// Run: node --test relay/app/test
import test from "node:test";
import assert from "node:assert/strict";
import RELAY, { mailBox, boxOf, newSlug, mintAddress } from "../worker.js";
import { suite, fromBase64, SEAL_INFO } from "../seal.js";
import { makeChain, signPurchase, purchasePayload, appTransactionPayload, x25519 } from "./pki.mjs";

/** A KV namespace in memory. Remembers each key's TTL; lists in pages of `page` keys. */
function memoryKV(page = 1000) {
  const m = new Map(), ttl = new Map();
  return {
    m, ttl,
    async get(k, type) { const v = m.get(k); if (v === undefined) return null; return type === "json" ? JSON.parse(v) : v; },
    async put(k, v, o = {}) { m.set(k, String(v)); if (o.expirationTtl) ttl.set(k, o.expirationTtl); else ttl.delete(k); },
    async delete(k) { m.delete(k); ttl.delete(k); },
    async list({ prefix = "", cursor } = {}) {
      const all = [...m.keys()].filter((k) => k.startsWith(prefix)).sort();
      const start = cursor ? Number(cursor) : 0;
      const keys = all.slice(start, start + page).map((name) => ({ name }));
      const done = start + page >= all.length;
      return { keys, list_complete: done, cursor: done ? undefined : String(start + page) };
    },
  };
}

const ORIGIN = "https://inmyshoebox.com";
const KEY_A = "sb-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const KEY_B = "sb-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

// Apple's chain stands in as a test chain; the Worker trusts it only because the test sets TEST_PURCHASE_ROOT.
const chain = makeChain();
const text = new TextEncoder();
// One phone's sealing key pair, from fixed secret bytes.
const phone = x25519(new Uint8Array(32).fill(7));
const PUB = phone.public;
const phoneKey = await suite.kem.deserializePrivateKey(fromBase64(phone.secret).buffer);

const newEnv = (extra = {}) => ({ SHOEBOX: memoryKV(), TEST_PURCHASE_ROOT: chain.root, ...extra });

// A purchase for each phone key, so one purchase never covers more than five boxes by accident.
const ids = new Map();
const otidOf = (key) => { if (!ids.has(key)) ids.set(key, String(1000000000 + ids.size + 1)); return ids.get(key); };
const jwsFor = (otid, over = {}) => signPurchase(chain, purchasePayload({ originalTransactionId: otid, ...over }));

function call(env, path, { method = "GET", key, body, origin = ORIGIN, ip = "1.1.1.1" } = {}) {
  const headers = { origin, "cf-connecting-ip": ip };
  if (key) headers["x-inbox-key"] = key;
  if (body) headers["content-type"] = "application/json";
  return RELAY.fetch(new Request("https://api.inmyshoebox.com" + path, { method, headers, body: body ? JSON.stringify(body) : undefined }), env);
}

/** Asks for an address the way the phone does: its name, its sealing key and a signed purchase. */
function mint(env, key, opts = {}) {
  const otid = opts.otid || otidOf(key);
  // `in` (not a default) so a test can pass pub: undefined to leave it out.
  const body = { name: opts.name || "sam", pub: "pub" in opts ? opts.pub : PUB, purchase: "purchase" in opts ? opts.purchase : jwsFor(otid) };
  return call(env, "/inbox/address", { method: "POST", key, body, ip: opts.ip });
}
async function address(env, key, opts) { return (await (await mint(env, key, opts)).json()).address; }

function mail(to, subject = "Band concert", { attach } = {}) {
  let rejected = null;
  const body = "The band concert is Thursday, Nov 13 at 7 pm in the gym. Please arrive by 6:30 and bring your uniform.";
  const raw = attach
    ? `From: School <school@example.com>\r\nSubject: ${subject}\r\nContent-Type: multipart/mixed; boundary="b1"\r\n\r\n--b1\r\nContent-Type: text/plain\r\n\r\n${body}\r\n--b1\r\nContent-Type: application/pdf; name="flyer.pdf"\r\nContent-Transfer-Encoding: base64\r\nContent-Disposition: attachment; filename="flyer.pdf"\r\n\r\n${Buffer.from(attach).toString("base64")}\r\n--b1--\r\n`
    : `From: School <school@example.com>\r\nSubject: ${subject}\r\nContent-Type: text/plain\r\n\r\n${body}\r\n`;
  return {
    to, from: "school@example.com", rawSize: 400, raw,
    setReject(reason) { rejected = reason; },
    get rejected() { return rejected; },
  };
}

/** What the phone does with a stored record: open it with its private key and the box and mail ids. */
async function open(record, aad, key = phoneKey) {
  return new Uint8Array(await suite.open({ recipientKey: key, enc: fromBase64(record.enc).buffer, info: text.encode(SEAL_INFO) }, fromBase64(record.ct).buffer, text.encode(aad)));
}
const openJSON = async (record, aad) => JSON.parse(new TextDecoder().decode(await open(record, aad)));
const keysWith = (kv, prefix) => [...kv.m.keys()].filter((k) => k.startsWith(prefix));

