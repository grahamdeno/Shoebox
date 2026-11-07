# 08. The UX audit: walking the real app

Started November 7, 2026. Run by `.github/workflows/ux-audit.yml` on any branch commit whose message contains `[audit]`.
The report (every picture, check, timing and accessibility issue) lands on the `ci-audit` branch as `SUMMARY.md` and
`sheets/`.

## 1. What it can and cannot tell us

Three layers, each answering a different question. The simulator proves the first; it cannot prove the third.

| Layer | Question | Who | Evidence |
|---|---|---|---|
| 1. Functional walk | Does every step work as SPEC says? | XCUITest in the CI simulator (`App/ShoeboxUITests`) | A check per step, a picture per step, timings |
| 2. Expert review | Is each step clear, findable and calm? | Opus reading the pictures against the rubric (section 5) | Findings rated 1 to 4, in `backlog.csv` |
| 3. Real people | Can a stranger do it, and how does it feel? | Five TestFlight testers, five tasks (section 7) | Task success, a one-question ease score per task, SUS |

A usability score comes only from layer 3. Layers 1 and 2 clear the obvious problems first so testers spend their time
on the ones only people find.

## 2. The journeys

Each journey is one job, walked the way a person does it. A check that fails is written down and the walk goes on.

| # | Journey | Steps |
|---|---|---|
| J1 | First launch | Welcome, Save from anywhere, When they come out (Not now), Three moves, Try it, Today |
| J2 | Today's moves | Tap opens, Close; flick up, Undo; pull down, Undo; a short drag changes nothing; Undo leaves after 5 s; go through the whole day to its end |
| J3 | An opened post | The moves as words, scroll, Edit the title, Keep, the edit shows; Edit, Delete, Undo offered |
| J4 | Keep something new | + New, Keep waits for words, a note, Why "Before Friday", the return line reads it, Photo or file menu, Keep, the box count grows |
| J5 | The Shoebox | Put one away, open the box, Today and Settings words, scroll, Put away (n), Just put away with "Put away today", a topic, search "band", search with no match |
| J6 | Settings | Each row opens its screen and comes back: Each day, Look (Stone and back), Pictures, Backups, How Shoebox works, Privacy; Delete everything offers a way out; Close |
| J7 | Empty states | Today clear, Go through your Shoebox |
| J8 | Five weeks (time replay) | See section 3 |

Not walked by the simulator: the share sheet from another app (the system's sheet cannot be driven reliably; its
screen is covered by the `share` still and by testers), the email address purchase (Plus), notifications arriving.

## 3. Time replay

Shoebox's promise is that things come back. A ten-minute walk never sees that. The debug build reads `-dayOffset N`
(with `-demo YES`) and moves the app's clock N days on (`Shared/Clock.swift`; always the real time in a release build).
`-replay YES` keeps the sample store on disk between launches, apart from the real store. J8 relaunches the app on
days 0, 4, 9, 11, 13, 20 and 35 after the school newsletter arrives and checks:

- day 0: the six dates arrive, shown once;
- day 4: the first date (9 days out) is back, 5 days before;
- day 9: Picture day is on Today; it is put away;
- day 11: it is under Just put away;
- day 13: it has left Just put away, still in Put away;
- day 20: the week-one concert moved to Kept on its own;
- day 35: the last date is past and in Kept.

## 4. Conditions

Five runs at once, one runner each:

| Config | Phone | Look | Colors | Text | Journeys |
|---|---|---|---|---|---|
| pro-light | iPhone 17 Pro | Light | Pistachio | Default | All, with time replay |
| pro-dark | iPhone 17 Pro | Dark | Plum | Default | J1 to J7 |
| stone-dark | iPhone 17 Pro | Dark | Stone | Default | J2, J5, J6 |
| big-text | iPhone 17 Pro | Light | Pistachio | Accessibility XXXL | J1 to J7 |
| small-phone | iPhone SE, else 16e | Light | Pistachio | Default | J1 to J7 |

Reduce Motion, Reduce Transparency and VoiceOver cannot be switched on in the CI simulator from a test. They are
reviewed in the code (section 6) and on a real phone (section 7).

Apple's accessibility audit (`performAccessibilityAudit`: contrast, hit areas, labels, clipped text, Dynamic Type,
traits) runs on every main screen in every config.

## 5. The rubric

Each finding gets a severity: 4 blocks the task, 3 a person will stumble, 2 slows or confuses, 1 cosmetic.

Heuristics used on every picture:

1. Can a first-time person tell what to do next, without onboarding?
2. Does every action say what it did, and can it be undone?
3. Is every hidden gesture also a visible word somewhere, and a VoiceOver action?
4. Do words read on every photo and in both looks (contrast, the plum-shade scrim)?
5. Does text grow with the person's text size, without clipping or overlap?
6. Is anything shown that the person did not need at that moment?
7. Does the copy say what it means in plain words?

Shoebox's own rules (CLAUDE.md), checked on the pictures:

- No black anywhere; shadows and scrims are the plum shade.
- Actions are words, never pills or icon-only buttons.
- Brick only on the Delete swipe.
- The lid: Sunflower, 44 pt, 12 pt in, canted 2 degrees on a left hinge, level once open.
- No em-dashes in any copy.
- One post at a time on Today; the panel clear of the box's glass.

## 6. Reviewed in the code (first pass, November 7)

| Area | Finding |
|---|---|
| Reduce Transparency | Handled on the box, the lid, the Shoebox search and Settings cards. Not on the post's word panel, the opened post's glass words, or the writing screens' panel. To check on a phone. |
| Reduce Motion | Handled on Today (rise, rattle) and the move demos. |
| VoiceOver | The post offers "Next one" and "Put away" as actions, and the box is one button with its count. Good. |
| Dynamic Type | 109 places set a fixed point size (`.font(.system(size:))`), which does not grow with the person's text size. The big-text run measures how much this matters. |
| Icons | One icon: the magnifying glass in search, beside its field. Allowed: it is not a button. |
| Em-dashes, black | None in copy or colors. |

## 7. People: five testers, five tasks

Send to five TestFlight testers who have not used Shoebox. No help, no onboarding video first. After each task, one
question: "How easy was that?" 1 (very hard) to 7 (very easy). At the end, the ten SUS questions.

1. Save this page so it comes back to you on Friday. (Share from Safari, Why "Friday")
2. You're done with the post on screen. Make it go away, but keep it.
3. You did that by mistake. Get it back.
4. Find the thing you put away yesterday.
5. Change it so Shoebox shows you three posts a day.

Record: finished or not, taps, time, and anything they say. Five people find most of the problems.

## 8. Results

Each run's report is on `ci-audit`. Findings go into `backlog.csv` with the prefix `UX-` and their severity.
See section 9 for the runs so far.

## 9. Runs

| Date | Commit | Result |
|---|---|---|
