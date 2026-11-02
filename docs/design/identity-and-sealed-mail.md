# Mailbox identity, sealed mail and the Plus gate

Design for D-5 (Keychain), R-13 (sealed mail), M-1 (Shoebox Plus gate) and D-6 (Delete everything retries). Written November 2, 2026, for the v1.0 batch. These four share one question: what the phone holds, what the relay holds, and how a new phone gets back in.

## Irreversible or outside-the-repo steps, first

1. **Workers Paid on before the public TestFlight link goes out.** On the free plan a Worker gets about 10 ms of CPU per email (Cloudflare: email Workers count against the standard Workers CPU limits; inbound messages are capped at 25 MiB). Graham's own forwards fit: 20 since late October, the largest 2.8 MB, no bounces. Strangers' mail is not predictable, so upgrade before they arrive. Graham, or Grok with Graham's yes.
2. **Paid Apps Agreement active** (W-9, bank account) in App Store Connect. Needed to test the purchase in the sandbox. Graham.
3. **Create the in-app purchase** `com.grahamdeno.shoebox.plus`, non-consumable, $9.99, Family Sharing on. **A product id can never be reused or changed.** Grok with Graham's yes, after this design is accepted.
4. **Redeploy the app relay** with sealing and the purchase check (`wrangler deploy`; the code gains an import, so the dashboard editor no longer works). Rollback: `wrangler rollback` to the version Grok deployed on November 2.

## What each side holds

