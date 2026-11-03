/*
 * Shoebox Plus: checking the signed purchase the phone sends (docs/design/identity-and-sealed-mail.md, M-1).
 *
 * StoreKit 2 gives the phone a JWS for each transaction (`Transaction.jwsRepresentation`). Apple signs it with a
 * certificate chain carried in the header (x5c: leaf, intermediate, Apple Root CA G3). This file checks, in order:
 *
 *   1. the chain: three certificates, the last one is Apple's root as embedded here, the intermediate is signed by it
 *      and the leaf by the intermediate, each valid on the day Apple signed the purchase
 *   2. that the certificates are App Store signing certificates (Apple's two marker extensions), because any Apple
 *      developer can get a certificate under the same intermediate and must not be able to sign a purchase
 *   3. the ES256 signature of the JWS, with the leaf's key
 *   4. the contents: bundle id, product id, not revoked, Production (or Sandbox while allowSandbox is on)
 *
 * The certificate reader is the one the old relay uses for App Attest (relay/perplexity-relay.js, readCert and
 * signedBy), copied here so this Worker stays self-contained. It does no network calls.
 */

export const BUNDLE_ID = "com.grahamdeno.shoebox";
export const PRODUCT_ID = "com.grahamdeno.shoebox.plus";

// Apple's markers: the leaf is an App Store receipt signing certificate, the intermediate is Apple's WWDR CA.
const LEAF_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";
const FIVE_MINUTES = 5 * 60 * 1000;

export class PurchaseError extends Error {}

const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

