// Run: node --test relay/app/test
import test from "node:test";
import assert from "node:assert/strict";
import RELAY, { mailBox, boxOf, newSlug, mintAddress } from "../worker.js";

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

function call(env, path, { method = "GET", key, body, origin = ORIGIN, ip = "1.1.1.1" } = {}) {
  const headers = { origin, "cf-connecting-ip": ip };
  if (key) headers["x-inbox-key"] = key;
  if (body) headers["content-type"] = "application/json";
  return RELAY.fetch(new Request("https://api.inmyshoebox.com" + path, { method, headers, body: body ? JSON.stringify(body) : undefined }), env);
}

function mail(to, subject = "Band concert") {
  let rejected = null;
  return {
    to, from: "school@example.com", rawSize: 400,
    raw: `From: School <school@example.com>\r\nSubject: ${subject}\r\nContent-Type: text/plain\r\n\r\nThe band concert is Thursday, Nov 13 at 7 pm in the gym. Please arrive by 6:30 and bring your uniform.\r\n`,
    setReject(reason) { rejected = reason; },
    get rejected() { return rejected; },
  };
}

test("only Shoebox's origin is served", async () => {
  const env = { SHOEBOX: memoryKV() };
  assert.equal((await call(env, "/inbox", { key: KEY_A, origin: "https://example.com" })).status, 403);
  assert.equal((await call(env, "/inbox", { key: KEY_A, origin: "" })).status, 403);
});

test("the old relay's routes are not here", async () => {
  const env = { SHOEBOX: memoryKV() };
  for (const [method, path] of [["POST", "/v1/agent"], ["GET", "/apple/token"], ["POST", "/remind"], ["GET", "/image?url=https://example.com/a.png"],
    ["GET", "/file?url=https://example.com/a"], ["GET", "/ical?url=https://example.com/a"], ["GET", "/version"], ["POST", "/beta"], ["GET", "/photo?q=cats"],
    ["POST", "/ai/messages"], ["GET", "/stats"], ["POST", "/song"]]) {
    assert.equal((await call(env, path, { method })).status, 404, `${method} ${path}`);
  }
});

test("an address has an 8 character suffix and its keys expire", async () => {
  const kv = memoryKV(), env = { SHOEBOX: kv };
  const res = await call(env, "/inbox/address", { method: "POST", key: KEY_A, body: { name: "Sam" } });
  assert.equal(res.status, 200);
  const { address } = await res.json();
  assert.match(address, /^sam-[a-z2-9]{8}@inmyshoebox\.com$/);
  const slug = address.split("@")[0];
  assert.ok(kv.ttl.get(`alias:${slug}`) > 0, "alias has a TTL");
  assert.ok(kv.ttl.get(`box:${await boxOf(KEY_A)}`) > 0, "box has a TTL");
  assert.equal(newSlug("x").split("-")[1].length, 8);
});

test("new addresses are limited per network, then refused", async () => {
  const env = { SHOEBOX: memoryKV() };
  const results = [];
  for (let i = 0; i < 7; i++) {
    const key = `sb-${String(i).repeat(40)}`;
    results.push((await call(env, "/inbox/address", { method: "POST", key, body: { name: "kid" }, ip: "9.9.9.9" })).status);
  }
  assert.deepEqual(results, [200, 200, 200, 200, 200, 429, 429]);
  // Another network is not affected.
  assert.equal((await call(env, "/inbox/address", { method: "POST", key: KEY_B, body: { name: "kid" }, ip: "8.8.8.8" })).status, 200);
});

test("the whole relay stops minting at the daily cap", async () => {
  const env = { SHOEBOX: memoryKV(), MINT_DAILY_CAP: "2" };
  const statuses = [];
  for (let i = 0; i < 4; i++) {
    statuses.push((await call(env, "/inbox/address", { method: "POST", key: `sb-${String(i + 1).repeat(40)}`, body: { name: "a" }, ip: `7.7.7.${i}` })).status);
  }
  assert.deepEqual(statuses, [200, 200, 503, 503]);
});

test("a phone can rename its address only a few times a day", async () => {
  const env = { SHOEBOX: memoryKV() };
  const statuses = [];
  for (let i = 0; i < 6; i++) statuses.push((await call(env, "/inbox/address", { method: "POST", key: KEY_A, body: { name: "sam" }, ip: `6.6.6.${i}` })).status);
  assert.deepEqual(statuses, [200, 200, 200, 200, 429, 429]);   // first mint, then 3 renames, then refused
});

test("mail to an unknown address is dropped without a bounce", async () => {
  const kv = memoryKV(), env = { SHOEBOX: kv };
  const m = mail("nobody-abcd2345@inmyshoebox.com");
  await RELAY.email(m, env);
  assert.equal(m.rejected, null);
  assert.equal([...kv.m.keys()].filter((k) => k.startsWith("m:")).length, 0);
  // A four letter suffix (the old form) is not an address any more.
  const old = mail("sam-ab2c@inmyshoebox.com");
  await RELAY.email(old, env);
  assert.equal(old.rejected, null);
});

