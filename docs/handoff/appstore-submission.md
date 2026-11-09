# Shoebox 1.0: App Store submission handoff

Written November 9, 2026, at the end of the glass-lid chat. For a new chat whose job is getting Shoebox 1.0 submitted. Repo: `grahamdeno/Shoebox`. Read `CLAUDE.md`, then this file.

## Irreversible steps. Read first.

1. **Submit for Review: Graham presses it himself.** Agents (Claude, Grok) stop before "Add for Review" and "Submit for Review".
2. **Creating the in-app purchase `com.grahamdeno.shoebox.plus`.** A product id can never be reused or changed. Non-consumable, $9.99, Family Sharing on. Needs the Paid Apps Agreement active first. Ask Graham before creating it.
3. **Workers Paid ($5/month) on Cloudflare** before any public TestFlight link goes out. Ask Graham.
4. **Relay deploys** change the live server. Grok runs them with `wrangler deploy`, reports the current version first (the rollback point) and waits for Graham's yes.

## Where things stand

- **Latest build:** 1.0.0 (1571), TestFlight run 57, from main after PR #53. Includes the glass lid, the Stone colors, the sheet gesture fixes and the picture fixes.
- **App Store Connect version is named "1.0", but builds are "1.0.0".** That is why no build can be attached. Fix: rename the App Store version to **1.0.0** (allowed before the first submission), then attach the newest build. No new upload needed.
- **Screenshots:** done. Six at 6.9 inch (1320 x 2868) uploaded by Grok on November 4: 1-today, 2-put-away, 3-shoebox, 4-opened, 5-keep, 6-stone-settings. No 6.5-inch set (the store scales the 6.9-inch set down). Files: `appstore-screens` branch.
- **Relay:** `shoebox-app-relay` at `api.inmyshoebox.com`, version `99987eae-fd0b-4728-85b5-270a1d67e44e` (deployed November 4, 4:07 PM ET). The one before it, for rollback: `25327fde-d57c-4e44-af5a-970f666aec84`. Sealed mail and the Plus gate are live. `PLUS_OWNER_ADDRESS` is set to Graham's address, so his mail works before Plus is on sale. Secret: `PIXABAY_API_KEY`.
- **Already set in App Store Connect:** name "Shoebox: Your Own Feed", subtitle, availability (US, CA, MX, UK, AU, NZ; no EU), Small Business Program applied for. `support@inmyshoebox.com` reaches Graham's Gmail.

## What is left, in order

| # | Step | Who | Notes |
|---|---|---|---|
| 1 | Paid Apps Agreement: W-9 and bank account | Graham | On hold until Apple updates his mailing address. Blocks step 4. |
| 2 | Rename the App Store version 1.0 to 1.0.0; attach the newest build | Grok | No new build needed. |
| 3 | Price: Free | Grok | Needed before submission. |
| 4 | Create Shoebox Plus (non-consumable, $9.99, Family Sharing on, review screenshot) | Grok, after Graham's yes | Irreversible id. Needs step 1. |
| 5 | Privacy policy and terms: update and publish at `inmyshoebox.com/privacy` and `/terms`; support page at `/support` | Claude drafts, Grok publishes | Drafts: `docs/legal/privacy.md`, `docs/legal/terms.md`. Must describe sealed mail, the Keychain key, 7-day mail retention, the Plus purchase check (five phones per purchase), and Delete everything retrying until the server confirms. Design: `docs/design/identity-and-sealed-mail.md`. |
| 6 | Description, promotional text, keywords, categories (Productivity, Lifestyle), age rating 4+, copyright | Grok pastes | Text: `docs/appstore/1.0-text.md`. Check it still matches what is built (glass lid, Stone colors). |
| 7 | Privacy nutrition label | Grok, from the list | `docs/audit/05-release-checklist.md`, section "Privacy nutrition label". |
| 8 | Review notes and demo path | Grok pastes | Same checklist, section "Review notes and demo path". Plus is offered at once in the sandbox, so reviewers can reach it. |
| 9 | Workers Paid | Grok, after Graham's yes | Before any public TestFlight link. |
| 10 | Final check of every field, then hand back | Claude | Graham presses Submit for Review. |

The full checklist, with what is ticked: `docs/audit/05-release-checklist.md`.

## Not confirmed yet

- **Test email after the relay deploy:** Grok asked Graham to send one to his Shoebox address on November 4. Not confirmed it arrived as a post.
- **Pictures on 1571:** Settings › Pictures shows a "Last look" line. Not checked since the 6-second spacing went in. Most posts should now say "found a picture".
- **Tester group error (422)** when adding builds to a group with automatic distribution: `Scripts/asc_testflight.py` should skip such groups. Not fixed. Harmless; the build still reaches testers.

## How to work (from `CLAUDE.md` and Graham's rules)

- Graham picks the model per step: Opus for judgment and data safety, Sonnet for building and shipping. Name the next model at every handoff.
- Branch, PR, and Claude merges. Never work on main. Don't merge or push to `testflight` until Graham says "ship".
- Steps Claude can't do (App Store Connect, Cloudflare, the website) go to Grok as a complete prompt, ready to paste, with the irreversible steps first. Grok reports back.
- Don't sit and wait on CI. Start it, say what to expect, stop.
- **Mac CI queue:** GitHub's `macos-26` runners sometimes leave a job waiting about 15 minutes and then cancel it. Re-run the failed job. If a run can't be re-run again, push an empty commit to the branch.
- **Pixabay** refuses searches closer than a few seconds apart (the relay reports `x-reason: pixabay-429`). The app spaces searches six seconds apart. If pictures stay thin, the fallback is switching the relay to Pexels.

## Loose ends in the repo

- **`appstore/shots`** (not merged): the 6.9-inch App Store screenshot job (any `appstore/...` branch, with `[screens]` in a commit), real Pixabay photos for the sample posts, and everyday sample posts in place of the old work note. Merge to main with Graham's "ship" so future screenshots come from main.
- **`probe/stock`**: a throwaway job that tests the relay's `/stock` route from Linux. Safe to delete.
