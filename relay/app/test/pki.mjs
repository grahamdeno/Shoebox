// Test helpers: a small certificate chain shaped like Apple's (root, intermediate, leaf, with Apple's marker
// extensions) made with the openssl command line, and a StoreKit-style signed purchase (JWS) from it.
// Nothing here is a secret or is shipped: the keys live in a temporary folder for the length of the test run.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { sign, createPrivateKey, createPublicKey } from "node:crypto";

const LEAF_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";

const openssl = (dir, ...args) => execFileSync("openssl", args, { cwd: dir, stdio: ["ignore", "pipe", "pipe"] });
const pemBody = (pem) => pem.split("\n").filter((l) => l && !l.startsWith("-----")).join("");

/** A chain: { root, mid, leaf } as base64 DER, and the leaf's private key (PEM). `days` is how long the certificates last. */
export function makeChain({ leafMarker = true, midMarker = true, days = 3650, name = "Test" } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "shoebox-pki-"));
  const write = (file, text) => writeFileSync(join(dir, file), text);
  // Apple's shape: a P-384 root and intermediate, a P-256 leaf, signed with SHA-384.
  openssl(dir, "ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "root.key");
  openssl(dir, "req", "-x509", "-new", "-key", "root.key", "-sha384", "-days", String(days), "-subj", `/CN=${name} Root CA - G3/O=Shoebox Test`, "-addext", "basicConstraints=critical,CA:TRUE", "-out", "root.pem");
  openssl(dir, "ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "mid.key");
  openssl(dir, "req", "-new", "-key", "mid.key", "-subj", `/CN=${name} Intermediate/O=Shoebox Test`, "-out", "mid.csr");
  write("mid.cnf", `basicConstraints=critical,CA:TRUE\n${midMarker ? `${INTERMEDIATE_OID}=ASN1:NULL\n` : ""}`);
  openssl(dir, "x509", "-req", "-in", "mid.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial", "-sha384", "-days", String(days), "-extfile", "mid.cnf", "-out", "mid.pem");
  openssl(dir, "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "leaf.key");
  openssl(dir, "req", "-new", "-key", "leaf.key", "-subj", `/CN=${name} Leaf/O=Shoebox Test`, "-out", "leaf.csr");
  write("leaf.cnf", `basicConstraints=CA:FALSE\n${leafMarker ? `${LEAF_OID}=ASN1:NULL\n` : ""}`);
  openssl(dir, "x509", "-req", "-in", "leaf.csr", "-CA", "mid.pem", "-CAkey", "mid.key", "-CAcreateserial", "-sha384", "-days", String(days), "-extfile", "leaf.cnf", "-out", "leaf.pem");
  const read = (f) => readFileSync(join(dir, f), "utf8");
  return { root: pemBody(read("root.pem")), mid: pemBody(read("mid.pem")), leaf: pemBody(read("leaf.pem")), leafKey: read("leaf.key") };
}

const b64u = (bytes) => Buffer.from(bytes).toString("base64url");

/** What StoreKit's transaction JWS carries, for a purchase that is good unless `over` changes it. */
export function purchasePayload(over = {}) {
  return {
    transactionId: "2000000000000001",
    originalTransactionId: "1000000000000001",
    bundleId: "com.grahamdeno.shoebox",
    productId: "com.grahamdeno.shoebox.plus",
    type: "Non-Consumable",
    environment: "Sandbox",
    signedDate: Date.now(),
    ...over,
  };
}

/** A signed purchase. `header` and `x5c` replace parts of the header; `tamper` changes the payload after signing. */
export function signPurchase(chain, payload = purchasePayload(), { header = {}, x5c, tamper } = {}) {
  const h = { alg: "ES256", x5c: x5c || [chain.leaf, chain.mid, chain.root], ...header };
  const head = b64u(JSON.stringify(h)), body = b64u(JSON.stringify(payload));
  const sig = sign("sha256", Buffer.from(`${head}.${body}`), { key: chain.leafKey, dsaEncoding: "ieee-p1363" });
  return `${head}.${tamper ? b64u(JSON.stringify(tamper(payload))) : body}.${b64u(sig)}`;
}

/** An X25519 key pair from 32 secret bytes, as standard base64 (the form the phone sends and CryptoKit stores). */
export function x25519(secret32) {
  const pkcs8 = Buffer.concat([Buffer.from("302e020100300506032b656e04220420", "hex"), Buffer.from(secret32)]);
  const priv = createPrivateKey({ key: pkcs8, format: "der", type: "pkcs8" });
  const x = createPublicKey(priv).export({ format: "jwk" }).x;
  return { secret: Buffer.from(secret32).toString("base64"), public: Buffer.from(x, "base64url").toString("base64") };
}
