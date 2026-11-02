// Run: node --test relay/app/test
// These tests need the real HPKE packages (npm install in relay/app). They write and read test/vectors/:
//   sealed-v1.json    written by the first test, opened by the Swift test (App/ShoeboxTests/SealedMailTests.swift) with CryptoKit.
//                     Commit it when it changes; CI fails if the committed copy is not what this test writes.
//   rfc9180-a1.json   RFC 9180 appendix A.1 (base mode, X25519 + HKDF-SHA256, AES-128-GCM), copied out of the
//                     published test vectors. Tests are skipped until it is there. See docs/handoff/grok-identity-build.md.
import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { CipherSuite, HkdfSha256, Aes128Gcm } from "@hpke/core";
import { DhkemX25519HkdfSha256 } from "@hpke/dhkem-x25519";
import { suite, seal, sealJSON, fromBase64, toBase64, isPublicKey, SEAL_INFO } from "../seal.js";
import { x25519 } from "./pki.mjs";

const VECTORS = join(dirname(fileURLToPath(import.meta.url)), "vectors");
const text = new TextEncoder(), utf8 = new TextDecoder();
const SUITE = "DHKEM(X25519, HKDF-SHA256), HKDF-SHA256, AES-256-GCM, base mode (RFC 9180)";

const secret = Uint8Array.from({ length: 32 }, (_, i) => i + 1);
const ekm = Uint8Array.from({ length: 32 }, (_, i) => 0xe0 + i);
const pair = x25519(secret);
const aad = "0123456789abcdef0123:mail1-abc";
const message = {
  from: "school@example.com", fromName: "School", subject: "Band concert",
  text: "The band concert is Thursday at 7 pm in the gym. Please arrive by 6:30.",
  links: ["https://example.com/band"],
  attachments: [{ n: 0, name: "flyer.pdf", type: "application/pdf", size: 1234 }],
};
const plaintext = JSON.stringify(message);

async function openWith(recipientSecret, enc, ct, aadText, aead) {
  const s = aead ? new CipherSuite({ kem: new DhkemX25519HkdfSha256(), kdf: new HkdfSha256(), aead }) : suite;
  const recipientKey = await s.kem.deserializePrivateKey(recipientSecret.buffer ? recipientSecret.buffer.slice(recipientSecret.byteOffset, recipientSecret.byteOffset + recipientSecret.byteLength) : recipientSecret);
  return new Uint8Array(await s.open({ recipientKey, enc, info: text.encode(SEAL_INFO) }, ct, text.encode(aadText)));
}

test("a message sealed with fixed keys opens here, is the same every time, and is written for the Swift test", async () => {
  const { enc, ct } = await seal(pair.public, text.encode(plaintext), aad, ekm.buffer.slice(0));
  const opened = await openWith(secret, fromBase64(enc).buffer, fromBase64(ct).buffer, aad);
  assert.equal(utf8.decode(opened), plaintext);
  // Fixed key pair and fixed ephemeral seed: byte for byte the same on every run.
  assert.deepEqual(await seal(pair.public, text.encode(plaintext), aad, ekm.buffer.slice(0)), { enc, ct });
  assert.equal(fromBase64(enc).length, 32, "enc is a raw X25519 public key");
  mkdirSync(VECTORS, { recursive: true });
  writeFileSync(join(VECTORS, "sealed-v1.json"), JSON.stringify({
    suite: SUITE, info: SEAL_INFO, aad, plaintext,
    recipientSecret: pair.secret, recipientPublic: pair.public, ephemeralSeed: toBase64(ekm), enc, ct,
  }, null, 2) + "\n");
});

test("sealing without a fixed seed uses a fresh ephemeral key each time", async () => {
  const a = await sealJSON(pair.public, message, aad), b = await sealJSON(pair.public, message, aad);
  assert.notEqual(a.enc, b.enc);
  assert.notEqual(a.ct, b.ct);
  assert.equal(utf8.decode(await openWith(secret, fromBase64(b.enc).buffer, fromBase64(b.ct).buffer, aad)), plaintext);
});

test("a wrong aad, a changed byte or another key does not open", async () => {
  const { enc, ct } = await seal(pair.public, text.encode(plaintext), aad);
  await assert.rejects(openWith(secret, fromBase64(enc).buffer, fromBase64(ct).buffer, aad + "x"));
  const flipped = fromBase64(ct);
  flipped[0] ^= 1;
  await assert.rejects(openWith(secret, fromBase64(enc).buffer, flipped.buffer, aad));
  await assert.rejects(openWith(Uint8Array.from({ length: 32 }, () => 9), fromBase64(enc).buffer, fromBase64(ct).buffer, aad));
});

test("a sealing key is 32 bytes of standard base64", () => {
  assert.ok(isPublicKey(pair.public));
  for (const bad of ["", "abc", pair.public.slice(0, -1), pair.public + "A", pair.public.replace("=", "A"), null, undefined, 5]) assert.ok(!isPublicKey(bad), String(bad));
});

const rfc = join(VECTORS, "rfc9180-a1.json");
test("RFC 9180 appendix A.1: the published vector for DHKEM(X25519, HKDF-SHA256) and HKDF-SHA256, base mode", { skip: !existsSync(rfc) && "test/vectors/rfc9180-a1.json is not there yet" }, async () => {
  const v = JSON.parse(readFileSync(rfc, "utf8"));
  assert.equal(Number(v.mode), 0);
  assert.equal(Number(v.kem_id), 0x20);
  assert.equal(Number(v.kdf_id), 1);
  assert.equal(Number(v.aead_id), 1);
  const hex = (h) => Uint8Array.from(Buffer.from(h, "hex")).buffer;
  const toHex = (b) => Buffer.from(b).toString("hex");
  // The suite of the RFC's A.1 is AES-128-GCM; the key schedule and the KEM are the same code as ours.
  const s = new CipherSuite({ kem: new DhkemX25519HkdfSha256(), kdf: new HkdfSha256(), aead: new Aes128Gcm() });
  const recipientPublicKey = await s.kem.deserializePublicKey(hex(v.pkRm));
  const first = v.encryptions[0];
  const sealed = await s.seal({ recipientPublicKey, info: hex(v.info), ekm: hex(v.ikmE) }, hex(first.pt), hex(first.aad));
  assert.equal(toHex(sealed.enc), v.enc, "enc");
  assert.equal(toHex(sealed.ct), first.ct, "ciphertext");
  const recipientKey = await s.kem.deserializePrivateKey(hex(v.skRm));
  const pt = await s.open({ recipientKey, enc: hex(v.enc), info: hex(v.info) }, hex(first.ct), hex(first.aad));
  assert.equal(toHex(pt), first.pt, "plaintext");
});
