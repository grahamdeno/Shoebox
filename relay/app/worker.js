/*
 * Shoebox app relay: the Cloudflare Worker for the Shoebox iPhone app (1.0 and later).
 *
 * Nine routes, nothing else. Everything the old relay (relay/perplexity-relay.js) also does for Shoebox 1
 * (AI calls, reminders, Apple Music, stats, beta sign-up, calendar and file pass-through) is not here on purpose.
 *
 *   GET  /preview?url=[&text=1]   a page's title, description, pictures and, with text=1, its readable text
 *   GET  /stock?q=&n=             Pixabay stock photos for a few generic words (24 hour cache)
 *   GET  /inbox                   waiting mail for this phone (sealed), its address and the sealing key held for it
 *   POST /inbox/address           make this phone's address { name, pub, purchase | beta }   needs Shoebox Plus
 *   POST /inbox/seal              register this phone's sealing key { pub, purchase | beta }  needs Shoebox Plus
 *   GET  /inbox/file?id=&n=       one attachment of a waiting mail (sealed)
 *   POST /inbox/ack               forget mail the phone has saved { ids }
 *   POST /me/delete               forget everything kept for this phone
 *   POST /request/beta|android    a request from the website: kept 180 days, and posted, sealed, to the owner's Shoebox
 *   (email)                       mail to <name>-<8 letters>@inmyshoebox.com waits here 7 days, sealed
 *
 * Sealed mail: before a message is stored it is sealed (HPKE, seal.js) to the public key the phone registered. What is
 * stored holds no sender, subject, text, link or attachment in the clear, and this Worker cannot open it. Cloudflare's
 * email system and this Worker see a message in memory while it is delivered; nothing readable is written.
 * Collecting mail, files, ack and delete are never gated by a purchase; making an address and registering a key are.
 *
 * What it keeps, and for how long (the privacy policy says the same):
 *   mail and attachments   7 days, or until the phone acknowledges them (sealed)
 *   address and box        90 days after the phone last asked, then gone
 *   purchase seats         the transaction number and the boxes it opened (up to 5): 90 days from the last time one of them asked
 *   counters               a day or an hour, then gone; addresses appear only as salted hashes
 * Search words, link addresses and mail text are never logged.
 */
import { verifyPurchase, verifyBetaApp, PurchaseError, b64decode } from "./purchase.js";
import { APPLE_ROOT_CA_G3_B64 } from "./apple-root-g3.js";
import { sealJSON, seal, isPublicKey, fromBase64 } from "./seal.js";

export const APP_RELAY_VERSION = 2;

const ALLOWED_ORIGINS = ["https://inmyshoebox.com"];
const MAIL_TTL = 7 * 86400;          // waiting mail and attachments
const BOX_TTL = 90 * 86400;          // an address and its box, from the last time the phone asked
const TOUCH_AFTER = 86400;           // refresh the box at most once a day
const MINT_PER_NETWORK_DAILY = 5;    // new addresses per network per day
const MINT_PER_BOX_DAILY = 3;        // renames per phone per day
const MINT_DAILY_CAP = 300;          // new addresses for everyone per day (MINT_DAILY_CAP overrides)
const MAILBOX_DAILY_CAP = 40;        // mails a single box accepts per day (MAILBOX_DAILY_CAP overrides)
const PREVIEW_HOURLY = 240;          // previews per network per hour
const PURCHASE_CHECKS_HOURLY = 30;   // purchase checks per network per hour (they cost CPU)
const BOXES_PER_PURCHASE = 5;        // one purchase opens at most this many boxes
const SUFFIX_LENGTH = 8;
const ALIAS_RE = new RegExp(`^([a-z][a-z0-9]{0,15}-[a-z2-9]{${SUFFIX_LENGTH}})@`);

function allowed(origin) {
  return ALLOWED_ORIGINS.includes(origin) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
}

function corsHeaders(origin) {
  return {
    "access-control-allow-origin": allowed(origin) ? origin : ALLOWED_ORIGINS[0],
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "content-type, x-inbox-key",
    "access-control-expose-headers": "retry-after",
    "access-control-max-age": "86400",
    vary: "origin",
  };
}

function json(status, message, headers) {
  return new Response(JSON.stringify({ error: { message } }), { status, headers: { ...headers, "content-type": "application/json" } });
}

async function sha256(text) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const dayOf = (t = Date.now()) => new Date(t).toISOString().slice(0, 10);
async function spent(kv, key) { return parseInt(await kv.get(key), 10) || 0; }

/** The network a request came from: the address, or its first 64 bits for IPv6 (one home or phone gets a whole /64). */
export function networkOf(request) {
  const ip = request.headers.get("cf-connecting-ip") || "unknown";
  return ip.includes(":") ? ip.toLowerCase().split(":").slice(0, 4).join(":") : ip;
}

/** Counts one use against `scope` for this network. Returns true while under `max` for the window (seconds). */
export async function underLimit(env, request, scope, max, window) {
  const kv = env.SHOEBOX;
  if (!kv) return true;
  const ip = networkOf(request);
  const slot = Math.floor(Date.now() / (window * 1000));
  const key = `lim:${scope}:${(await sha256(`${scope}:${ip}`)).slice(0, 24)}:${slot}`;
  const used = await spent(kv, key);
  if (used >= max) return false;
  await kv.put(key, String(used + 1), { expirationTtl: window * 2 });
  return true;
}