test("only Shoebox's origin is served", async () => {
  const env = newEnv();
  assert.equal((await call(env, "/inbox", { key: KEY_A, origin: "https://example.com" })).status, 403);
  assert.equal((await call(env, "/inbox", { key: KEY_A, origin: "" })).status, 403);
});

test("the old relay's routes are not here", async () => {
  const env = newEnv();
  for (const [method, path] of [["POST", "/v1/agent"], ["GET", "/apple/token"], ["POST", "/remind"], ["GET", "/image?url=https://example.com/a.png"],
    ["GET", "/file?url=https://example.com/a"], ["GET", "/ical?url=https://example.com/a"], ["GET", "/version"], ["POST", "/beta"], ["GET", "/photo?q=cats"],
    ["POST", "/ai/messages"], ["GET", "/stats"], ["POST", "/song"]]) {
    assert.equal((await call(env, path, { method })).status, 404, `${method} ${path}`);
  }
});

test("an address has an 8 character suffix and its keys expire", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const res = await mint(env, KEY_A, { name: "Sam" });
  assert.equal(res.status, 200);
  const { address } = await res.json();
  assert.match(address, /^sam-[a-z2-9]{8}@inmyshoebox\.com$/);
  const slug = address.split("@")[0];
  assert.ok(kv.ttl.get(`alias:${slug}`) > 0, "alias has a TTL");
  const box = await boxOf(KEY_A);
  assert.ok(kv.ttl.get(`box:${box}`) > 0, "box has a TTL");
  // The box record holds the phone's sealing key and the purchase that opened it. Never the secret itself.
  const rec = await kv.get(`box:${box}`, "json");
  assert.equal(rec.pub, PUB);
  assert.equal(rec.buy, otidOf(KEY_A));
  assert.ok(![...kv.m.values()].some((v) => v.includes(KEY_A)), "the mailbox secret is never stored, only its hash");
  assert.equal(newSlug("x").split("-")[1].length, 8);
});

test("new addresses are limited per network, then refused", async () => {
  const env = newEnv();
  const results = [];
  for (let i = 0; i < 7; i++) {
    const key = `sb-${String(i).repeat(40)}`;
    results.push((await mint(env, key, { name: "kid", ip: "9.9.9.9" })).status);
  }
  assert.deepEqual(results, [200, 200, 200, 200, 200, 429, 429]);
  // Another network is not affected.
  assert.equal((await mint(env, KEY_B, { name: "kid", ip: "8.8.8.8" })).status, 200);
});

test("the whole relay stops minting at the daily cap", async () => {
  const env = newEnv({ MINT_DAILY_CAP: "2" });
  const statuses = [];
  for (let i = 0; i < 4; i++) statuses.push((await mint(env, `sb-${String(i + 1).repeat(40)}`, { name: "a", ip: `7.7.7.${i}` })).status);
  assert.deepEqual(statuses, [200, 200, 503, 503]);
});

test("a phone can rename its address only a few times a day", async () => {
  const env = newEnv();
  const statuses = [];
  for (let i = 0; i < 6; i++) statuses.push((await mint(env, KEY_A, { name: "sam", ip: `6.6.6.${i}` })).status);
  assert.deepEqual(statuses, [200, 200, 200, 200, 429, 429]);   // first mint, then 3 renames, then refused
});

test("mail to an unknown address is dropped without a bounce", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const m = mail("nobody-abcd2345@inmyshoebox.com");
  await RELAY.email(m, env);
  assert.equal(m.rejected, null);
  assert.equal(keysWith(kv, "m:").length, 0);
  // A four letter suffix (the old form) is not an address any more.
  const old = mail("sam-ab2c@inmyshoebox.com");
  await RELAY.email(old, env);
  assert.equal(old.rejected, null);
});

test("mail waits 7 days, reaches only its phone, and is gone once acknowledged", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const addr = await address(env, KEY_A);
  const m = mail(addr);
  await RELAY.email(m, env);
  assert.equal(m.rejected, null);
  const mailKey = keysWith(kv, "m:")[0];
  assert.equal(kv.ttl.get(mailKey), 7 * 86400);

  const inbox = await (await call(env, "/inbox", { key: KEY_A })).json();
  assert.equal(inbox.mails.length, 1);
  assert.equal(inbox.address, addr);
  assert.equal(inbox.pub, PUB, "the phone is told which sealing key the relay holds for it");
  const opened = await openJSON(inbox.mails[0], `${await boxOf(KEY_A)}:${inbox.mails[0].id}`);
  assert.match(opened.text, /band concert/i);
  // Another phone sees nothing.
  assert.equal((await (await call(env, "/inbox", { key: KEY_B })).json()).mails.length, 0);

  await call(env, "/inbox/ack", { method: "POST", key: KEY_B, body: { ids: [inbox.mails[0].id] } });
  assert.equal((await (await call(env, "/inbox", { key: KEY_A })).json()).mails.length, 1, "another phone cannot acknowledge it");
  await call(env, "/inbox/ack", { method: "POST", key: KEY_A, body: { ids: [inbox.mails[0].id] } });
  assert.equal((await (await call(env, "/inbox", { key: KEY_A })).json()).mails.length, 0);
});

