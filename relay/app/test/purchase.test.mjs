// Run: node --test relay/app/test
import test from "node:test";
import assert from "node:assert/strict";
import { verifyPurchase, verifyBetaApp, PurchaseError, readCert, signedBy, b64decode } from "../purchase.js";
import { APPLE_ROOT_CA_G3_B64 } from "../apple-root-g3.js";
import { makeChain, signPurchase, purchasePayload, appTransactionPayload } from "./pki.mjs";

const chain = makeChain();
const roots = [b64decode(chain.root)];
const ok = (jws, opts = {}) => verifyPurchase(jws, { roots, ...opts });
const fails = (jws, why, opts = {}) => assert.rejects(ok(jws, opts), (e) => e instanceof PurchaseError && (!why || why.test(e.message)));

test("a sandbox purchase passes, and carries its original transaction id", async () => {
  const r = await ok(signPurchase(chain));
  assert.deepEqual(r, { originalTransactionId: "1000000000000001", environment: "Sandbox" });
});

test("a production purchase passes, even with sandbox turned off", async () => {
  const jws = signPurchase(chain, purchasePayload({ environment: "Production" }));
  assert.equal((await ok(jws, { allowSandbox: false })).environment, "Production");
});

test("sandbox is refused once ALLOW_SANDBOX is off", async () => {
  await fails(signPurchase(chain), /environment/, { allowSandbox: false });
});

test("Xcode's local purchases are never accepted", async () => {
  await fails(signPurchase(chain, purchasePayload({ environment: "Xcode" })), /environment/);
});

test("a purchase for another app or another product fails", async () => {
  await fails(signPurchase(chain, purchasePayload({ bundleId: "com.example.other" })), /wrong app/);
  await fails(signPurchase(chain, purchasePayload({ productId: "com.grahamdeno.shoebox.other" })), /wrong product/);
});

test("a refunded purchase fails", async () => {
  await fails(signPurchase(chain, purchasePayload({ revocationDate: Date.now(), revocationReason: 0 })), /refunded/);
});

test("a changed payload or a changed signature fails", async () => {
  await fails(signPurchase(chain, purchasePayload(), { tamper: (p) => ({ ...p, originalTransactionId: "1000000000000002" }) }), /bad signature/);
  const jws = signPurchase(chain);
  const [h, p, s] = jws.split(".");
  const flipped = Buffer.from(s, "base64url");
  flipped[10] ^= 1;
  await fails(`${h}.${p}.${flipped.toString("base64url")}`, /bad signature/);
  await fails(`${h}.${p}.`, /bad signature/);
});

test("a chain that does not end in the trusted root fails (a self-signed chain)", async () => {
  const other = makeChain({ name: "Other" });
  await fails(signPurchase(other), /root/);
  // Their root pasted over ours in the header is still refused: the root is compared with the one trusted here.
  await fails(signPurchase(chain, purchasePayload(), { x5c: [chain.leaf, chain.mid, other.root] }), /root/);
});

test("a leaf signed by a different intermediate fails", async () => {
  const other = makeChain({ name: "Other" });
  await fails(signPurchase(chain, purchasePayload(), { x5c: [other.leaf, chain.mid, chain.root] }), /leaf not signed/);
  await fails(signPurchase(chain, purchasePayload(), { x5c: [chain.leaf, other.mid, chain.root] }), /intermediate not signed/);
});

test("a certificate without Apple's marker fails (any Apple developer can get one under the same intermediate)", async () => {
  const noLeaf = makeChain({ leafMarker: false });
  await assert.rejects(verifyPurchase(signPurchase(noLeaf), { roots: [b64decode(noLeaf.root)] }), /App Store signing/);
  const noMid = makeChain({ midMarker: false });
  await assert.rejects(verifyPurchase(signPurchase(noMid), { roots: [b64decode(noMid.root)] }), /App Store signing/);
});

test("a purchase signed outside the certificates' dates fails", async () => {
  const short = makeChain({ days: 1, name: "Short" });
  const trust = { roots: [b64decode(short.root)] };
  const old = signPurchase(short, purchasePayload({ signedDate: Date.now() - 400 * 86400e3 }));
  await assert.rejects(verifyPurchase(old, trust), /out of date/);
  // Signed today under a chain valid today: fine. Signed in the future: refused.
  assert.equal((await verifyPurchase(signPurchase(short), trust)).originalTransactionId, "1000000000000001");
  await assert.rejects(verifyPurchase(signPurchase(short, purchasePayload({ signedDate: Date.now() + 3600e3 })), trust), /signing date/);
});

