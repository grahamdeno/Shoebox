# Sonnet: the newsletter in the sample data, the `dates` screen, and one copy fix

**Branch:** `video-newsletter` (already has the video sheets). Commit on it; the PR is open. Don't merge: Graham says ship.
**Why:** the promo and short 3b now lead with the newsletter (`docs/video/01-promo.md` shot 5, `03-feature-shorts.md` 3b). Video rule 1 says every screen comes from CI screenshots of the sample data, and the sample data has no newsletter. Nothing in the app changes except the onboarding example and the debug sample data.

## 1. Sample data: six dates from one newsletter

In `App/Shoebox/Model/SampleData.swift`, add six email posts that look exactly like what `Inbox` makes from a newsletter with many dates (`Inbox.swift` around line 135, SPEC section 4, Email row):

- `kind: .email`, `origin: "Maple Grove newsletter"` (so `byline()` reads "from Maple Grove newsletter"), `emailSubject: "Maple Grove Middle School: November news"`, `emailFrom: "office@example.org"`, `emailReceivedAt` and `createdAt` the same for all six.
- `title` up to six words. `snippet` and `body` start with the day: `"Thursday, Dec 10 · 6:30 PM · Auditorium · 7th and 8th grade band."` Build the day text from the real `eventDate` with a `DateFormatter` so it is never wrong.
- `eventDate` relative to `now`: about 9, 13, 16, 20, 27 and 34 days out, so all six sit in Coming up (within two months) and the nearest shows its number in Sunflower. Give two of them a time (`eventHasTime = true`).
- Status and `returnDate` as `Inbox.schedule` would set for a post that arrived today: use the same call, or match what it does.
- No pictures. A newsletter date post gets a picture of its own subject or none (SPEC 4.1); none is honest and Plum with Sunflower looks right.
- Make the existing "Picture day" post one of the six: same origin and subject, its first line starting with its day.
- The six, all fictional, about "Sam, 7th grade, band" and school-wide days. Suggested: Winter band concert (time), Picture day, Early release day, 7th grade field trip forms due, Band fundraiser pickup (time), No school: teacher workday. No real school, town, child or event.
- Set the demo "Who it's about" line so Settings reads the same story: in demo mode, `Prefs.mailFor = "Sam, 7th grade, band"` if it is empty (find where `-demo` is handled in `ShoeboxApp.swift`).

The concert post stays the lead on Today (it is returning, so it is first).

## 2. The `dates` screen

- `ShoeboxApp.swift` / `TodayView.swift`: add `case "dates"` next to `"opened"`: move the newest newsletter date post (the one with the soonest `eventDate` and `origin == "Maple Grove newsletter"`) to the front of the queue, so the screenshot shows it full screen on Today with its byline and first line. No other state.
- `Scripts/screens.sh`: add `dates` to `SCREENS` (after `today`).
- `docs/video/style.md` already lists `dates` in the screenshot table.

## 3. The onboarding copy fix

`App/Shoebox/Onboarding/Onboarding.swift` line 72: the example "For the trip" is not something the app reads (SPEC 3.1 reads weekdays, "before Monday", weekend, tonight, tomorrow). Change it to:

`"Before Saturday" brings it back Friday evening.`

Check `docs/design/screens/` and SPEC 2.5 for the same sentence and change them to match.

## 4. Checks you do yourself

- `xcodegen` if needed, then build and run the tests (`Scripts/` has the CI commands; `.github/workflows/ios.yml` shows them).
- Run the app in the simulator with `-demo YES -screen dates` and `-screen box` and look: the byline reads "from Maple Grove newsletter"; Coming up lists the six and the concert soonest first with no empty tiles; nothing on the status bar matters (videos mask it).
- Commit with the message `Sample newsletter dates, the dates screen, onboarding example [screens]` so `screens.yml` builds the new screenshots to `ci-screens`. Report the run link. Do not wait for it.

## 5. Report back

Say which commit, that `[screens]` ran, and anything that did not match this sheet. Then Graham brings Grok in: video 4 finishes first, then video 1 again from the new sheet.