test("one box takes only so many mails a day, and says so", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv, MAILBOX_DAILY_CAP: "3" });
  const addr = await address(env, KEY_A);
  const sent = [];
  for (let i = 0; i < 5; i++) { const m = mail(addr, `Note ${i}`); await RELAY.email(m, env); sent.push(m.rejected); }
  assert.equal(keysWith(kv, "m:").length, 3);
  assert.deepEqual(sent.slice(0, 3), [null, null, null]);
  assert.match(sent[3], /enough mail today/);
});

test("mail too large for a real address is bounced with a reason, not lost silently", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const addr = await address(env, KEY_A);
  const big = mail(addr);
  big.rawSize = 13e6;
  await RELAY.email(big, env);
  assert.match(big.rejected, /Too large/);
  assert.equal(keysWith(kv, "m:").length, 0);
});

test("an IPv6 network counts as its first 64 bits", async () => {
  const env = newEnv();
  const statuses = [];
  for (let i = 0; i < 6; i++) statuses.push((await mint(env, `sb-${String(i).repeat(40)}`, { name: "a", ip: `2001:db8:1:2::${i + 1}` })).status);
  assert.deepEqual(statuses, [200, 200, 200, 200, 200, 429]);
});

test("the shared address belongs to a pinned owner, never to the first caller", async () => {
  const kv = memoryKV();
  const env = newEnv({ SHOEBOX: kv, EMAIL_ADDRESS: "graham-keep@inmyshoebox.com" });
  assert.equal(await mailBox(env, "graham-keep@inmyshoebox.com"), null, "no owner secret: nobody");
  // Asking the inbox first does not make a phone the owner.
  await call(env, "/inbox", { key: KEY_B });
  assert.equal(await mailBox(env, "graham-keep@inmyshoebox.com"), null);
  const pinned = { ...env, OWNER_INBOX_KEY: KEY_A };
  assert.equal(await mailBox(pinned, "graham-keep@inmyshoebox.com"), await boxOf(KEY_A));
});

test("Delete everything removes the address, the box and every waiting mail, past the first page", async () => {
  const kv = memoryKV(2), env = newEnv({ SHOEBOX: kv });
  const addr = await address(env, KEY_A);
  for (let i = 0; i < 5; i++) await RELAY.email(mail(addr, `Note ${i}`), env);
  assert.ok(keysWith(kv, "m:").length >= 5);
  const res = await call(env, "/me/delete", { method: "POST", key: KEY_A });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).mail, 5);
  const left = [...kv.m.keys()].filter((k) => /^(m|a|alias|box|buy):/.test(k));
  assert.deepEqual(left, []);
  assert.equal(await mailBox(env, addr), null);
  // Asking again is safe (the phone retries until it hears 200).
  assert.equal((await call(env, "/me/delete", { method: "POST", key: KEY_A })).status, 200);
  // Without a key there is nothing to delete.
  assert.equal((await call(env, "/me/delete", { method: "POST" })).status, 401);
});

test("an inbox key must look like one", async () => {
  const env = newEnv();
  assert.equal((await call(env, "/inbox", { key: "short" })).status, 401);
  assert.equal((await call(env, "/inbox")).status, 401);
});

test("the stock route answers only Shoebox's origin and asks for 1 to 80 characters", async () => {
  const env = newEnv();
  assert.equal((await call(env, "/stock?q=cats", { origin: "http://localhost:3000" })).status, 403);
  assert.equal((await call(env, "/stock?q=")).status, 400);
  assert.equal((await call(env, "/stock?q=" + "a".repeat(81))).status, 400);
  // No Pixabay key set: a plain 502 with no photos, not a crash.
  const res = await call(env, "/stock?q=garden");
  assert.equal(res.status, 502);
  assert.equal(res.headers.get("x-reason"), "no-key");
  assert.deepEqual(await res.json(), { photos: [] });
});