test("certificates are judged on the day the purchase was signed, not on the day it is checked", async () => {
  // Apple rotates its leaf certificates; the phone may hold a purchase signed under an older one.
  const short = makeChain({ days: 1, name: "Short" });
  const trust = { roots: [b64decode(short.root)], now: Date.now() + 10 * 86400e3 };   // ten days on: the certificates have expired
  const signedWhileValid = signPurchase(short, purchasePayload({ signedDate: Date.now() }));
  assert.equal((await verifyPurchase(signedWhileValid, trust)).originalTransactionId, "1000000000000001");
  // Signed after they expired: refused.
  const signedAfter = signPurchase(short, purchasePayload({ signedDate: Date.now() + 5 * 86400e3 }));
  await assert.rejects(verifyPurchase(signedAfter, trust), /out of date/);
});

test("a different algorithm, a short chain and plain garbage fail", async () => {
  await fails(signPurchase(chain, purchasePayload(), { header: { alg: "none" } }), /chain/);
  await fails(signPurchase(chain, purchasePayload(), { header: { alg: "HS256" } }), /chain/);
  await fails(signPurchase(chain, purchasePayload(), { x5c: [chain.leaf, chain.mid] }), /chain/);
  for (const junk of ["", "a.b.c", "not a purchase", undefined, null, 42, "x".repeat(30000)]) await fails(junk);
});

test("the Apple root embedded in the Worker is Apple Root CA - G3 (skipped until it is filled in)", { skip: !APPLE_ROOT_CA_G3_B64 && "apple-root-g3.js is not filled in yet" }, async () => {
  const der = b64decode(APPLE_ROOT_CA_G3_B64);
  const cert = readCert(der);
  assert.ok(await signedBy(cert, cert), "self-signed");
  assert.equal(cert.curve, "P-384");
  assert.ok(Buffer.from(cert.subject).includes("Apple Root CA - G3"), "the subject names Apple Root CA - G3");
  assert.ok(Buffer.from(cert.subject).includes("Apple Inc."));
  assert.ok(cert.notAfter > Date.UTC(2038, 0, 1), "valid until 2039");
});

/* ---- TestFlight and App Review: the app transaction opens Plus without a purchase (decided November 5) ---- */

const beta = (jws, opts = {}) => verifyBetaApp(jws, { roots, ...opts });
const betaFails = (jws, why) => assert.rejects(beta(jws), (e) => e instanceof PurchaseError && (!why || why.test(e.message)));

test("a TestFlight app transaction passes, and gives one id per Apple Account", async () => {
  assert.deepEqual(await beta(signPurchase(chain, appTransactionPayload())), { betaId: "704000000000000001" });
});

test("StoreKit's environment key is read too, not only receiptType", async () => {
  const p = appTransactionPayload({ environment: "Sandbox" });
  delete p.receiptType;
  assert.equal((await beta(signPurchase(chain, p))).betaId, "704000000000000001");
});

test("an app transaction without an id falls back to the first download date", async () => {
  const p = appTransactionPayload({ originalPurchaseDate: 1762300000000 });
  delete p.appTransactionId;
  assert.deepEqual(await beta(signPurchase(chain, p)), { betaId: "d1762300000000" });
});

test("an App Store install never gets Plus free, and Xcode never does", async () => {
  await betaFails(signPurchase(chain, appTransactionPayload({ receiptType: "Production" })), /environment/);
  await betaFails(signPurchase(chain, appTransactionPayload({ receiptType: "Xcode" })), /environment/);
  const p = appTransactionPayload();
  delete p.receiptType;
  await betaFails(signPurchase(chain, p), /environment/);
});

test("another app's app transaction fails", async () => {
  await betaFails(signPurchase(chain, appTransactionPayload({ bundleId: "com.example.other" })), /wrong app/);
});

test("a purchase is not an app transaction, and an app transaction is not a purchase", async () => {
  await betaFails(signPurchase(chain), /not an app transaction/);
  await fails(signPurchase(chain, appTransactionPayload()), /wrong product/);
});

test("a beta proof that is tampered with, or signed by anyone but Apple, fails", async () => {
  await betaFails(signPurchase(chain, appTransactionPayload(), { tamper: (p) => ({ ...p, appTransactionId: "704000000000000002" }) }), /bad signature/);
  await betaFails(signPurchase(makeChain({ name: "Other" }), appTransactionPayload()), /root/);
  const noLeaf = makeChain({ leafMarker: false });
  await assert.rejects(verifyBetaApp(signPurchase(noLeaf, appTransactionPayload()), { roots: [b64decode(noLeaf.root)] }), /App Store signing/);
  await betaFails("garbage", /not a signed purchase/);
});