| | Phone | Relay |
|---|---|---|
| Mailbox secret (today's `inboxKey`, `sb-` + 40) | Keychain, synced through iCloud Keychain | Only a hash of it (the box id) |
| Sealing key pair (X25519) | Private key in the Keychain, synced | Public key in the box record |
| Address | App Group defaults (display only) | `alias:<slug>` and `box:<id>`, 90 days idle |
| Plus purchase | StoreKit | `buy:<originalTransactionId>`: the boxes it has opened, up to 5 |
| Forwarded mail | Posts made from it | Sealed blob, size, arrival time, 7 days at most |

**Server-blind, stated exactly:** Cloudflare's email system and the Worker see each message in memory while it is delivered. Nothing readable is stored: the sender, subject, text, links and attachments are sealed to the phone's public key before they are written. The relay cannot open what it stores, and neither can Graham or Cloudflare.

## D-5: the mailbox secret in the Keychain

- Keychain item: service `com.grahamdeno.shoebox.mailbox`, account `secret`, `kSecAttrAccessibleAfterFirstUnlock` (background refresh runs while the phone is locked), `kSecAttrSynchronizable` true. App only; the share extension never needs it.
- Move on launch: if App Group defaults hold `inboxKey` and the Keychain does not, write it, read it back, compare, and only then remove it from defaults. If the write fails, leave defaults alone and try next launch.
- Backups stop carrying the key (`Backups.swift:234`). Restoring an old backup that has one imports it only when the Keychain has none. The "before delete" copy never carries it.
- Reading the key goes through one place (`MailboxKeys`), never `Prefs.inboxKey`.

## R-13: sealed mail

**Scheme: HPKE (RFC 9180), base mode, DHKEM(X25519, HKDF-SHA256), HKDF-SHA256, AES-256-GCM.** It is a published standard, the phone has it built in (CryptoKit `HPKE`, iOS 17 and later), and the Worker uses `@hpke/core` (pinned exact version) on Web Crypto. Nothing hand-rolled.

- **Phone:** makes the key pair once, on first need, stores the private key's raw bytes in the Keychain (service `com.grahamdeno.shoebox.mailbox`, account `seal`, synced). Sends the public key (base64, 32 bytes) when it makes an address, and with `POST /inbox/seal` when it has an address but the relay has no key or a different one.
- **Relay, on each mail:** parse as today, then seal one JSON object `{from, fromName, subject, text, links, attachments: [{n, name, type, size}]}` with `info = "shoebox-mail-v1"` and `aad = "<box>:<id>"`. Each attachment is sealed on its own with `aad = "<box>:<id>:<n>"`. Stored record: `{v: 1, id, at, enc, ct}` (base64). No plain field holds anything from the message.
- **A box with no public key** cannot receive: the relay bounces with "Open Shoebox to finish setting up your address." No plain copy is ever stored.
- **Phone, on collect:** opens each record. A record it cannot open (the key was lost, or a new phone without iCloud Keychain) is acknowledged and counted. Settings › Email then shows one quiet line: "1 email couldn't be opened on this phone." Nothing is retried forever, and nothing is lost for more than 7 days, because the relay would delete it anyway.
- **Records without `v`** (plain mail from before this change) are read as today for 1.0 and dropped in 1.1. Only Graham's phone has any.
- **Test vectors:** the relay tests seal a fixed message with a fixed key pair and ephemeral seed (HPKE's deterministic test mode), write the result to `relay/app/test/vectors/sealed-v1.json`, and a Swift test opens that same file with CryptoKit. That proves the two sides agree byte for byte. Both test suites also check the RFC 9180 published vector for this suite.

## M-1: the Plus gate

- Product `com.grahamdeno.shoebox.plus`, non-consumable, $9.99, Family Sharing on.
- **Phone:** StoreKit 2. `Transaction.currentEntitlements` gives the verified transaction; its `jwsRepresentation` goes in the body of `POST /inbox/address` and `POST /inbox/seal` as `purchase`. Restore purchases is `AppStore.sync()`, a quiet word in Settings. The app never decides on its own that someone has Plus without StoreKit saying so.
- **Relay:** checks the JWS:
  - an x5c chain to Apple Root CA G3 (embedded)
  - ES256 signature
  - `bundleId` = `com.grahamdeno.shoebox`
  - `productId` = `com.grahamdeno.shoebox.plus`
  - no `revocationDate`
  - `environment` Production, or Sandbox while `ALLOW_SANDBOX` is `1` (the default)

  Sandbox is needed for TestFlight and for App Review, which buys in the sandbox against the release build. The certificate parsing from the old relay's App Attest check (`readCert`, `signedBy`) is reused, copied and tested.
- **One purchase opens at most 5 boxes** (`buy:<originalTransactionId>`), which covers a family and a few new phones and stops one JWS being shared to make addresses for everyone. A sixth gets "This purchase is already on five phones. Write to support@inmyshoebox.com."
- **What it gates:** making an address and registering a sealing key. Collecting mail (`GET /inbox`), files, ack and delete are never gated: an address that exists keeps working, a refund stops only new addresses.
- **The rate limits stay.** They now sit behind the purchase rather than in front of everyone.
- **Copy:** Settings › Email shows "Get your address with Shoebox Plus" and the price from StoreKit. Never in the first run; offered after the first week (SPEC 9).

## D-6: Delete everything that finishes

1. Save the "before delete" copy (as today, now without the key). No copy, no delete.
2. Delete the posts, clear "Who it's about", the address and the pick.
3. Move the mailbox secret to a Keychain item `pendingDelete` and remove `secret` and `seal`. From here the app has no mailbox.
4. Call `POST /me/delete` with the pending secret. On 200, remove `pendingDelete`. Otherwise try again on every launch, every return to the app and every background refresh until it answers 200. The request is safe to repeat.
5. While pending, Settings shows one quiet line: "Removing your address from the server."
6. The relay's `/me/delete` also removes the box from its `buy:` record, so the purchase can open a box on the next phone.

## A new phone

- **Same Apple Account, iCloud Keychain on:** the secret and the sealing key arrive with the account. The first collect finds the address and opens the mail. Nothing to do.
- **iCloud Keychain off or another account:** no secret, so Settings › Email offers an address. Plus comes back with Restore purchases. The old address expires 90 days after it was last used. Mail sent to it meanwhile cannot be opened, and is counted and dropped as above.
- **Two phones on one account** share one mailbox: whichever collects first gets the post. That is acceptable for an iPhone-only 1.0 with no sync, and goes away if sync is added.

## Privacy policy changes

- "Forwarded email is sealed to a key that only your phone holds before it is stored. We cannot read it."
- "Your phone's mailbox key is kept in your iCloud Keychain so a new phone can collect your mail."
- Delete everything: replace the "does not retry" note with "the app keeps asking until the server confirms".
- Purchases: "When you get an address, the app sends Apple's signed proof of your Shoebox Plus purchase. We keep its transaction number to limit it to five phones."

## Tests that must exist

- **Keychain move:** defaults to Keychain, read back before removal, a failed write leaves defaults, a restored backup only fills an empty Keychain, backups never contain the key.
- **Sealing:**
  - shared test vectors, opened in Swift
  - the RFC 9180 vector on both sides
  - a record with the wrong aad does not open
  - the relay stores no plain field
  - a box without a key bounces
- **Gate:** a valid sandbox and production JWS pass; a wrong bundle, wrong product, revoked or tampered JWS, or a self-signed chain fails; a sixth box is refused; collect and delete are never gated.
- **Delete:** offline delete leaves `pendingDelete`, a later 200 clears it, a 500 keeps it, and the app holds no secret or seal key after step 3.

## Not in this design

CloudKit sync, App Attest, moving Pixabay photos to R2, Durable Objects. See the reasons given November 2: they guard against users who don't exist yet, or close a door that is hard to reopen.