test("a rate counter that KV refuses to write never stops a photo search", async () => {
  const kv = memoryKV();
  kv.put = async () => { throw new Error("KV PUT failed: 429 Too Many Requests"); };
  const env = newEnv({ SHOEBOX: kv, PIXABAY_API_KEY: "k" });
  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({ hits: [{ id: 1, largeImageURL: "https://pixabay.com/get/a.jpg", imageWidth: 800, imageHeight: 1200, tags: "bread" }] }), { status: 200 });
  try {
    for (const q of ["bread", "skillet", "coffee cup"]) {
      const res = await call(env, "/stock?q=" + encodeURIComponent(q));
      assert.equal(res.status, 200, q);
      assert.equal((await res.json()).photos.length, 1, q);
    }
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("a Pixabay refusal says why, without the words or the key", async () => {
  const env = newEnv({ PIXABAY_API_KEY: "secret-key" });
  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response("rate limited", { status: 429 });
  try {
    const res = await call(env, "/stock?q=private%20words");
    assert.equal(res.status, 502);
    assert.equal(res.headers.get("x-reason"), "pixabay-429");
    const text = await res.text();
    assert.ok(!text.includes("secret-key") && !text.includes("private"));
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("previews refuse private addresses and non-links", async () => {
  const env = newEnv();
  assert.equal((await call(env, "/preview?url=http://127.0.0.1/admin")).status, 400);
  assert.equal((await call(env, "/preview?url=http://169.254.169.254/latest")).status, 400);
  assert.equal((await call(env, "/preview?url=not-a-link")).status, 400);
});

/* ---- Sealed mail (R-13) ---- */

test("a stored mail and its attachment hold nothing readable, and the phone opens both", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const addr = await address(env, KEY_A);
  const pdf = Buffer.from("%PDF-1.4 the school flyer, with a very particular line: Picture Day is Friday");
  await RELAY.email(mail(addr, "Band concert", { attach: pdf }), env);

  // What the relay stored: only version, id, arrival time and the sealed bytes.
  const [mailKey] = keysWith(kv, "m:"), [fileKey] = keysWith(kv, "a:");
  const stored = await kv.get(mailKey, "json");
  assert.deepEqual(Object.keys(stored).sort(), ["at", "ct", "enc", "id", "v"]);
  assert.equal(stored.v, 1);
  assert.deepEqual(Object.keys(await kv.get(fileKey, "json")).sort(), ["ct", "enc", "v"]);
  for (const secret of ["band concert", "Band concert", "school@example.com", "School", "uniform", "flyer", "Picture Day", pdf.toString("base64").slice(0, 40)]) {
    for (const [k, v] of kv.m) assert.ok(!v.toLowerCase().includes(secret.toLowerCase()), `${k} holds "${secret}" in the clear`);
  }

  // What the phone gets: the same records, which it opens with its key and the box and mail ids.
  const box = await boxOf(KEY_A), id = stored.id;
  const body = await openJSON(stored, `${box}:${id}`);
  assert.equal(body.from, "school@example.com");
  assert.equal(body.fromName, "School");
  assert.equal(body.subject, "Band concert");
  assert.match(body.text, /band concert/i);
  assert.deepEqual(body.links, []);
  assert.deepEqual(body.attachments, [{ n: 0, name: "flyer.pdf", type: "application/pdf", size: pdf.length }]);
  const file = await (await call(env, `/inbox/file?id=${id}&n=0`, { key: KEY_A })).json();
  assert.deepEqual(Object.keys(file).sort(), ["ct", "enc", "v"]);
  assert.deepEqual(Buffer.from(await open(file, `${box}:${id}:0`)), pdf);
});

test("a record does not open under the wrong box, mail or attachment number, or the wrong key", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const addr = await address(env, KEY_A);
  await RELAY.email(mail(addr, "Band concert", { attach: Buffer.from("%PDF-1.4 x") }), env);
  const stored = await kv.get(keysWith(kv, "m:")[0], "json"), box = await boxOf(KEY_A);
  await assert.rejects(open(stored, `${await boxOf(KEY_B)}:${stored.id}`));
  await assert.rejects(open(stored, `${box}:other`));
  await assert.rejects(open(stored, `${box}:${stored.id}:0`), "a mail is not an attachment");
  const file = await kv.get(keysWith(kv, "a:")[0], "json");
  await assert.rejects(open(file, `${box}:${stored.id}`), "an attachment is not a mail");
  await assert.rejects(open(file, `${box}:${stored.id}:1`));
  const elsewhere = await suite.kem.deserializePrivateKey(fromBase64(x25519(new Uint8Array(32).fill(9)).secret).buffer);
  await assert.rejects(open(stored, `${box}:${stored.id}`, elsewhere), "another phone's key cannot open it");
});

test("each mail is sealed with a fresh key, so two identical mails look nothing alike", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const addr = await address(env, KEY_A);
  await RELAY.email(mail(addr, "Same"), env);
  await RELAY.email(mail(addr, "Same"), env);
  const [a, b] = await Promise.all(keysWith(kv, "m:").map((k) => kv.get(k, "json")));
  assert.notEqual(a.enc, b.enc);
  assert.notEqual(a.ct, b.ct);
});

test("a box with no sealing key cannot receive: the sender is told, and nothing is stored", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  // A box from before sealing: an address and no key.
  const box = await boxOf(KEY_A);
  await kv.put("alias:sam-abcd2345", box, { expirationTtl: 90 * 86400 });
  await kv.put(`box:${box}`, JSON.stringify({ slug: "sam-abcd2345", at: Date.now() }), { expirationTtl: 90 * 86400 });
  const m = mail("sam-abcd2345@inmyshoebox.com");
  await RELAY.email(m, env);
  assert.equal(m.rejected, "Open Shoebox to finish setting up your address.");
  assert.equal(keysWith(kv, "m:").length + keysWith(kv, "a:").length, 0);
  assert.equal((await (await call(env, "/inbox", { key: KEY_A })).json()).pub, null);
});

test("an address cannot be made without the sealing key, and a bad key is refused", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  for (const pub of [undefined, "", "short", "!".repeat(44), PUB.slice(0, -1)]) {
    assert.equal((await mint(env, KEY_A, { pub })).status, 400, `pub ${pub}`);
  }
  assert.equal(keysWith(kv, "box:").length + keysWith(kv, "alias:").length, 0);
});