const RELAY = {
  /** Mail sent to a personal address. An address nobody holds is dropped without an answer, so bounces never
   *  reveal which addresses exist. */
  async email(message, env) {
    if (!env.SHOEBOX) return;
    const box = await mailBox(env, message.to);
    if (!box) return;
    // A real address that can't take this mail says so, so the person who forwarded it knows it did not arrive.
    // (Only someone who already sent to a real address learns that it exists.)
    // No sealing key, no mail: nothing is ever stored in the clear.
    const held = await env.SHOEBOX.get(`box:${box}`, "json");
    if (!held || !isPublicKey(held.pub)) { message.setReject("Open Shoebox to finish setting up your address."); return; }
    const capKey = `cap:${box}:${dayOf()}`;
    const used = await spent(env.SHOEBOX, capKey);
    if (used >= (parseInt(env.MAILBOX_DAILY_CAP, 10) || MAILBOX_DAILY_CAP)) { message.setReject("This Shoebox has had enough mail today. Try again tomorrow."); return; }
    if (message.rawSize && message.rawSize > 12e6) { message.setReject("Too large for Shoebox (12 MB)."); return; }
    const raw = await new Response(message.raw).arrayBuffer();
    if (raw.byteLength > 12e6) { message.setReject("Too large for Shoebox (12 MB)."); return; }
    await env.SHOEBOX.put(capKey, String(used + 1), { expirationTtl: 2 * 86400 });
    const { files, ...mail } = parseMail(new TextDecoder("utf-8", { fatal: false }).decode(raw));
    const id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
    // Each attachment is sealed on its own, then the mail: the stored mail names no sender, subject or text.
    for (const [n, f] of files.entries()) {
      const sealed = await seal(held.pub, fromBase64(f.data), `${box}:${id}:${n}`);
      await env.SHOEBOX.put(`a:${box}:${id}:${n}`, JSON.stringify({ v: 1, ...sealed }), { expirationTtl: MAIL_TTL });
    }
    const attachments = files.map((f, n) => ({ n, name: f.name, type: f.type, size: f.size }));
    const sealed = await sealJSON(held.pub, { from: message.from, ...mail, attachments }, `${box}:${id}`);
    await env.SHOEBOX.put(`m:${box}:${id}`, JSON.stringify({ v: 1, id, at: Date.now(), ...sealed }), { expirationTtl: MAIL_TTL });
  },

  async fetch(request, env = {}, ctx = null) {
    try { return await RELAY.handle(request, env, ctx); } catch (e) {
      // The message is not passed on: it could hold a link, search words or a key.
      return json(500, "The relay hit a problem.", corsHeaders(request.headers.get("origin") || ""));
    }
  },

  async handle(request, env = {}) {
    const origin = request.headers.get("origin") || "";
    const cors = corsHeaders(origin);
    if (!allowed(origin)) return json(403, "This relay only serves Shoebox.", cors);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    const { pathname, searchParams } = new URL(request.url);
    if (request.method === "GET" && pathname === "/preview") {
      if (!(await underLimit(env, request, "preview", PREVIEW_HOURLY, 3600))) {
        return json(429, "Too many previews from this network. Try again in an hour.", { ...cors, "retry-after": "3600" });
      }
      return preview(searchParams.get("url"), cors, searchParams.get("text") === "1");
    }
    if (request.method === "GET" && pathname === "/stock") return stock(request, env, searchParams, cors, origin);
    if (request.method === "POST" && pathname === "/me/delete") return deleteMe(request, env, cors);
    if (["/inbox", "/inbox/ack", "/inbox/file", "/inbox/address", "/inbox/seal"].includes(pathname)) return inboxRoute(request, env, pathname, cors);
    if (request.method === "POST" && (pathname === "/request/beta" || pathname === "/request/android")) return requestRoute(request, env, pathname.split("/")[2], cors);
    return json(404, "Not found.", cors);
  },
};
export default RELAY;

/* ---- Link previews ----
 * Fetch the page (first 400 KB is plenty for the <head>), read its Open Graph
 * and Twitter card tags, and return { image, title, description, site }.
 * Only public http(s) addresses; private and local hosts are refused.
 */
const PRIVATE_HOST = /^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|0\.|\[?::1\]?$|.*\.local$|.*\.internal$)/i;

