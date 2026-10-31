# Shoebox relay

The Cloudflare Worker `shoebox-relay`, live at `https://shoebox-api.tangomike.app`. It does what the app can't do on its own: link previews (`/preview`, `/image`), photo search through Pixabay (`/photo`), the email inbox (`inmyshoebox.com` addresses, `/inbox/*`), reminders and notifications (`/push/*`, `/remind`, a 15-minute Cron Trigger), Claude calls with Shoebox's own key (`/ai/*`), Apple Music tokens and calendar pass-through.

This folder is the source of the live version `91ae1328-009c-4a83-8ec4-3374c658297f` (deployed 31 Oct 2026, "photo via Pixabay"). Its bundle was checked byte for byte against what Cloudflare runs.

## The old copy

`grahamdeno/edition/relay` is the older copy (Openverse `/photo`). edition is frozen. Never deploy from it: it would overwrite this version and drop the Pixabay `/photo`. Deploy from here only.

## Deploy

1. In `wrangler.jsonc`, replace `REPLACE_WITH_SHOEBOX_KV_NAMESPACE_ID` with the id of the existing SHOEBOX KV namespace. Don't commit it.
2. From this folder:

```sh
npx wrangler deploy -c wrangler.jsonc
```

The secrets and dashboard variables stay as they are (`keep_vars`).

## Roll back

```sh
npx wrangler rollback 0f023bc7-068d-4b98-88d8-2163a0968205 --name shoebox-relay
```

Versions:

- `0f023bc7-068d-4b98-88d8-2163a0968205`: before Pixabay (Openverse `/photo`).
- `bdba0fc9-94cc-4044-88a5-5e6e64915703`: the same old code, with the `PIXABAY_API_KEY` secret attached.
- `91ae1328-009c-4a83-8ec4-3374c658297f`: current (Pixabay `/photo`).

## Secrets (names only)

Set with `npx wrangler secret put <NAME> --name shoebox-relay`. Never commit values.

- `ANTHROPIC_API_KEY`: Claude calls.
- `APPLE_P8`: the Apple key file, for Apple Music tokens.
- `PIXABAY_API_KEY`: `/photo`.

## Bindings and settings

- KV namespace bound as `SHOEBOX` (id kept out of the repo, see Deploy).
- Cron Trigger `*/15 * * * *` (reminders).
- Custom domain `shoebox-api.tangomike.app`.
- Email Routing: the `inmyshoebox.com` catch-all sends mail to this Worker.
- Dashboard variables (not secret): `EMAIL_ADDRESS`, `EMAIL_DOMAIN`, `EMAIL_ALIASES`, `AI_DAILY_CENTS`, `AI_DEVICE_DAILY_CENTS`, `AI_OWNER_DEVICES`. Optional, read by the code with defaults: `AI_DEVICE_MONTHLY_CENTS`, `AI_NETWORK_DAILY_CENTS`, `AI_ATTEST`, `PHOTO_HOURLY_LIMIT`. `PIXABAY_BASE_URL` is for local tests only (localhost).

## /photo

`GET /photo?q=<words>&n=6`, Origin `https://inmyshoebox.com` only (else 403). `q` is 1 to 80 characters (else 400), `n` defaults to 6, at most 8. Answers `{"photos":[{"id","url","width","height","alt","by","page"}]}`, cached 24 hours per phrase, about 60 searches per network per hour (then 429). Never logs the search words or addresses.

Pixabay allows its image links only for showing search results for a while. Copy a chosen photo to Shoebox's own storage before keeping it in a post, and credit Pixabay where results show (`by`, `page`).