test("/inbox/seal registers a key for an address that has none, and replaces a different one", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const box = await boxOf(KEY_A);
  await kv.put("alias:sam-abcd2345", box, { expirationTtl: 90 * 86400 });
  await kv.put(`box:${box}`, JSON.stringify({ slug: "sam-abcd2345", at: Date.now() }), { expirationTtl: 90 * 86400 });
  const seal = (extra = {}) => call(env, "/inbox/seal", { method: "POST", key: KEY_A, body: { pub: PUB, purchase: jwsFor(otidOf(KEY_A)), ...extra } });
  assert.equal((await seal()).status, 200);
  assert.equal((await (await call(env, "/inbox", { key: KEY_A })).json()).pub, PUB);
  const m = mail("sam-abcd2345@inmyshoebox.com");
  await RELAY.email(m, env);
  assert.equal(m.rejected, null);
  assert.equal(keysWith(kv, "m:").length, 1);
  // A new phone key (a reinstall without iCloud Keychain) replaces it.
  const second = x25519(new Uint8Array(32).fill(3)).public;
  assert.equal((await seal({ pub: second })).status, 200);
  assert.equal((await (await call(env, "/inbox", { key: KEY_A })).json()).pub, second);
  assert.ok(kv.ttl.get(`box:${box}`) > 0 && kv.ttl.get("alias:sam-abcd2345") > 0, "both keep their TTL");
});

test("/inbox/seal needs an address first, a good key and a purchase", async () => {
  const env = newEnv();
  const seal = (body, key = KEY_A) => call(env, "/inbox/seal", { method: "POST", key, body });
  assert.equal((await seal({ pub: PUB, purchase: jwsFor("1000000000000001") })).status, 404, "no address yet");
  await address(env, KEY_A);
  assert.equal((await seal({ pub: "nope", purchase: jwsFor("1000000000000001") })).status, 400);
  assert.equal((await seal({ pub: PUB })).status, 402);
  assert.equal((await seal({ pub: PUB, purchase: "garbage" })).status, 402);
  assert.equal((await seal({ pub: PUB, purchase: jwsFor("1000000000000001") })).status, 200);
  assert.equal((await call(env, "/inbox/seal", { method: "GET", key: KEY_A })).status, 404);
});

/* ---- The Plus gate (M-1) ---- */

test("an address needs a signed Shoebox Plus purchase", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const attempt = (purchase) => call(env, "/inbox/address", { method: "POST", key: KEY_A, body: { name: "sam", pub: PUB, purchase } });
  assert.equal((await attempt(undefined)).status, 402);
  assert.equal((await attempt("garbage")).status, 402);
  assert.equal((await attempt(jwsFor("1000000000000001", { productId: "com.grahamdeno.shoebox.other" }))).status, 402);
  assert.equal((await attempt(jwsFor("1000000000000001", { bundleId: "com.example.other" }))).status, 402);
  assert.equal((await attempt(jwsFor("1000000000000001", { revocationDate: Date.now() }))).status, 402);
  assert.equal((await attempt(signPurchase(makeChain({ name: "Forged" })))).status, 402, "a chain that is not Apple's");
  const body = await (await attempt("garbage")).json();
  assert.match(body.error.message, /Shoebox Plus/);
  assert.equal(keysWith(kv, "box:").length + keysWith(kv, "alias:").length + keysWith(kv, "buy:").length, 0, "nothing was made");
  assert.equal((await attempt(jwsFor("1000000000000001"))).status, 200);
});

test("with no Apple root filled in and no test root, nothing verifies: the gate fails closed", async () => {
  const env = { SHOEBOX: memoryKV() };
  const res = await call(env, "/inbox/address", { method: "POST", key: KEY_A, body: { name: "sam", pub: PUB, purchase: jwsFor("1000000000000001") } });
  assert.equal(res.status, 402);
});

test("sandbox purchases are accepted until ALLOW_SANDBOX is turned off", async () => {
  const sandbox = jwsFor("1000000000000001", { environment: "Sandbox" }), production = jwsFor("1000000000000002", { environment: "Production" });
  const on = newEnv(), off = newEnv({ ALLOW_SANDBOX: "0" });
  assert.equal((await mint(on, KEY_A, { purchase: sandbox })).status, 200);
  assert.equal((await mint(off, KEY_A, { purchase: sandbox })).status, 402);
  assert.equal((await mint(off, KEY_B, { purchase: production })).status, 200);
});

test("one purchase opens at most five boxes; a sixth is told to write to support", async () => {
  const env = newEnv();
  const otid = "1000000000000099", keys = [0, 1, 2, 3, 4, 5].map((i) => `sb-${String(i + 1).repeat(40)}`);
  const statuses = [];
  for (const [i, key] of keys.entries()) statuses.push((await mint(env, key, { otid, ip: `5.5.5.${i}` })).status);
  assert.deepEqual(statuses, [200, 200, 200, 200, 200, 403]);
  const sixth = await mint(env, keys[5], { otid, ip: "5.5.5.9" });
  assert.equal((await sixth.json()).error.message, "This purchase is already on five phones. Write to support@inmyshoebox.com.");
  // A phone that already holds a seat can ask again (a new name, or a new sealing key).
  assert.equal((await mint(env, keys[0], { otid, ip: "5.5.5.10" })).status, 200);
  assert.equal((await call(env, "/inbox/seal", { method: "POST", key: keys[1], body: { pub: PUB, purchase: jwsFor(otid) }, ip: "5.5.5.11" })).status, 200);
  // Another purchase is not affected.
  assert.equal((await mint(env, keys[5], { otid: "1000000000000100", ip: "5.5.5.12" })).status, 200);
});

