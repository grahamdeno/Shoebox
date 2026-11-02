/*
 * Sealed mail (docs/design/identity-and-sealed-mail.md, R-13).
 *
 * HPKE, RFC 9180, base mode: DHKEM(X25519, HKDF-SHA256), HKDF-SHA256, AES-256-GCM. A published standard from the
 * `@hpke/core` and `@hpke/dhkem-x25519` packages (versions pinned exactly in package.json), on Web Crypto. Nothing
 * here is hand-rolled. The phone opens what this seals with CryptoKit's HPKE (the same suite).
 *
 *   info = "shoebox-mail-v1"
 *   aad  = "<box>:<id>" for a mail, "<box>:<id>:<n>" for its attachment number n
 *
 * One call seals one message to one public key: a fresh ephemeral key each time, so `enc` differs every call.
 */
import { CipherSuite, HkdfSha256, Aes256Gcm } from "@hpke/core";
import { DhkemX25519HkdfSha256 } from "@hpke/dhkem-x25519";

export const SEAL_INFO = "shoebox-mail-v1";
const text = new TextEncoder();

export const suite = new CipherSuite({ kem: new DhkemX25519HkdfSha256(), kdf: new HkdfSha256(), aead: new Aes256Gcm() });

export function toBase64(bytes) {
  let bin = "";
  for (const b of new Uint8Array(bytes)) bin += String.fromCharCode(b);
  return btoa(bin);
}
export function fromBase64(s) { return Uint8Array.from(atob(String(s)), (c) => c.charCodeAt(0)); }

/** A phone's sealing public key: standard base64 of 32 bytes (44 characters). */
export const isPublicKey = (s) => typeof s === "string" && /^[A-Za-z0-9+/]{43}=$/.test(s);

/** An exact-size ArrayBuffer of the bytes (the library takes ArrayBuffers, and a view can sit inside a larger buffer). */
export const exact = (u8) => u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);

/** Seals bytes to a public key (base64). Returns { enc, ct } as base64. `ekm` is for the test vectors only. */
export async function seal(publicKey, bytes, aad, ekm) {
  const recipientPublicKey = await suite.kem.deserializePublicKey(exact(fromBase64(publicKey)));
  const params = { recipientPublicKey, info: exact(text.encode(SEAL_INFO)) };
  if (ekm) params.ekm = ekm;
  const { enc, ct } = await suite.seal(params, exact(bytes), exact(text.encode(aad)));
  return { enc: toBase64(enc), ct: toBase64(ct) };
}

/** Seals one JSON object. */
export function sealJSON(publicKey, value, aad, ekm) {
  return seal(publicKey, text.encode(JSON.stringify(value)), aad, ekm);
}
