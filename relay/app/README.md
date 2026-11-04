# Shoebox app relay

The Cloudflare Worker `shoebox-app-relay` for the Shoebox iPhone app, at `https://api.inmyshoebox.com`. It has nine routes and nothing else. Mail is sealed (HPKE, RFC 9180) to a public key the phone gives it, so the relay cannot read what it stores. Making or re-keying an address needs Shoebox Plus, proven by a StoreKit signed receipt that the relay verifies itself (`purchase.js`).

| Route | What it does |
|---|---|
| `GET /preview?url=&text=1` | A page's title, description, pictures and readable text. Public web links only. 240 a network an hour. |
| `GET /stock?q=&n=` | Pixabay photos for a few generic words. Cached 24 hours. About 60 searches a network an hour. |
| `GET /inbox` | Waiting mail (up to 20, sealed), this phone's address and the sealing key held for it. |
| `POST /inbox/address` | Makes the phone's address from `{name, pub, purchase}`: `name-` plus 8 letters or digits. 402 without Plus, 403 when the purchase is already on five phones. |
| `POST /inbox/seal` | Registers a new sealing key `{pub, purchase}` for an existing address (a new phone). |
| `GET /inbox/file?id=&n=` | One attachment of a waiting mail. |
| `POST /inbox/ack` | Forgets mail the phone has saved. |
| `POST /me/delete` | Forgets the address, the box and all waiting mail for the phone, and frees its purchase seat. Safe to repeat. |
| `POST /request/beta`, `POST /request/android` | A request from the website. Kept 180 days (one per email), and posted, sealed, to the owner's Shoebox (`REQUESTS_TO`, else `PLUS_OWNER_ADDRESS`). Three a network a day. |

Mail sent to an address arrives through Email Routing (`email()` in `worker.js`).

The old Worker (`../perplexity-relay.js`, `shoebox-relay`) keeps `shoebox-api.tangomike.app` for Shoebox 1 and is not changed. Nothing in the app calls it any more.

## What it keeps

| What | How long |
|---|---|
| Mail and attachments | 7 days, or until the phone acknowledges them |
| Address and box | 90 days after the phone last asked (renewed at most once a day) |
| Purchase seats (`buy:`) | Original transaction number only, up to five boxes; freed by `/me/delete` or when a box expires |
| Rate counters | An hour or a day. Addresses appear only as salted hashes. |

Search words, link addresses and mail text are never logged.

## Limits

| Limit | Value | Setting |
|---|---|---|
| New addresses per network per day | 5 | in code |
| Address changes per phone per day | 3 | in code |
| New addresses for everyone per day | 300 | `MINT_DAILY_CAP` |
| Mails one box accepts per day | 40 | `MAILBOX_DAILY_CAP` |
| Mail size | 12 MB | in code |

Mail to an address nobody holds is dropped without a bounce, so the relay never says which addresses exist. Mail to a real address that is over the size or the daily limit is bounced with a short reason, so the person who forwarded it knows. Limits per network count an IPv6 network as its first 64 bits.

## Owner

No phone becomes the owner by asking first. The one shared address (optional) is `EMAIL_ADDRESS`; it delivers to the phone whose inbox key is the `OWNER_INBOX_KEY` secret, and to nobody if the secret is not set.

## Settings

Secrets: `PIXABAY_API_KEY`, `OWNER_INBOX_KEY` (optional).
Sandbox purchases (TestFlight, Xcode) are accepted while `ALLOW_SANDBOX` is not `"0"`. Set it to `"0"` once testing is over. `TEST_PURCHASE_ROOT` is for tests only; never set it in production.
`PLUS_OWNER_ADDRESS` (optional, a plain variable): the owner's own address, such as `graham-k3t7m2qa`. That one address may register its sealing key without a purchase, so its mail works before Shoebox Plus is on sale. It makes no address and takes no seat. Remove it once Plus can be bought.
The Apple root certificate is in `apple-root-g3.js`. While it is empty the relay refuses every purchase (fails closed).
Variables: `EMAIL_DOMAIN` (default `inmyshoebox.com`), `EMAIL_ADDRESS` (optional), `MINT_DAILY_CAP`, `MAILBOX_DAILY_CAP`, `STOCK_HOURLY_LIMIT` (all optional). `PIXABAY_BASE_URL` is for local tests only.
Binding: KV `SHOEBOX`, a namespace made for this Worker.

## Tests

```sh
cd relay/app && npm ci
node --test test/*.test.mjs
```
The tests need the real `@hpke` packages. `test/vectors/sealed-v1.json` is written by the tests and opened by the Swift tests; commit it when it changes.

## Deploy

Not by hand. `docs/handoff/grok-relay-deploy.md` has the first deploy. The sealed-mail version uses npm packages, so it is deployed with `wrangler deploy` (the dashboard paste no longer works); `docs/handoff/grok-identity-build.md` has the steps, with the ones that can't be undone first.