export function parseMeta(html, base) {
  const meta = {};
  for (const tag of html.match(/<meta\b[^>]*>/gi) || []) {
    const key = (tag.match(/\b(?:property|name)\s*=\s*["']([^"']+)["']/i) || [])[1];
    const val = (tag.match(/\bcontent\s*=\s*["']([^"']*)["']/i) || [])[1];
    if (key && val != null && !(key.toLowerCase() in meta)) meta[key.toLowerCase()] = decode(val.trim());
  }
  const titleTag = (html.match(/<title[^>]*>([^<]*)<\/title>/i) || [])[1];
  const pick = (...keys) => keys.map((k) => meta[k]).find(Boolean) || "";
  let image = pick("og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src");
  if (image) { try { image = new URL(image, base).href; } catch { image = ""; } }
  if (image && !/^https?:\/\//.test(image)) image = "";
  const abs = (u) => { try { u = new URL(u, base).href; } catch { return ""; } return /^https?:\/\//.test(u) ? u : ""; };
  const tw = pick("twitter:image", "twitter:image:src");
  return {
    image: image || null,
    imageW: parseInt(meta["og:image:width"], 10) || null,
    imageH: parseInt(meta["og:image:height"], 10) || null,
    imageAlt: pick("og:image:alt", "twitter:image:alt").slice(0, 160) || null,
    twitterImage: tw ? abs(tw) || null : null,
    title: (pick("og:title", "twitter:title") || decode((titleTag || "").trim())).slice(0, 200) || null,
    description: pick("og:description", "twitter:description", "description").slice(0, 300) || null,
    site: pick("og:site_name").slice(0, 80) || null,
  };
}

function decode(s) {
  return String(s).replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#0?39;|&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n)).replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)));
}

async function preview(target, cors, wantText = false) {
  const out = (status, body) => new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json", "cache-control": "public, max-age=86400" } });
  let url;
  try { url = new URL(target); } catch { return out(400, { error: { message: "Not a link." } }); }
  if (!/^https?:$/.test(url.protocol) || PRIVATE_HOST.test(url.hostname)) return out(400, { error: { message: "Only public web links." } });
  let res;
  try {
    res = await fetch(url.href, {
      redirect: "follow",
      headers: { "user-agent": "Mozilla/5.0 (compatible; EditionPreview/1.0; +https://inmyshoebox.com/)", accept: "text/html,application/xhtml+xml" },
      cf: { cacheTtl: 86400, cacheEverything: true },
    });
  } catch {
    return out(200, { image: null, title: null, description: null, site: null });
  }
  if (!res.ok || !/html/i.test(res.headers.get("content-type") || "")) return out(200, { image: null, title: null, description: null, site: null });
  // Read up to 1.5 MB: past the <head> and into the article, so its photos can be offered too.
  const reader = res.body.getReader();
  const dec = new TextDecoder();
  let html = "";
  while (html.length < 1500000) {
    const { done, value } = await reader.read();
    if (done) break;
    html += dec.decode(value, { stream: true });
  }
  try { reader.cancel(); } catch { /* already closed */ }
  const base = res.url || url.href;
  const meta = parseMeta(html, base);
  const images = pageImages(html, base, meta);
  // No preview picture: the article's own first large image.
  if (!meta.image) meta.image = images[0] ? images[0].src : null;
  const { imageW, imageH, imageAlt, twitterImage, ...rest } = meta;
  const body = { ...rest, images };
  return out(200, wantText ? { ...body, text: pageText(html) } : body);
}

/*
 * The first large image in the article (or main, or body). Skips icons, logos,
 * avatars, badges, sprites, tracking pixels, ads and anything marked small, and
 * takes the largest size a srcset offers. Returns an absolute address or null.
 */
const NOT_A_PHOTO = /(logo|icon|favicon|sprite|avatar|gravatar|badge|emoji|spinner|loader|pixel|spacer|blank|1x1|tracking|beacon|placeholder|button|banner|advert|\bads?\b|doubleclick|adserver|share|social|facebook|twitter|linkedin|pinterest)/i;

export function articleImage(html, base) {
  const first = articleImages(html, base, 1)[0];
  return first ? first.src : null;
}

/** Every usable photo in the article, in page order, up to `max`, without duplicates. */
export function articleImages(html, base, max = 8) {
  const h = String(html).replace(/<(script|style|noscript|nav|header|footer|aside|form)\b[\s\S]*?<\/\1>/gi, " ");
  const pick = (tag) => { const m = h.match(new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i")); return m ? m[1] : ""; };
  const scope = pick("article") || pick("main") || pick("body") || h;
  const attr = (tag, name) => (tag.match(new RegExp(`\\b${name}\\s*=\\s*["']([^"']*)["']`, "i")) || [])[1] || "";
  const out = [];
  for (const tag of scope.match(/<img\b[^>]*>/gi) || []) {
    if (out.length >= max) break;
    const w = parseInt(attr(tag, "width"), 10), hgt = parseInt(attr(tag, "height"), 10);
    if ((w && w < 300) || (hgt && hgt < 200)) continue;
    const cls = `${attr(tag, "class")} ${attr(tag, "id")} ${attr(tag, "alt")}`;
    if (NOT_A_PHOTO.test(cls) || attr(tag, "role") === "presentation" || attr(tag, "aria-hidden") === "true") continue;
    // The largest srcset entry, else the lazy-load source, else src.
    const set = (attr(tag, "srcset") || attr(tag, "data-srcset")).split(",").map((p) => p.trim().split(/\s+/))
      .filter((p) => p[0]).map(([u, d]) => ({ u, n: parseFloat(d) || 0 })).sort((a, b) => b.n - a.n);
    let src = (set[0] && set[0].u) || attr(tag, "data-src") || attr(tag, "data-original") || attr(tag, "data-lazy-src") || attr(tag, "src");
    if (!src || /^data:/i.test(src) || /\.svg(\?|$)/i.test(src) || /\.gif(\?|$)/i.test(src) || NOT_A_PHOTO.test(src)) continue;
    try { src = new URL(decode(src), base).href; } catch { continue; }
    if (!/^https?:\/\//.test(src) || out.some((o) => o.src === src)) continue;
    out.push({ src, w: w || null, h: hgt || null, alt: decode(attr(tag, "alt")).slice(0, 160) || null, from: "article" });
  }
  return out;
}

/**
 * Picture candidates for the picker: the page's preview picture, its Twitter
 * card picture if different, then the article's own photos. Logos and icons
 * are skipped here; the app drops anything small or oddly shaped once loaded.
 */
export function pageImages(html, base, meta, max = 8) {
  const list = [];
  const add = (c) => { if (c && c.src && !list.some((o) => o.src === c.src) && !NOT_A_PHOTO.test(c.src.split("?")[0].split("/").pop())) list.push(c); };
  if (meta.image) add({ src: meta.image, w: meta.imageW || null, h: meta.imageH || null, alt: meta.imageAlt || null, from: "preview" });
  if (meta.twitterImage) add({ src: meta.twitterImage, w: null, h: null, alt: null, from: "preview" });
  for (const c of articleImages(html, base, max)) add(c);
  return list.slice(0, max);
}

/**
 * The readable text of a page: its article (or main, or body), without
 * scripts, menus, headers, footers and asides, as paragraphs. Max 15,000 chars.
 */
export function pageText(html) {
  let h = String(html)
    .replace(/<(script|style|noscript|svg|nav|header|footer|aside|form|iframe|template)\b[\s\S]*?<\/\1>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ");
  const pick = (tag) => { const m = h.match(new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i")); return m ? m[1] : ""; };
  const scope = pick("article") || pick("main") || pick("body") || h;
  const paras = [];
  const re = /<(p|h[1-4]|li|blockquote)\b[^>]*>([\s\S]*?)<\/\1>/gi;
  let m;
  while ((m = re.exec(scope)) && paras.join("\n\n").length < 15000) {
    const t = decode(m[2].replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
    if (t.length >= 30 || /^h/i.test(m[1]) && t.length > 3) paras.push(t);
  }
  const text = paras.length ? paras.join("\n\n") : decode(scope.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
  return text.slice(0, 15000) || null;
}

/* ---- Stock photo search (Pixabay) ----
 * GET /stock?q=<a few generic words>&n=6. For the new Shoebox app; /photo above stays Openverse for Shoebox 1. Only https://inmyshoebox.com may ask.
 * Privacy: the search words, the caller's address and the outbound URL (it holds
 * the key) are never logged or put in an error message. The rate counter keeps
 * only a salted hash of the address. Pixabay asks for results to be cached 24 hours.
 */
const STOCK_ORIGIN = "https://inmyshoebox.com";
const PIXABAY = "https://pixabay.com";
const STOCK_CACHE_SECONDS = 86400;
const STOCK_HOURLY = 60;

function pixabayBase(env) {
  // Local testing only: a mock Pixabay on localhost. Anything else uses the real address.
  const b = String(env.PIXABAY_BASE_URL || "");
  return /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(b) ? b : PIXABAY;
}

async function stock(request, env, params, cors, origin) {
  const headers = { ...cors, "content-type": "application/json", "access-control-expose-headers": "retry-after, x-cache, x-reason" };
  const out = (status, body, extra = {}) => new Response(JSON.stringify(body), { status, headers: { ...headers, "cache-control": status === 200 ? "public, max-age=86400" : "no-store", ...extra } });
  try {
    if (origin !== STOCK_ORIGIN) return out(403, { error: { message: "This relay only serves Shoebox." } });
    const query = String(params.get("q") || "").trim().replace(/\s+/g, " ");
    if (!query || query.length > 80) return out(400, { error: { message: "Send 1 to 80 characters of search words." } });
    const asked = parseInt(params.get("n") || "", 10);
    const n = Number.isFinite(asked) && asked >= 1 ? Math.min(asked, 8) : 6;

    // One cache entry per phrase (lowercased, trimmed) and count. The key holds no address, origin or API key.
    const cache = typeof caches !== "undefined" ? caches.default : null;
    const cacheKey = new Request(`https://stock-cache.shoebox.invalid/v1?n=${n}&q=${encodeURIComponent(query.toLowerCase())}`);
    const hit = cache ? await cache.match(cacheKey) : null;
    if (hit) return out(200, await hit.json(), { "x-cache": "HIT" });

    // A search that reaches Pixabay counts against this network: about 60 an hour, then 429.
    // A counter that can't be read or written (KV limits) never stops the search: the hourly cap is a courtesy.
    const kv = env.SHOEBOX;
    if (kv) {
      const ip = request.headers.get("cf-connecting-ip") || "unknown";
      const hour = Math.floor(Date.now() / 3600e3);
      const rk = `stk:${(await sha256(`stock:${ip}`)).slice(0, 32)}:${hour}`;
      let used = 0;
      try { used = await spent(kv, rk); } catch { console.log("stock: counter read failed"); }
      const limit = parseInt(env.STOCK_HOURLY_LIMIT, 10) || STOCK_HOURLY;
      if (used >= limit) {
        const wait = String(Math.max(1, (hour + 1) * 3600 - Math.floor(Date.now() / 1000)));
        return out(429, { photos: [], error: { message: "Too many photo searches from this network. Try again in an hour." } }, { "retry-after": wait });
      }
      try { await kv.put(rk, String(used + 1), { expirationTtl: 7200 }); } catch { console.log("stock: counter write failed"); }
    }

    // On a failure, a short reason (never the words, the address or the key) in x-reason and the log.
    const fail = (reason) => { console.log(`stock: ${reason}`); return out(502, { photos: [] }, { "x-reason": reason }); };
    if (!env.PIXABAY_API_KEY) return fail("no-key");
    // Pixabay's per_page minimum is 3: ask for at least 3, then keep n.
    const qs = new URLSearchParams({ key: env.PIXABAY_API_KEY, q: query, image_type: "photo", orientation: "vertical", safesearch: "true", min_width: "600", per_page: String(Math.max(n, 3)) });
    let res;
    try {
      res = await fetch(`${pixabayBase(env)}/api/?${qs}`, { headers: { accept: "application/json" }, signal: AbortSignal.timeout(8000) });
    } catch {
      return fail("pixabay-unreachable"); // never pass the error on: it could name the URL, which holds the key
    }
    if (!res.ok) return fail(`pixabay-${res.status}`);
    const data = await res.json().catch(() => null);
    if (!data || typeof data !== "object" || !Array.isArray(data.hits)) return fail("pixabay-bad-answer");
    const body = { photos: pixabayPhotos(data.hits, n) };
    if (cache) {
      const keep = new Response(JSON.stringify(body), { headers: { "content-type": "application/json", "cache-control": `public, max-age=${STOCK_CACHE_SECONDS}` } });
      await cache.put(cacheKey, keep).catch(() => {});
    }
    return out(200, body, { "x-cache": "MISS" });
  } catch (e) {
    // Never pass the underlying message on: it could contain the search words or the key. Only its kind.
    const kind = (e && e.name) || "error";
    console.log(`stock: threw ${kind}`);
    return out(502, { photos: [] }, { "x-reason": `threw-${kind}` });
  }
}

/** Pixabay's answer, trimmed to what the app shows. */
export function pixabayPhotos(hits, n = 8) {
  return (Array.isArray(hits) ? hits : [])
    .filter((p) => p && p.largeImageURL)
    .slice(0, n)
    .map((p) => ({
      id: String(p.id),
      url: p.largeImageURL,
      width: Number(p.imageWidth) || 0,
      height: Number(p.imageHeight) || 0,
      alt: p.tags || "",
      by: p.user || "",
      page: p.pageURL || "",
    }));
}


/* ---- Mailboxes ----
 * A phone's inbox key (made on the phone, never leaves it except in this header) hashes to its box id.
 * Its address is <name>-<8 letters or digits>@inmyshoebox.com; alias:<slug> points at the box.
 * No phone is the owner by being first. The one shared address, if EMAIL_ADDRESS is set, delivers to the
 * phone whose key is the OWNER_INBOX_KEY secret, and to nobody otherwise.
 */
export const mailDomains = (env) => String(env.EMAIL_DOMAIN || "inmyshoebox.com").toLowerCase().split(",").map((d) => d.trim()).filter(Boolean);
const mailDomain = (env) => mailDomains(env)[0] || "inmyshoebox.com";
/** The name part of an address: letters and digits, starting with a letter, up to 16. */
export function addressName(name) {
  const n = String(name || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]/g, "").replace(/^[0-9]+/, "").slice(0, 16);
  return n || "shoebox";
}
export async function boxOf(key) { return (await sha256(`inbox:${key}`)).slice(0, 20); }
export function newSlug(name) {
  const abc = "abcdefghijkmnpqrstuvwxyz23456789"; // 32 letters and digits, no look-alikes (l, o, 0, 1)
  return `${addressName(name)}-${Array.from(crypto.getRandomValues(new Uint8Array(SUFFIX_LENGTH)), (b) => abc[b % abc.length]).join("")}`;
}

/** The box a recipient address delivers to, or null (nobody holds it). */
export async function mailBox(env, to) {
  const addr = String(to || "").trim().toLowerCase();
  if (!addr || !env.SHOEBOX) return null;
  if (env.EMAIL_ADDRESS && addr === String(env.EMAIL_ADDRESS).toLowerCase()) {
    return env.OWNER_INBOX_KEY ? boxOf(env.OWNER_INBOX_KEY) : null;
  }
  const m = addr.match(ALIAS_RE);
  if (!m || !mailDomains(env).includes(addr.split("@")[1])) return null;
  return (await env.SHOEBOX.get(`alias:${m[1]}`)) || null;
}

/** This phone's address, or null before one is made. Renews the box's 90 days at most once a day. */
async function currentAddress(env, box) {
  const kv = env.SHOEBOX;
  const cur = await kv.get(`box:${box}`, "json");
  if (!cur) return null;
  if (Date.now() - (cur.at || 0) > TOUCH_AFTER * 1000) {
    await kv.put(`alias:${cur.slug}`, box, { expirationTtl: BOX_TTL });
    await kv.put(`box:${box}`, JSON.stringify({ ...cur, at: Date.now() }), { expirationTtl: BOX_TTL });
    if (cur.buy) { const rec = await kv.get(`buy:${cur.buy}`); if (rec) await kv.put(`buy:${cur.buy}`, rec, { expirationTtl: BOX_TTL }); }
  }
  return `${cur.slug}@${mailDomain(env)}`;
}

/** Makes (or replaces) this phone's address. Returns { address } or { status, message } when refused.
 *  `pub` is the phone's sealing key and `buy` the purchase it was opened with; both stay in the box record. */
export async function mintAddress(env, request, box, name, { pub, buy } = {}) {
  const kv = env.SHOEBOX;
  const day = dayOf();
  const cur = await kv.get(`box:${box}`, "json");
  // A phone that already has an address may ask for a new one only a few times a day.
  if (cur) {
    const k = `mintbox:${box}:${day}`, n = await spent(kv, k);
    if (n >= MINT_PER_BOX_DAILY) return { status: 429, message: "That's enough new addresses for today. Try again tomorrow." };
    await kv.put(k, String(n + 1), { expirationTtl: 2 * 86400 });
  }
  // New addresses are limited per network and for everyone.
  const ip = networkOf(request);
  const netKey = `mintnet:${(await sha256(`mint:${ip}`)).slice(0, 24)}:${day}`, net = await spent(kv, netKey);
  if (net >= MINT_PER_NETWORK_DAILY) return { status: 429, message: "Too many new addresses from this network today. Try again tomorrow." };
  const allKey = `mintall:${day}`, all = await spent(kv, allKey);
  if (all >= (parseInt(env.MINT_DAILY_CAP, 10) || MINT_DAILY_CAP)) return { status: 503, message: "Shoebox can't make new addresses right now. Try again tomorrow." };
  let slug = newSlug(name);
  for (let i = 0; i < 5 && await kv.get(`alias:${slug}`); i++) slug = newSlug(name);
  if (await kv.get(`alias:${slug}`)) return { status: 409, message: "Couldn't find a free address. Try again." };
  await kv.put(netKey, String(net + 1), { expirationTtl: 2 * 86400 });
  await kv.put(allKey, String(all + 1), { expirationTtl: 2 * 86400 });
  if (cur && cur.slug !== slug) await kv.delete(`alias:${cur.slug}`);
  await kv.put(`alias:${slug}`, box, { expirationTtl: BOX_TTL });
  await kv.put(`box:${box}`, JSON.stringify({ slug, at: Date.now(), pub: pub || (cur && cur.pub) || null, buy: buy || (cur && cur.buy) || null }), { expirationTtl: BOX_TTL });
  return { address: `${slug}@${mailDomain(env)}` };
}

/* ---- Shoebox Plus: the purchase that opens a box ----
 * `buy:<originalTransactionId>` holds { boxes: [box ids] }, up to 5, so one purchase can't make addresses for everyone.
 * A box that expired (90 days idle) no longer counts. Collecting mail, files, ack and delete never ask for a purchase.
 */
const PURCHASE_REFUSED = "Shoebox Plus is needed to get an address.";
const FIVE_PHONES = "This purchase is already on five phones. Write to support@inmyshoebox.com.";
const FIVE_PHONES_BETA = "This Apple Account is already testing on five phones. Write to support@inmyshoebox.com.";
const fivePhones = (seat) => (String(seat).startsWith("beta-") ? FIVE_PHONES_BETA : FIVE_PHONES);

/** The owner's own address may register its sealing key without a purchase, until Shoebox Plus can be bought.
 *  `PLUS_OWNER_ADDRESS` names it ("graham-k3t7m2qa", the part before the @). Only the phone holding that
 *  address's inbox key reaches its box, so naming the address gives nobody else anything. It never makes a new
 *  address, takes no seat, and changes nothing for anyone else. Remove the variable once Plus is on sale. */
function ownerBox(env, cur) {
  const owner = String(env.PLUS_OWNER_ADDRESS || "").trim().toLowerCase().split("@")[0];
  return !!owner && !!cur && String(cur.slug || "").toLowerCase() === owner;
}

/* ---- Requests from the website: the iPhone beta and "tell me when it's on Android" ----
 * Kept as `req:<kind>:<id>` for 180 days so they can be exported, one per email address (asking again refreshes it),
 * and posted to the owner's Shoebox as sealed mail when the owner's address has a sealing key
 * (`REQUESTS_TO`, else `PLUS_OWNER_ADDRESS`). Nothing is sent anywhere else. A few a network a day.
 */
const REQUEST_TTL = 180 * 86400;
const REQUESTS_PER_NETWORK_DAILY = 3;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** The answers as plain short text: strings up to 1,200 characters, lists of up to 10 short strings. */
export function cleanRequest(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return "Bad request.";
  const line = (v, n) => String(v ?? "").replace(/[\u0000-\u001f]+/g, " ").trim().slice(0, n);
  const email = line(body.email, 120).toLowerCase();
  if (!EMAIL_RE.test(email)) return "Please add your email address.";
  const answers = {};
  for (const [k, v] of Object.entries(body).slice(0, 16)) {
    if (["email", "name", "website", "kind"].includes(k) || !/^[a-z_]{1,24}$/.test(k)) continue;
    if (Array.isArray(v)) answers[k] = v.slice(0, 10).map((x) => line(x, 80)).filter(Boolean);
    else if (v !== null && typeof v === "object") continue;
    else answers[k] = String(v ?? "").trim().slice(0, 1200);
  }
  return { email, name: line(body.name, 80), answers };
}

async function requestRoute(request, env, kind, cors) {
  const kv = env.SHOEBOX;
  if (!kv) return json(501, "Requests aren't set up. Write to support@inmyshoebox.com instead.", cors);
  const text = await request.text();
  if (text.length > 8000) return json(413, "That's too long.", cors);
  let body;
  try { body = JSON.parse(text); } catch { return json(400, "Bad request.", cors); }
  const ok = () => new Response(JSON.stringify({ ok: true }), { headers: { ...cors, "content-type": "application/json" } });
  if (body && body.website) return ok(); // the hidden field only a bot fills in
  const r = cleanRequest(body);
  if (typeof r === "string") return json(400, r, cors);
  if (!(await underLimit(env, request, "request", REQUESTS_PER_NETWORK_DAILY, 86400))) {
    return json(429, "Thanks, we have your request. Try again tomorrow if something changed.", cors);
  }
  const who = (await sha256(`${kind}:${r.email}`)).slice(0, 32);
  const seen = await kv.get(`reqe:${kind}:${who}`);
  const id = seen || `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  await kv.put(`req:${kind}:${id}`, JSON.stringify({ id, kind, at: Date.now(), ...r }), { expirationTtl: REQUEST_TTL });
  if (seen) return ok();
  await kv.put(`reqe:${kind}:${who}`, id, { expirationTtl: REQUEST_TTL });
  await postToOwner(env, kind, id, r);
  return ok();
}

/** One new request as a post in the owner's Shoebox, sealed like any mail. Quietly nothing without a sealing key. */
async function postToOwner(env, kind, id, r) {
  const owner = String(env.REQUESTS_TO || env.PLUS_OWNER_ADDRESS || "").trim().toLowerCase().split("@")[0];
  if (!owner) return;
  const box = await env.SHOEBOX.get(`alias:${owner}`);
  const held = box ? await env.SHOEBOX.get(`box:${box}`, "json") : null;
  if (!held || !isPublicKey(held.pub)) return;
  const who = r.name || r.email;
  const lines = [`${kind === "android" ? "Android request" : "Beta request"} from ${who} (${r.email}).`];
  for (const [k, v] of Object.entries(r.answers)) lines.push(`${k}: ${Array.isArray(v) ? v.join(", ") : v}`);
  const sealed = await sealJSON(held.pub, {
    from: r.email, fromName: r.name || undefined,
    subject: `${kind === "android" ? "Android request" : "Beta request"} from ${who}`,
    text: lines.join("\n"), links: [], attachments: [],
  }, `${box}:${id}`);
  await env.SHOEBOX.put(`m:${box}:${id}`, JSON.stringify({ v: 1, id, at: Date.now(), ...sealed }), { expirationTtl: MAIL_TTL });
}

/** The certificates to trust as Apple's root: the embedded one, plus a test root only when a test sets one. */
function purchaseRoots(env) {
  return [APPLE_ROOT_CA_G3_B64, env.TEST_PURCHASE_ROOT].filter(Boolean).map((b) => b64decode(b));
}

/** Checks the signed purchase in a request, or in TestFlight and App Review the signed app transaction (`beta`).
 *  Returns { originalTransactionId } (the seat this box takes) or { status, message }.
 *  Beta seats are `beta-<appTransactionId>`, so they sit beside purchases in `buy:` and get the same five-phone limit and
 *  the same seat back on Delete everything. A real purchase always wins when the phone sends both.
 *  `BETA_PLUS` "0" stops free addresses for testers at once, without a deploy; so does `ALLOW_SANDBOX` "0". Addresses
 *  already made keep working either way (collecting is never gated). */
async function checkPurchase(env, request, jws, beta) {
  const hasPurchase = typeof jws === "string" && !!jws;
  const hasBeta = typeof beta === "string" && !!beta && env.BETA_PLUS !== "0" && env.ALLOW_SANDBOX !== "0";
  if (!hasPurchase && !hasBeta) return { status: 402, message: PURCHASE_REFUSED };
  // Checking costs CPU: a network gets a few dozen an hour.
  if (!(await underLimit(env, request, "purchase", PURCHASE_CHECKS_HOURLY, 3600))) return { status: 429, message: "Too many tries from this network. Try again in an hour." };
  try {
    if (hasPurchase) {
      const bought = await verifyPurchase(jws, { roots: purchaseRoots(env), allowSandbox: env.ALLOW_SANDBOX !== "0" });
      return { originalTransactionId: bought.originalTransactionId };
    }
    const tester = await verifyBetaApp(beta, { roots: purchaseRoots(env) });
    return { originalTransactionId: `beta-${tester.betaId}` };
  } catch (e) {
    if (!(e instanceof PurchaseError)) throw e;
    return { status: 402, message: PURCHASE_REFUSED };
  }
}

/** The boxes this purchase has opened that still exist. */
async function seatsOf(kv, otid) {
  const rec = await kv.get(`buy:${otid}`, "json");
  const live = [];
  for (const id of (rec && rec.boxes) || []) if (await kv.get(`box:${id}`)) live.push(id);
  return live;
}

/** Is there a seat for this box on this purchase? (A box that already holds one always has.) */
async function seatFree(kv, otid, box) {
  const live = await seatsOf(kv, otid);
  return live.includes(box) || live.length < BOXES_PER_PURCHASE;
}

/** Records the box on the purchase, and takes it off the purchase it was on before, if that was another one. */
async function takeSeat(kv, otid, box, before) {
  if (before && before !== otid) await freeSeat(kv, before, box);
  const live = await seatsOf(kv, otid);
  if (!live.includes(box)) live.push(box);
  await kv.put(`buy:${otid}`, JSON.stringify({ boxes: live }), { expirationTtl: BOX_TTL });
}

async function freeSeat(kv, otid, box) {
  const left = (await seatsOf(kv, otid)).filter((id) => id !== box);
  if (left.length) await kv.put(`buy:${otid}`, JSON.stringify({ boxes: left }), { expirationTtl: BOX_TTL });
  else await kv.delete(`buy:${otid}`);
}

const KEY_RE = /^[\w-]{24,80}$/;

/** Every key under a prefix, following the cursor past the first 1,000. */
async function listAll(kv, prefix) {
  const names = [];
  let cursor;
  do {
    const page = await kv.list({ prefix, cursor });
    for (const k of page.keys) names.push(k.name);
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);
  return names;
}

/** Forget everything kept for one phone: its address, box record, waiting mail and attachments. */
async function deleteMe(request, env, cors) {
  const kv = env.SHOEBOX;
  if (!kv) return json(501, "No storage.", cors);
  const key = request.headers.get("x-inbox-key") || "";
  if (!KEY_RE.test(key)) return json(401, "No inbox key.", cors);
  const box = await boxOf(key);
  const cur = await kv.get(`box:${box}`, "json");
  if (cur) { await kv.delete(`alias:${cur.slug}`); await kv.delete(`box:${box}`); }
  let mail = 0;
  for (const prefix of [`m:${box}:`, `a:${box}:`]) {
    for (const name of await listAll(kv, prefix)) { await kv.delete(name); mail++; }
  }
  // The purchase gets its seat back, so it can open a box on the next phone. Safe to repeat: a second call finds nothing.
  if (cur && cur.buy) await freeSeat(kv, cur.buy, box);
  return new Response(JSON.stringify({ ok: true, mail }), { headers: { ...cors, "content-type": "application/json" } });
}

async function inboxRoute(request, env, pathname, cors) {
  const kv = env.SHOEBOX;
  if (!kv) return json(501, "The inbox isn't set up.", cors);
  const key = request.headers.get("x-inbox-key") || "";
  if (!KEY_RE.test(key)) return json(401, "No inbox key.", cors);
  const box = await boxOf(key);
  const send = (body) => new Response(JSON.stringify(body), { headers: { ...cors, "content-type": "application/json", "cache-control": "no-store" } });
  if (request.method === "GET" && pathname === "/inbox") {
    const mails = [];
    for (const name of (await listAll(kv, `m:${box}:`)).slice(0, 20)) { const m = await kv.get(name, "json"); if (m) mails.push(m); }
    const address = await currentAddress(env, box);
    // `pub` is the sealing key held for this phone, so the phone can tell when it needs to register its own.
    const held = address ? await kv.get(`box:${box}`, "json") : null;
    return send({ mails, address, pub: (held && held.pub) || null });
  }
  if (request.method === "POST" && pathname === "/inbox/address") {
    const { name, pub, purchase, beta } = await request.json().catch(() => ({}));
    if (!isPublicKey(pub)) return json(400, "Update Shoebox to get an address.", cors);
    const bought = await checkPurchase(env, request, purchase, beta);
    if (!bought.originalTransactionId) return json(bought.status, bought.message, cors);
    if (!(await seatFree(kv, bought.originalTransactionId, box))) return json(403, fivePhones(bought.originalTransactionId), cors);
    const before = (await kv.get(`box:${box}`, "json"))?.buy || null;
    const made = await mintAddress(env, request, box, name || "", { pub, buy: bought.originalTransactionId });
    if (!made.address) return json(made.status, made.message, cors);
    await takeSeat(kv, bought.originalTransactionId, box, before);
    return send({ address: made.address });
  }
  if (request.method === "POST" && pathname === "/inbox/seal") {
    const { pub, purchase, beta } = await request.json().catch(() => ({}));
    if (!isPublicKey(pub)) return json(400, "Bad key.", cors);
    const cur = await kv.get(`box:${box}`, "json");
    if (!cur) return json(404, "Get an address first.", cors);
    if (ownerBox(env, cur)) {
      await kv.put(`box:${box}`, JSON.stringify({ ...cur, pub, at: Date.now() }), { expirationTtl: BOX_TTL });
      await kv.put(`alias:${cur.slug}`, box, { expirationTtl: BOX_TTL });
      return send({ ok: true });
    }
    const bought = await checkPurchase(env, request, purchase, beta);
    if (!bought.originalTransactionId) return json(bought.status, bought.message, cors);
    if (!(await seatFree(kv, bought.originalTransactionId, box))) return json(403, fivePhones(bought.originalTransactionId), cors);
    await kv.put(`box:${box}`, JSON.stringify({ ...cur, pub, buy: bought.originalTransactionId, at: Date.now() }), { expirationTtl: BOX_TTL });
    await kv.put(`alias:${cur.slug}`, box, { expirationTtl: BOX_TTL });
    await takeSeat(kv, bought.originalTransactionId, box, cur.buy || null);
    return send({ ok: true });
  }
  if (request.method === "GET" && pathname === "/inbox/file") {
    const q = new URL(request.url).searchParams, id = q.get("id") || "", n = q.get("n") || "";
    if (!/^[\w-]+$/.test(id) || !/^\d$/.test(n)) return json(400, "Bad file.", cors);
    const data = await kv.get(`a:${box}:${id}:${n}`);
    if (!data) return json(404, "That attachment is gone.", cors);
    // Sealed attachments are stored as JSON { v, enc, ct }. Anything else is a plain one from before sealing (base64).
    if (data.startsWith("{")) return send(JSON.parse(data));
    return send({ data });
  }
  if (request.method === "POST" && pathname === "/inbox/ack") {
    const { ids } = await request.json().catch(() => ({ ids: [] }));
    for (const id of (ids || []).slice(0, 50)) if (typeof id === "string" && /^[\w-]+$/.test(id)) {
      await kv.delete(`m:${box}:${id}`);
      for (let n = 0; n < 6; n++) await kv.delete(`a:${box}:${id}:${n}`);
    }
    return send({ ok: true });
  }
  return json(404, "Not found.", cors);
}

/* ---- A small mail reader: headers, multipart, base64 and quoted-printable ---- */

function decodeWords(s) {
  return String(s || "").replace(/=\?([^?]+)\?([BQbq])\?([^?]*)\?=/g, (_, cs, enc, txt) => {
    try {
      const bytes = /b/i.test(enc) ? Uint8Array.from(atob(txt), (c) => c.charCodeAt(0))
        : Uint8Array.from(txt.replace(/_/g, " ").replace(/=([0-9A-F]{2})/gi, (m, h) => String.fromCharCode(parseInt(h, 16))), (c) => c.charCodeAt(0));
      return new TextDecoder(/utf-?8/i.test(cs) ? "utf-8" : cs.toLowerCase().includes("1252") ? "windows-1252" : "iso-8859-1").decode(bytes);
    } catch { return txt; }
  }).replace(/\?=\s+=\?/g, "");
}

function splitHead(part) {
  const i = part.search(/\r?\n\r?\n/);
  const head = i < 0 ? part : part.slice(0, i), body = i < 0 ? "" : part.slice(i).replace(/^\r?\n\r?\n/, "");
  const headers = {};
  for (const line of head.replace(/\r?\n[ \t]+/g, " ").split(/\r?\n/)) {
    const c = line.indexOf(":");
    if (c > 0) headers[line.slice(0, c).trim().toLowerCase()] = line.slice(c + 1).trim();
  }
  return { headers, body };
}

function decodeBody(body, headers) {
  const enc = (headers["content-transfer-encoding"] || "").toLowerCase();
  const cs = (/charset="?([^";]+)/i.exec(headers["content-type"] || "") || [])[1] || "utf-8";
  let bytes;
  if (enc === "base64") { try { bytes = Uint8Array.from(atob(body.replace(/\s+/g, "")), (c) => c.charCodeAt(0)); } catch { return body; } }
  else if (enc === "quoted-printable") bytes = Uint8Array.from(body.replace(/=\r?\n/g, "").replace(/=([0-9A-F]{2})/gi, (m, h) => String.fromCharCode(parseInt(h, 16))), (c) => c.charCodeAt(0) & 255);
  else return body;
  try { return new TextDecoder(/utf-?8/i.test(cs) ? "utf-8" : cs.toLowerCase().includes("1252") ? "windows-1252" : "iso-8859-1").decode(bytes); } catch { return new TextDecoder().decode(bytes); }
}

function walk(part, out, depth = 0) {
  const { headers, body } = splitHead(part);
  const type = (headers["content-type"] || "text/plain").toLowerCase();
  const boundary = (/boundary="?([^";]+)"?/i.exec(headers["content-type"] || "") || [])[1];
  if (type.startsWith("multipart/") && boundary && depth < 6) {
    for (const p of body.split(`--${boundary}`).slice(1)) { if (!p.startsWith("--")) walk(p.replace(/^\r?\n/, ""), out, depth + 1); }
    return;
  }
  // PDFs and pictures (attached, or a flyer placed in the email) are kept as base64; tiny images are logos.
  if (type.startsWith("application/pdf") || /^image\/(png|jpe?g|gif|webp)/.test(type)) {
    if ((headers["content-transfer-encoding"] || "").toLowerCase() !== "base64") return;
    const data = body.replace(/[^A-Za-z0-9+/=]/g, "");
    const size = Math.floor(data.length * 3 / 4) - (data.endsWith("==") ? 2 : data.endsWith("=") ? 1 : 0);   // the real byte count, padding excluded
    const isPdf = type.startsWith("application/pdf");
    if (!isPdf && size < 20000) return;
    const name = decodeWords((/filename\*?="?([^";]+)"?/i.exec(headers["content-disposition"] || "") || /name="?([^";]+)"?/i.exec(headers["content-type"] || "") || [])[1] || (isPdf ? "attachment.pdf" : "picture"));
    out.files = out.files || [];
    const used = out.files.reduce((n, f) => n + f.size, 0);
    if (out.files.length < 6 && used + size <= 4e6) out.files.push({ name: name.slice(0, 120), type: isPdf ? "application/pdf" : type.split(";")[0].trim(), size, data });
    return;
  }
  if (/attachment/i.test(headers["content-disposition"] || "")) return;
  if (type.startsWith("text/plain") && !out.text) out.text = decodeBody(body, headers);
  else if (type.startsWith("text/html") && !out.html) out.html = decodeBody(body, headers);
}

const safeChar = (n, fallback) => { try { return n > 0 && n < 0x110000 ? String.fromCodePoint(n) : fallback; } catch { return fallback; } };

export function htmlToText(html) {
  return String(html || "")
    .replace(/<(script|style|head)\b[\s\S]*?<\/\1>/gi, " ")
    .replace(/<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi, (m, href, t) => `${t.replace(/<[^>]+>/g, "").trim()} (${href})`)
    .replace(/<(br|\/p|\/div|\/h\d|\/li|\/tr)\b[^>]*>/gi, "\n").replace(/<li\b[^>]*>/gi, "\n• ")
    .replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#39;|&rsquo;/g, "'").replace(/&quot;|&ldquo;|&rdquo;/g, '"')
    .replace(/&#x([0-9a-f]{1,6});/gi, (m, h) => safeChar(parseInt(h, 16), m)).replace(/&#(\d{1,7});/g, (m, d) => safeChar(+d, m))
    .replace(/\u00a0/g, " ").replace(/[ \t]+/g, " ").replace(/ *\n */g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

/** { subject, fromName, text, links } from a raw message. */
export function parseMail(raw) {
  const { headers } = splitHead(raw);
  const out = {};
  walk(raw, out);
  const text = (out.text && out.text.trim().length > 40 ? out.text : htmlToText(out.html || out.text || "")).slice(0, 60000);
  const links = [...new Set((`${out.html || ""} ${text}`).match(/https?:\/\/[^\s"'<>)]+/g) || [])]
    .filter((u) => !/unsubscribe|manage.?preferences|list-manage|mailchimp\.com\/track|\.(png|jpe?g|gif)(\?|$)/i.test(u)).slice(0, 30);
  const from = decodeWords(headers.from || "");
  return {
    subject: decodeWords(headers.subject || "").slice(0, 200),
    fromName: (/^"?([^"<]+?)"?\s*</.exec(from) || [])[1] || from.replace(/<.*>/, "").trim(),
    text,
    links,
    files: out.files || [],
  };
}