export function b64decode(text) {
  const clean = String(text).replace(/-/g, "+").replace(/_/g, "/").replace(/\s+/g, "");
  const bin = atob(clean + "=".repeat((4 - (clean.length % 4)) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

/* ---- A small DER reader (from relay/perplexity-relay.js) ---- */

/** One element at p, as { tag, at (its first byte), start (of contents), end, len }. */
function der(u, p) {
  const tag = u[p];
  let len = u[p + 1], start = p + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (!n || n > 4) throw new Error("der: length");
    len = 0;
    for (let k = 0; k < n; k++) len = len * 256 + u[start + k];
    start += n;
  }
  if (start + len > u.length) throw new Error("der: short");
  return { tag, at: p, start, end: start + len, len };
}
function derKids(u, el) {
  const out = [];
  for (let p = el.start; p < el.end;) { const k = der(u, p); out.push(k); p = k.end; }
  return out;
}
function oidText(u, el) {
  const b = u.slice(el.start, el.end), parts = [Math.floor(b[0] / 40), b[0] % 40];
  let v = 0;
  for (let k = 1; k < b.length; k++) { v = v * 128 + (b[k] & 0x7f); if (!(b[k] & 0x80)) { parts.push(v); v = 0; } }
  return parts.join(".");
}
function derTime(u, el) {
  const s = new TextDecoder().decode(u.slice(el.start, el.end));
  const m = /^(\d{2}|\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(s);
  if (!m) throw new Error("der: time");
  const y = m[1].length === 2 ? (Number(m[1]) < 50 ? 2000 : 1900) + Number(m[1]) : Number(m[1]);
  return Date.UTC(y, m[2] - 1, m[3], m[4], m[5], m[6]);
}

/** The parts of an X.509 certificate the check needs. */
export function readCert(u) {
  const top = der(u, 0), [tbs, alg, sig] = derKids(u, top);
  const t = derKids(u, tbs);
  const off = t[0].tag === 0xa0 ? 1 : 0; // the version, when present
  const validity = derKids(u, t[off + 3]), spki = t[off + 5];
  const [spkiAlg, spkiKey] = derKids(u, spki);
  const curve = oidText(u, derKids(u, spkiAlg)[1]);
  const exts = {};
  const extWrap = t.slice(off + 6).find((e) => e.tag === 0xa3);
  if (extWrap) {
    for (const e of derKids(u, derKids(u, extWrap)[0])) {
      const k = derKids(u, e);
      exts[oidText(u, k[0])] = u.slice(k[k.length - 1].start, k[k.length - 1].end);
    }
  }
  return {
    tbs: u.slice(tbs.at, tbs.end),
    subject: u.slice(t[off + 4].at, t[off + 4].end),
    issuer: u.slice(t[off + 2].at, t[off + 2].end),
    sigAlg: oidText(u, derKids(u, alg)[0]),
    sig: u.slice(sig.start + 1, sig.end), // BIT STRING: skip the unused-bits byte
    spki: u.slice(spki.at, spki.end),
    point: u.slice(spkiKey.start + 1, spkiKey.end),
    curve: { "1.2.840.10045.3.1.7": "P-256", "1.3.132.0.34": "P-384" }[curve] || null,
    notBefore: derTime(u, validity[0]),
    notAfter: derTime(u, validity[1]),
    exts,
  };
}

/** An ECDSA signature in DER (SEQUENCE of two INTEGERs) as the fixed-size r|s WebCrypto checks. */
function rawSig(sig, size) {
  const [r, s] = derKids(sig, der(sig, 0)).map((k) => {
    let v = sig.slice(k.start, k.end);
    while (v.length > size && v[0] === 0) v = v.slice(1);
    const out = new Uint8Array(size);
    out.set(v, size - v.length);
    return out;
  });
  const out = new Uint8Array(size * 2);
  out.set(r, 0); out.set(s, size);
  return out;
}

/** Is cert signed by the issuer's key? */
export async function signedBy(cert, issuer) {
  const hash = { "1.2.840.10045.4.3.2": "SHA-256", "1.2.840.10045.4.3.3": "SHA-384" }[cert.sigAlg];
  if (!hash || !issuer.curve) return false;
  const key = await crypto.subtle.importKey("spki", issuer.spki, { name: "ECDSA", namedCurve: issuer.curve }, false, ["verify"]);
  return crypto.subtle.verify({ name: "ECDSA", hash }, key, rawSig(cert.sig, issuer.curve === "P-384" ? 48 : 32), cert.tbs);
}

/* ---- The purchase ---- */

function parseJSON(bytes) {
  try { return JSON.parse(new TextDecoder().decode(bytes)); } catch { throw new PurchaseError("not a signed purchase"); }
}

/**
 * Checks a StoreKit 2 transaction JWS. Returns { originalTransactionId, environment } or throws PurchaseError.
 * `roots` are the DER bytes of the certificates to trust as the root (Apple Root CA G3 in production).
 * The messages say what failed for the tests and the logs; the relay never passes them on to the phone.
 */
export async function verifyPurchase(jws, { roots = [], now = Date.now(), allowSandbox = true } = {}) {
  try {
    return await check(String(jws || ""), roots, now, allowSandbox);
  } catch (e) {
    if (e instanceof PurchaseError) throw e;
    throw new PurchaseError("could not read the purchase");
  }
}

async function check(jws, roots, now, allowSandbox) {
  const parts = jws.split(".");
  if (parts.length !== 3 || jws.length > 20000) throw new PurchaseError("not a signed purchase");
  const header = parseJSON(b64decode(parts[0])), payload = parseJSON(b64decode(parts[1]));
  if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length !== 3) throw new PurchaseError("not an Apple chain");

  // 1. The chain.
  const ders = header.x5c.map((c) => b64decode(c));
  const trusted = roots.find((r) => same(r, ders[2]));
  if (!trusted) throw new PurchaseError("not signed by Apple's root");
  const [leaf, mid] = ders.slice(0, 2).map(readCert), root = readCert(trusted);
  if (!(await signedBy(mid, root))) throw new PurchaseError("intermediate not signed by the root");
  if (!(await signedBy(leaf, mid))) throw new PurchaseError("leaf not signed by the intermediate");
  // Valid on the day Apple signed the purchase (the phone may hold a purchase signed long ago, under an older leaf).
  const signedAt = Number(payload.signedDate);
  if (!Number.isFinite(signedAt) || signedAt > now + FIVE_MINUTES) throw new PurchaseError("bad signing date");
  for (const c of [leaf, mid, root]) if (signedAt < c.notBefore || signedAt > c.notAfter) throw new PurchaseError("certificate out of date");

  // 2. App Store signing certificates, not any certificate Apple issued.
  if (!(LEAF_OID in leaf.exts) || !(INTERMEDIATE_OID in mid.exts)) throw new PurchaseError("not an App Store signing certificate");

  // 3. The signature over "header.payload", ES256: r|s, 64 bytes.
  if (leaf.curve !== "P-256") throw new PurchaseError("unexpected key");
  const key = await crypto.subtle.importKey("spki", leaf.spki, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  const sig = b64decode(parts[2]);
  const data = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  if (sig.length !== 64 || !(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, sig, data))) throw new PurchaseError("bad signature");

  // 4. What was bought.
  if (payload.bundleId !== BUNDLE_ID) throw new PurchaseError("wrong app");
  if (payload.productId !== PRODUCT_ID) throw new PurchaseError("wrong product");
  if (payload.revocationDate) throw new PurchaseError("refunded");
  const environment = payload.environment;
  if (environment !== "Production" && !(environment === "Sandbox" && allowSandbox)) throw new PurchaseError("wrong environment");
  const originalTransactionId = String(payload.originalTransactionId || "");
  if (!/^\d{1,20}$/.test(originalTransactionId)) throw new PurchaseError("no transaction");
  return { originalTransactionId, environment };
}