test("mail waits 7 days, reaches only its phone, and is gone once acknowledged", async () => {
  const kv = memoryKV(), env = { SHOEBOX: kv };
  const { address } = await (await call(env, "/inbox/address", { method: "POST", key: KEY_A, body: { name: "sam" } })).json();
  const m = mail(address);
  await RELAY.email(m, env);
  assert.equal(m.rejected, null);
  const mailKey = [...kv.m.keys()].find((k) => k.startsWith("m:"));
  assert.equal(kv.ttl.get(mailKey), 7 * 86400);

  const inbox = await (await call(env, "/inbox", { key: KEY_A })).json();
  assert.equal(inbox.mails.length, 1);
  assert.equal(inbox.address, address);
  assert.match(inbox.mails[0].text, /band concert/i);
  // Another phone sees nothing.
  assert.equal((await (await call(env, "/inbox", { key: KEY_B })).json()).mails.length, 0);

  await call(env, "/inbox/ack", { method: "POST", key: KEY_B, body: { ids: [inbox.mails[0].id] } });
  assert.equal((await (await call(env, "/inbox", { key: KEY_A })).json()).mails.length, 1, "another phone cannot acknowledge it");
  await call(env, "/inbox/ack", { method: "POST", key: KEY_A, body: { ids: [inbox.mails[0].id] } });
  assert.equal((await (await call(env, "/inbox", { key: KEY_A })).json()).mails.length, 0);
});

test("one box takes only so many mails a day", async () => {
  const kv = memoryKV(), env = { SHOEBOX: kv, MAILBOX_DAILY_CAP: "3" };
  const { address } = await (await call(env, "/inbox/address", { method: "POST", key: KEY_A, body: { name: "sam" } })).json();
  for (let i = 0; i < 6; i++) await RELAY.email(mail(address, `Note ${i}`), env);
  assert.equal([...kv.m.keys()].filter((k) => k.startsWith("m:")).length, 3);
});

test("the shared address belongs to a pinned owner, never to the first caller", async () => {
  const kv = memoryKV();
  const env = { SHOEBOX: kv, EMAIL_ADDRESS: "graham-keep@inmyshoebox.com" };
  assert.equal(await mailBox(env, "graham-keep@inmyshoebox.com"), null, "no owner secret: nobody");
  // Asking the inbox first does not make a phone the owner.
  await call(env, "/inbox", { key: KEY_B });
  assert.equal(await mailBox(env, "graham-keep@inmyshoebox.com"), null);
  const pinned = { ...env, OWNER_INBOX_KEY: KEY_A };
  assert.equal(await mailBox(pinned, "graham-keep@inmyshoebox.com"), await boxOf(KEY_A));
});

test("Delete everything removes the address, the box and every waiting mail, past the first page", async () => {
  const kv = memoryKV(2), env = { SHOEBOX: kv };
  const { address } = await (await call(env, "/inbox/address", { method: "POST", key: KEY_A, body: { name: "sam" } })).json();
  for (let i = 0; i < 5; i++) await RELAY.email(mail(address, `Note ${i}`), env);
  assert.ok([...kv.m.keys()].filter((k) => k.startsWith("m:")).length >= 5);
  const res = await call(env, "/me/delete", { method: "POST", key: KEY_A });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).mail, 5);
  const left = [...kv.m.keys()].filter((k) => /^(m|a|alias|box):/.test(k));
  assert.deepEqual(left, []);
  assert.equal(await mailBox(env, address), null);
  // Without a key there is nothing to delete.
  assert.equal((await call(env, "/me/delete", { method: "POST" })).status, 401);
});

test("an inbox key must look like one", async () => {
  const env = { SHOEBOX: memoryKV() };
  assert.equal((await call(env, "/inbox", { key: "short" })).status, 401);
  assert.equal((await call(env, "/inbox")).status, 401);
});

test("the stock route answers only Shoebox's origin and asks for 1 to 80 characters", async () => {
  const env = { SHOEBOX: memoryKV() };
  assert.equal((await call(env, "/stock?q=cats", { origin: "http://localhost:3000" })).status, 403);
  assert.equal((await call(env, "/stock?q=")).status, 400);
  assert.equal((await call(env, "/stock?q=" + "a".repeat(81))).status, 400);
  // No Pixabay key set: a plain 502 with no photos, not a crash.
  const res = await call(env, "/stock?q=garden");
  assert.equal(res.status, 502);
  assert.deepEqual(await res.json(), { photos: [] });
});

test("previews refuse private addresses and non-links", async () => {
  const env = { SHOEBOX: memoryKV() };
  assert.equal((await call(env, "/preview?url=http://127.0.0.1/admin")).status, 400);
  assert.equal((await call(env, "/preview?url=http://169.254.169.254/latest")).status, 400);
  assert.equal((await call(env, "/preview?url=not-a-link")).status, 400);
});
