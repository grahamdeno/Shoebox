# Handoff: submit Shoebox 1.0 to the App Store

Start a new chat with this file. Written Nov 9, 2026.

## Crucial: who presses what
- **Graham presses Submit for Review himself.** Stop before it.
- **Creating the Plus in-app purchase is permanent:** its product ID `com.grahamdeno.shoebox.plus` can never be reused. Grok creates it only after Graham says yes.
- **Relay deploys, deleting anything, and publishing go through Grok, who asks first.** Never paste secret values or the review phone number into chat, files or screenshots.
- **Don't merge or ship until Graham says "ship".**

## Where things are
- App, relay and website: `grahamdeno/Shoebox` (public). Read `CLAUDE.md`, then `docs/PLAN.md` and `docs/SPEC.md`.
- Full checklist: `docs/audit/05-release-checklist.md`. Its boxes are not up to date, so check each item against the real state.
- Website: `web/` on `main`, served by Cloudflare Pages at inmyshoebox.com (`/privacy`, `/terms`, `/support` are live; privacy updated Nov 9).
- Relay: `relay/app`, Worker `shoebox-app-relay` at api.inmyshoebox.com. Live version `a434910c-4914-4ccf-b5c9-edfd38c6101e`; rollback `eefd72c8-1411-4a25-b9ce-791d6d3130b7`. Deploy steps: `docs/handoff/grok-relay-deploy.md`.
- The old repo `grahamdeno/edition` is archived and private. Don't deploy from it.
- TestFlight: pushing `main` to the `testflight` branch builds and uploads. The latest build is `main` at 9fdc9e6.

## Done
- 1.0 features built and on TestFlight with 3 testers: newsletter dates, the daily limit of 10, Undo, swipe left to Delete on Today.
- Privacy page checked line by line against the app and relay (Nov 9). Relay logging is off.
- UX audit green on 0cf77d9. Reduce Transparency and Reduce Motion checked on the phone.

## Left before Submit for Review
1. **Graham confirms swipe left then Delete works** on the 9fdc9e6 build. It shipped without its simulator check. Run the audit's new J2 Delete step with an `[audit]` commit.
2. **Paid Apps Agreement** active (W-9, bank). It was waiting on Apple's address update. Graham checks.
3. **Plus in-app purchase** (non-consumable, "Shoebox Plus", $20) created, priced, with its review screenshot. This depends on step 2, and Grok creates it after Graham's yes.
4. **App Store Connect metadata:** description (only built features; "Best on iPhones with Apple Intelligence"), keywords, category Productivity and Lifestyle, age rating 4+, copyright, price Free, version 1.0.
5. **Privacy nutrition label** as listed in the checklist (email address, first name, forwarded mail, other user content), plus the required-reason API declarations.
6. **Screenshots** (6.9-inch and 6.5-inch) from a `[screens]` run. Settings now shows "Each day: 10".
7. **Review notes:** no login, the demo path, AI on the phone, Delete everything, local notifications. The draft is in the checklist.
8. **Relay switches for review:** set `ALLOW_SANDBOX="0"` before Submit. Remove `PLUS_OWNER_ADDRESS` once Plus is on sale. Grok does both, asking first.
9. **VoiceOver check** on the phone. It was skipped; Graham decides whether it blocks.
10. **Graham presses Submit for Review.**

## Also open (not blocking)
- Send testers the task 5 correction: "set it to show 5 posts a day, not 3."
- Upgrade to Workers Paid ($5 a month) the day a public TestFlight link is posted.
- Delete the old Worker `shoebox-relay` and its storage around Dec 4, as its own yes.
- Family details sit in the public repo's history; decide on a cleanup before a public launch.
- Shorts: post 3d (Graham); 3a and 3c not started.

## How Graham works
- Ask one specific question at a time. Write plainly and compactly, with no em-dashes.
- Name the model for each step: Opus for judgment and data safety, Sonnet for building and shipping.
- For anything Claude can't do, write a full Grok prompt, irreversible steps first, ending with "report back".
- Mac builds are free while the repo is public. Run `[audit]` and `[screens]` only before a release.