test("Delete everything gives the purchase its seat back; so does a box that expired", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const otid = "1000000000000098", keys = [0, 1, 2, 3, 4, 5].map((i) => `sb-${String(i + 1).repeat(40)}`);
  for (const [i, key] of keys.slice(0, 5).entries()) assert.equal((await mint(env, key, { otid, ip: `4.4.4.${i}` })).status, 200);
  assert.equal((await mint(env, keys[5], { otid, ip: "4.4.4.9" })).status, 403);
  await call(env, "/me/delete", { method: "POST", key: keys[0] });
  assert.equal((await mint(env, keys[5], { otid, ip: "4.4.4.10" })).status, 200, "a seat came back");
  assert.equal((await mint(env, keys[0], { otid, ip: "4.4.4.11" })).status, 403, "and is taken again");
  // A box idle for 90 days is gone from KV; its seat is free without anyone asking.
  await kv.delete(`box:${await boxOf(keys[1])}`);
  assert.equal((await mint(env, keys[0], { otid, ip: "4.4.4.12" })).status, 200);
  // The last box leaving removes the purchase record, so nothing is kept for it.
  const alone = newEnv({ SHOEBOX: memoryKV() });
  await mint(alone, KEY_A, { otid: "1000000000000097" });
  assert.equal(keysWith(alone.SHOEBOX, "buy:").length, 1);
  await call(alone, "/me/delete", { method: "POST", key: KEY_A });
  assert.equal(keysWith(alone.SHOEBOX, "buy:").length, 0);
});

/* ---- TestFlight and App Review: Plus without buying (decided November 5) ---- */

const betaFor = (id, over = {}) => signPurchase(chain, appTransactionPayload({ appTransactionId: id, ...over }));
const mintBeta = (env, key, beta, ip = "6.6.6.6", name = "sam") =>
  call(env, "/inbox/address", { method: "POST", key, body: { name, pub: PUB, beta }, ip });

test("a TestFlight install gets an address with no purchase, in the usual name-plus-8 form", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const res = await mintBeta(env, KEY_A, betaFor("704000000000000001"));
  assert.equal(res.status, 200);
  assert.match((await res.json()).address, /^sam-[a-z2-9]{8}@inmyshoebox\.com$/);
  assert.deepEqual(keysWith(kv, "buy:"), ["buy:beta-704000000000000001"]);
  // The same proof registers a new sealing key, as a purchase would.
  assert.equal((await call(env, "/inbox/seal", { method: "POST", key: KEY_A, body: { pub: PUB, beta: betaFor("704000000000000001") }, ip: "6.6.6.7" })).status, 200);
});

test("an App Store install, another app, Xcode or a forged chain never gets a free address", async () => {
  const env = newEnv();
  assert.equal((await mintBeta(env, KEY_A, betaFor("704000000000000002", { receiptType: "Production" }))).status, 402);
  assert.equal((await mintBeta(env, KEY_A, betaFor("704000000000000002", { receiptType: "Xcode" }))).status, 402);
  assert.equal((await mintBeta(env, KEY_A, betaFor("704000000000000002", { bundleId: "com.example.other" }))).status, 402);
  assert.equal((await mintBeta(env, KEY_A, signPurchase(makeChain({ name: "Forged" }), appTransactionPayload()))).status, 402);
  assert.equal((await mintBeta(env, KEY_A, "garbage")).status, 402);
});

test("BETA_PLUS or ALLOW_SANDBOX off stops free addresses; an address already made keeps working", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  assert.equal((await mintBeta(env, KEY_A, betaFor("704000000000000003"))).status, 200);
  for (const off of [{ BETA_PLUS: "0" }, { ALLOW_SANDBOX: "0" }]) {
    const later = { ...env, ...off };
    assert.equal((await mintBeta(later, KEY_B, betaFor("704000000000000004"), "6.6.7.1")).status, 402);
    const inbox = await call(later, "/inbox", { key: KEY_A });
    assert.equal(inbox.status, 200);
    assert.ok((await inbox.json()).address, "the tester's address still delivers");
  }
});

test("one tester's proof opens at most five boxes, and a real purchase wins when both are sent", async () => {
  const env = newEnv();
  const keys = [0, 1, 2, 3, 4, 5].map((i) => `sb-${String(i + 1).repeat(40)}`);
  const statuses = [];
  for (const [i, key] of keys.entries()) statuses.push((await mintBeta(env, key, betaFor("704000000000000005"), `7.7.7.${i}`)).status);
  assert.deepEqual(statuses, [200, 200, 200, 200, 200, 403]);
  const sixth = await mintBeta(env, keys[5], betaFor("704000000000000005"), "7.7.7.9");
  assert.match((await sixth.json()).error.message, /testing on five phones/);
  const both = await call(env, "/inbox/address", { method: "POST", key: keys[5], ip: "7.7.7.10", body: { name: "sam", pub: PUB, purchase: jwsFor("1000000000000200"), beta: betaFor("704000000000000005") } });
  assert.equal(both.status, 200);
  assert.ok(keysWith(env.SHOEBOX, "buy:").includes("buy:1000000000000200"));
});

