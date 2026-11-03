# Identity and sealed mail: steps outside the repo (prompt for Grok)

**Who runs this:** Graham gives the prompt below to Grok. Claude cannot reach npm, apple.com or Cloudflare from its workspace.
**Branch:** `v1/identity-build` (PR to `main`, draft). Design: `docs/design/identity-and-sealed-mail.md`.
**Model for the next step:** Opus to review the sealing, the purchase gate and the delete judgment before "ship"; Sonnet to build and ship afterwards.

## Irreversible or outside the repo. Read these first.

1. **Create the in-app purchase** `com.grahamdeno.shoebox.plus` in App Store Connect: non-consumable, $9.99, Family Sharing on. **ASK.** A product id can never be reused or changed. Needs the Paid Apps Agreement. Only after Graham accepts the design.
2. **Deploy the relay** with `wrangler deploy -c relay/app/wrangler.jsonc` from `relay/app` after `npm ci`. **ASK.** From that moment new addresses need Plus, and old addresses bounce until their phone registers a sealing key. Rollback: `wrangler rollback` to the version from 2 November.
3. **Workers Paid** on the day a public TestFlight link goes out. **ASK.**

Nothing below changes anything outside the repo. Do it before step 2.

## The prompt

> You are finishing three files for Graham's repo `grahamdeno/Shoebox`, branch `v1/identity-build`. Do not merge. Never paste secrets anywhere. Report each step as done, skipped or failed, with the exact output of the checks.
>
> **A. Packages.** In `relay/app`: `npm install --save-exact @hpke/core @hpke/dhkem-x25519`. Commit `package.json` and `package-lock.json`. If the `@hpke/core` API in `seal.js` (`CipherSuite`, `suite.seal`, `kem.deserializePublicKey`, `ekm`) does not match the installed version, stop and report the exact error. Do not edit `seal.js` to fit.
>
> **B. Vectors.** Run `node --test test/*.test.mjs` in `relay/app`. This writes `test/vectors/sealed-v1.json`; commit it. Then from the CFRG test vectors file (`test-vectors.json` in `cfrg/draft-irtf-cfrg-hpke`), copy the entry with `mode` 0, `kem_id` 32, `kdf_id` 1, `aead_id` 1 into `test/vectors/rfc9180-a1.json` and commit it. Run the tests again; the RFC test must pass, not skip. Note: RFC 9180 has no AES-256-GCM vector for this KEM, so the test uses the AES-128-GCM one. This is a known deviation from the design.
>
> **C. Apple root.** Download `AppleRootCA-G3.cer` from https://www.apple.com/certificateauthority/ . Compute its SHA-256 fingerprint and compare it with the value Apple publishes on that page. If they differ, stop. If they match, put the base64 of the DER file in `relay/app/apple-root-g3.js` as `APPLE_ROOT_CA_G3_B64` and commit. Run the tests; the skipped purchase test must now pass.
>
> Push to the same branch. Then wait for the CI run on the PR and report its result. If the Swift tests fail, paste the failing test names and messages; do not fix Swift.
