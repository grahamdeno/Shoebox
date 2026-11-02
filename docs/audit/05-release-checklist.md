# App Store release-readiness checklist

**Graham presses Submit for Review. Agents stop at an uploaded build with everything below filled in.**

## Before external TestFlight

- [x] Privacy policy at `https://inmyshoebox.com/privacy`, set in App Store Connect
- [ ] Policy updated for 7-day retention, children's details, preview cache, EU and California rights
- [ ] Policy linked from Settings › Privacy
- [ ] Terms published (suggest `https://inmyshoebox.com/terms`)
- [ ] Support URL live (`https://inmyshoebox.com/support`)
- [x] `support@inmyshoebox.com` reaches Graham's Gmail under Support/Shoebox (tested November 2)
- [ ] Beta App Description and What to Test written
- [ ] Beta App Review contact and demo notes (same as review notes below)
- [ ] Relay split and deployed from this repo; `/stock` and `/me/delete` answer correctly
- [ ] Workers Paid plan on

## Metadata

- [x] Name "Shoebox: Your Own Feed" on the record; subtitle "Keep it. Come back to it."
- [ ] Description that promises only built features: share sheet, Keep something, forwarding email (Plus), dates read from what you keep, one post at a time, daily notification, backups. No Siri, Watch, Lock Screen, widgets or flyer reading until built
- [ ] "Best on iPhones with Apple Intelligence" in the description
- [ ] Keywords (100 chars)
- [ ] Category: Productivity; secondary Lifestyle
- [ ] Age rating questionnaire: no objectionable content; 4+
- [ ] Copyright line; seller name
- [ ] Version 1.0 on the existing record (`com.grahamdeno.shoebox`); `MARKETING_VERSION` set to 1.0.0
- [x] Availability: US, Canada, Mexico, UK, Australia, New Zealand; no EU; future countries off (set November 2)
- [ ] Price set to Free in Pricing (needed before submission)
- [x] Small Business Program submitted (November 2); approval email pending
- [ ] Paid Apps Agreement active (W-9 and bank account)
- [ ] In-app purchase "Shoebox Plus" (non-consumable) created, priced, with review screenshot

## Privacy nutrition label

Collected, all **linked to the user? No account, but the address identifies them: answer Linked**, **not used for tracking**, purpose **App Functionality**:
- [ ] Contact Info › Email Address (the sender address inside forwarded mail)
- [ ] Contact Info › Name (first name in the forwarding address)
- [ ] User Content › Emails or Text Messages (forwarded mail, until collected, up to 7 days)
- [ ] User Content › Other User Content (attachments, link URLs sent for previews)

Not collected: usage data, diagnostics, identifiers, location, contacts, health, financial. Match `PrivacyInfo.xcprivacy` to this list (P-2).

- [ ] Required-reason APIs declared: UserDefaults CA92.1, 1C8F.1 in the app and the share extension (P-3)
- [ ] `ITSAppUsesNonExemptEncryption` NO (set, `project.yml:45`)

## Screenshots (6.9-inch and 6.5-inch)

- [ ] Today with a photo post and the reason line
- [ ] Today with a dated school post ("Saturday, Nov 14 · 5:00 PM")
- [ ] The Shoebox with Coming up
- [ ] Share sheet keeping a link with a reason
- [ ] The opened post
- [ ] Dark mode (Plum Night)
- [ ] Demo data free of work jargon and black (SampleData fixes), generated from the `[screens]` run

## Review notes and demo path

- [ ] No login. Explain: "Shoebox has no accounts. Everything stays on the phone except link previews, generic stock-picture words and forwarded email."
- [ ] Demo path: 1. finish the four welcome screens; 2. tap + New, paste any link, add a reason, Keep; 3. pull the post down to put it away, flick up for next; 4. to test email, open Settings › Email, enter a first name, Get address (Plus is unlocked for review with a promo code or sandbox), forward any email to it, reopen Shoebox.
- [ ] Say that AI runs on the device; on a device without Apple Intelligence, posts use plain rules.
- [ ] Say how to delete: Settings › Delete everything removes posts and the email address on the server.
- [ ] Mention notifications are local, one a day, at a time the user picks.

## Build

- [ ] Built with a pinned, released Xcode (Q-1)
- [ ] Tests passed on the same commit (Q-1)
- [ ] Entitlements in the IPA: App Group and iCloud Documents (Q-6)
- [ ] No crash in a 24-hour TestFlight window; MetricKit reports clean (Q-2)
- [ ] Tested on a device without Apple Intelligence and on one with it
- [ ] Tested at the largest Dynamic Type size and with VoiceOver (after X-1 to X-4)
- [ ] Update path from TestFlight build 36 checked on your phone (D-10)