test("Delete everything gives a tester's seat back", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  await mintBeta(env, KEY_A, betaFor("704000000000000006"));
  assert.equal(keysWith(kv, "buy:beta-").length, 1);
  await call(env, "/me/delete", { method: "POST", key: KEY_A });
  assert.equal(keysWith(kv, "buy:beta-").length, 0);
});

test("collecting mail, files, ack and delete are never gated: a refund stops only new addresses", async () => {
  const kv = memoryKV(), live = newEnv({ SHOEBOX: kv });
  const addr = await address(live, KEY_A);
  await RELAY.email(mail(addr, "Band concert", { attach: Buffer.from("%PDF-1.4 x") }), live);
  // From here on no purchase verifies (sandbox off, and the only purchase is a sandbox one).
  const off = { ...live, ALLOW_SANDBOX: "0" };
  assert.equal((await mint(off, KEY_B)).status, 402);
  assert.equal((await call(off, "/inbox/seal", { method: "POST", key: KEY_A, body: { pub: PUB, purchase: jwsFor(otidOf(KEY_A)) } })).status, 402);
  const inbox = await call(off, "/inbox", { key: KEY_A });
  assert.equal(inbox.status, 200);
  const { mails, address: still } = await inbox.json();
  assert.equal(mails.length, 1);
  assert.equal(still, addr, "the address keeps working");
  assert.equal((await call(off, `/inbox/file?id=${mails[0].id}&n=0`, { key: KEY_A })).status, 200);
  assert.equal((await call(off, "/inbox/ack", { method: "POST", key: KEY_A, body: { ids: [mails[0].id] } })).status, 200);
  const more = mail(addr, "Another");
  await RELAY.email(more, off);
  assert.equal(more.rejected, null, "mail still arrives");
  assert.equal((await call(off, "/me/delete", { method: "POST", key: KEY_A })).status, 200);
});

test("purchase checks are limited per network, because each one costs CPU", async () => {
  const env = newEnv();
  const statuses = [];
  for (let i = 0; i < 32; i++) statuses.push((await call(env, "/inbox/address", { method: "POST", key: KEY_A, body: { name: "sam", pub: PUB, purchase: "garbage" }, ip: "3.3.3.3" })).status);
  assert.equal(statuses.filter((s) => s === 402).length, 30);
  assert.deepEqual(statuses.slice(30), [429, 429]);
});

test("plain mail from before sealing is still handed over as it was stored", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const box = await boxOf(KEY_A);
  await kv.put(`m:${box}:old1`, JSON.stringify({ id: "old1", at: 1, from: "a@example.com", subject: "Old", text: "plain", links: [], attachments: [{ n: 0, name: "x.pdf", type: "application/pdf", size: 3 }] }));
  await kv.put(`a:${box}:old1:0`, "QUJD");
  const { mails } = await (await call(env, "/inbox", { key: KEY_A })).json();
  assert.equal(mails.length, 1);
  assert.equal(mails[0].text, "plain");
  assert.equal(mails[0].v, undefined, "no version: the phone reads it as plain");
  assert.deepEqual(await (await call(env, "/inbox/file?id=old1&n=0", { key: KEY_A })).json(), { data: "QUJD" });
});

test("the owner's address registers its key without a purchase; nobody else does", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv, PLUS_OWNER_ADDRESS: "Graham-K3T7M2QA@inmyshoebox.com" });
  const box = await boxOf(KEY_A), other = await boxOf(KEY_B);
  for (const [b, slug] of [[box, "graham-k3t7m2qa"], [other, "sam-abcd2345"]]) {
    await kv.put(`alias:${slug}`, b, { expirationTtl: 90 * 86400 });
    await kv.put(`box:${b}`, JSON.stringify({ slug, at: Date.now() }), { expirationTtl: 90 * 86400 });
  }
  const seal = (key) => call(env, "/inbox/seal", { method: "POST", key, body: { pub: PUB } });
  assert.equal((await seal(KEY_A)).status, 200, "the owner's box, no purchase");
  assert.equal((await (await call(env, "/inbox", { key: KEY_A })).json()).pub, PUB);
  assert.equal(keysWith(kv, "buy:").length, 0, "no seat taken");
  const m = mail("graham-k3t7m2qa@inmyshoebox.com");
  await RELAY.email(m, env);
  assert.equal(m.rejected, null, "the owner's mail is taken, sealed");
  assert.equal((await seal(KEY_B)).status, 402, "another box still needs Plus");
  // Without the variable, the owner needs Plus like everyone.
  const plain = newEnv({ SHOEBOX: kv });
  assert.equal((await call(plain, "/inbox/seal", { method: "POST", key: KEY_A, body: { pub: PUB } })).status, 402);
  // It never makes an address.
  const fresh = newEnv({ PLUS_OWNER_ADDRESS: "graham-k3t7m2qa" });
  assert.equal((await call(fresh, "/inbox/address", { method: "POST", key: KEY_A, body: { name: "graham", pub: PUB } })).status, 402);
});

