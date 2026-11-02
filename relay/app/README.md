# Shoebox app relay

The Cloudflare Worker `shoebox-app-relay` for the Shoebox iPhone app, at `https://api.inmyshoebox.com`. It has seven routes and nothing else:

| Route | What it does |
|---|---|
| `GET /preview?url=&text=1` | A page's title, description, pictures and readable text. Public web links only. 240 a network an hour. |
| `GET /stock?q=&n=` | Pixabay photos for a few generic words. Cached 24 hours. About 60 searches a network an hour. |
| `GET /inbox` | Waiting mail (up to 20) and this phone's address. |
| `POST /inbox/address` | Makes the phone's address from a first name: `name-` plus 8 letters or digits. |
| `GET /inbox/file?id=&n=` | One attachment of a waiting mail. |
| `POST /inbox/ack` | Forgets mail the phone has saved. |
| `POST /me/delete` | Forgets the address, the box and all waiting mail for the phone. |

Mail sent to an address arrives through Email Routing (`email()` in `worker.js`).

The old Worker (`../perplexity-relay.js`, `shoebox-relay`) keeps `shoebox-api.tangomike.app` for Shoebox 1 and is not changed. Nothing in the app calls it any more.

## What it keeps

| What | How long |
|---|---|
| Mail and attachments | 7 days, or until the phone acknowledges them |
| Address and box | 90 days after the phone last asked (renewed at most once a day) |
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

Mail to an address nobody holds is dropped without a bounce, so the relay never says which addresses exist.

## Owner

No phone becomes the owner by asking first. The one shared address (optional) is `EMAIL_ADDRESS`; it delivers to the phone whose inbox key is the `OWNER_INBOX_KEY` secret, and to nobody if the secret is not set.

## Settings

Secrets: `PIXABAY_API_KEY`, `OWNER_INBOX_KEY` (optional).
Variables: `EMAIL_DOMAIN` (default `inmyshoebox.com`), `EMAIL_ADDRESS` (optional), `MINT_DAILY_CAP`, `MAILBOX_DAILY_CAP`, `STOCK_HOURLY_LIMIT` (all optional). `PIXABAY_BASE_URL` is for local tests only.
Binding: KV `SHOEBOX`, a namespace made for this Worker.

## Tests

```sh
node --test relay/app/test/worker.test.mjs
```

## Deploy

Not by hand. `docs/handoff/grok-relay-deploy.md` has the steps in order, with the ones that can't be undone first.