test("website requests: kept once per email, posted sealed to the owner's Shoebox, bots and floods turned away", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv, PLUS_OWNER_ADDRESS: "graham-k3t7m2qa" });
  const box = await boxOf(KEY_A);
  await kv.put("alias:graham-k3t7m2qa", box, { expirationTtl: 90 * 86400 });
  await kv.put(`box:${box}`, JSON.stringify({ slug: "graham-k3t7m2qa", at: Date.now() }), { expirationTtl: 90 * 86400 });
  assert.equal((await call(env, "/inbox/seal", { method: "POST", key: KEY_A, body: { pub: PUB } })).status, 200);
  const ask = (kind, body, ip = "7.7.7.7") => call(env, `/request/${kind}`, { method: "POST", body, ip });

  assert.equal((await ask("android", { email: "nope" })).status, 400);
  assert.equal((await ask("android", { email: "bot@example.com", website: "x" })).status, 200, "the bot is told yes");
  assert.equal(keysWith(kv, "req:").length, 0, "and nothing is kept");

  const res = await ask("android", { email: "Sis@Example.com", name: "Sis", phone: "Pixel 9" });
  assert.equal(res.status, 200);
  const kept = await kv.get(keysWith(kv, "req:android:")[0], "json");
  assert.equal(kept.email, "sis@example.com");
  assert.deepEqual(kept.answers, { phone: "Pixel 9" });
  assert.ok(kv.ttl.get(keysWith(kv, "req:android:")[0]) > 0, "it expires");

  const posted = keysWith(kv, `m:${box}:`);
  assert.equal(posted.length, 1, "one post in the owner's Shoebox");
  const stored = await kv.get(posted[0], "json");
  assert.equal(stored.v, 1);
  const opened = await openJSON(stored, `${box}:${stored.id}`);
  assert.equal(opened.subject, "Android request from Sis");
  assert.match(opened.text, /phone: Pixel 9/);

  // Asking again refreshes the kept answers and posts nothing new.
  assert.equal((await ask("android", { email: "sis@example.com", name: "Sis", phone: "Pixel 10" }, "7.7.7.8")).status, 200);
  assert.equal(keysWith(kv, "req:android:").length, 1);
  assert.equal(keysWith(kv, `m:${box}:`).length, 1);
  assert.deepEqual((await kv.get(keysWith(kv, "req:android:")[0], "json")).answers, { phone: "Pixel 10" });

  // The beta form's answers come through as they are.
  assert.equal((await ask("beta", { email: "a@b.co", name: "A", iphone: "yes", places: ["Notes", "Safari"], story: "lost a form" }, "7.7.7.9")).status, 200);
  assert.deepEqual((await kv.get(keysWith(kv, "req:beta:")[0], "json")).answers, { iphone: "yes", places: ["Notes", "Safari"], story: "lost a form" });

  // A few a network a day.
  const statuses = [];
  for (let i = 0; i < 5; i++) statuses.push((await ask("android", { email: `p${i}@example.com` }, "9.9.9.9")).status);
  assert.deepEqual(statuses, [200, 200, 200, 429, 429]);
  // Only the two kinds, and only from the website.
  assert.equal((await ask("ios", { email: "a@b.co" })).status, 404);
  assert.equal((await call(env, "/request/android", { method: "POST", body: { email: "a@b.co" }, origin: "https://evil.example" })).status, 403);
});

test("a request with no owner key is still kept", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  assert.equal((await call(env, "/request/android", { method: "POST", body: { email: "x@example.com" } })).status, 200);
  assert.equal(keysWith(kv, "req:android:").length, 1);
  assert.equal(keysWith(kv, "m:").length, 0);
});

test("a purchase's seat record expires 90 days after its phones last asked, and asking renews it", async () => {
  const kv = memoryKV(), env = newEnv({ SHOEBOX: kv });
  const box = await boxOf(KEY_A), otid = "1000000000000300";
  await kv.put("alias:sam-abcd2345", box, { expirationTtl: 90 * 86400 });
  await kv.put(`box:${box}`, JSON.stringify({ slug: "sam-abcd2345", at: Date.now() }), { expirationTtl: 90 * 86400 });
  assert.equal((await call(env, "/inbox/seal", { method: "POST", key: KEY_A, body: { pub: PUB, purchase: jwsFor(otid) } })).status, 200);
  assert.equal(kv.ttl.get(`buy:${otid}`), 90 * 86400, "the seat record is not kept forever");
  // A day later the phone asks for mail: the box and its seat record both renew.
  const cur = JSON.parse(kv.m.get(`box:${box}`));
  await kv.put(`box:${box}`, JSON.stringify({ ...cur, at: Date.now() - 2 * 86400 * 1000 }), { expirationTtl: 5 });
  kv.ttl.set(`buy:${otid}`, 5);
  assert.equal((await call(env, "/inbox", { key: KEY_A })).status, 200);
  assert.equal(kv.ttl.get(`box:${box}`), 90 * 86400);
  assert.equal(kv.ttl.get(`buy:${otid}`), 90 * 86400, "asking renews the seat record");
});
