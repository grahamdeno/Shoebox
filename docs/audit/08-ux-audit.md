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
| J9 | Heavy and odd data | 500 more posts (`-dataset heavy`): launch, flick, the Shoebox, eight fast scrolls, search a 57-letter word, Japanese and Arabic, open the longest title |
| J9b | No pictures | `-dataset nophotos`: Today, opened, next, the Shoebox |
| J10 | Shoebox Plus | The store's offer after a week and the App Store unreachable; TestFlight's free address (Get address is never tapped: it would use the live relay) |
| J11 | Benchmark jobs | Six jobs from Today, counted in taps, with every app response timed (section 10) |

Not walked by the simulator: the share sheet from another app (the system's sheet cannot be driven reliably; its
screen is covered by the `share` still and by tester task 1), a real purchase and a real address (they need a signed
build and the live relay; testers in TestFlight get Plus free), and a notification arriving on the lock screen. What a
notification says and when is checked by unit tests (`NotifierTests`).

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

## 6a. What the simulator cannot settle

- **VoiceOver and the closed Shoebox.** XCUITest and Apple's audit still list the closed sheet's words on Today after
  they were hidden at three levels. Both read the testing tree, which SwiftUI keeps fuller than what VoiceOver reads, so
  this cannot be confirmed here. The contrast "failures" on Today's hidden Today and Settings words come from the same
  place and are not real. Check on a phone (section 7, first list).
- **Glass.** The audit's contrast check samples through Liquid Glass and flags words that read well (Stone dark Settings
  rows, Cancel on the writing screens). Checked by eye in the pictures; not changed.
- **Query timeouts.** Today and the Shoebox are large trees; some runs time out on a query mid-journey, worst at
  the largest text, where a query can outlast the 5 s Undo. Each journey ran
  to the end in at least one config; the pictures cover every step.

## 7. People: five testers, five tasks

**First, on Graham's phone (ten minutes, before the testers):**

1. VoiceOver on, Today: swipe through. Only the post, + New, the count and the box should be read, never the Shoebox
   list behind the box. Open the Shoebox: Today's post should not be read under it.
2. Settings › Accessibility › Display & Text Size › Reduce Transparency on: the post's panel, the writing panel and the
   opened post's words should be solid and readable.
3. Reduce Motion on: flick up and pull down; the next post should fade, not rise.
4. Larger Text at the largest accessibility size: Today, the Shoebox, Settings and Keep something new should read
   without words broken mid-word.

**Then the testers:**

Send to five TestFlight testers who have not used Shoebox. No help, no onboarding video first. After each task, one
question: "How easy was that?" 1 (very hard) to 7 (very easy). At the end, the ten SUS questions.

1. Save this page so it comes back to you on Friday. (Share from Safari, Why "Friday")
2. You're done with the post on screen. Make it go away, but keep it.
3. You did that by mistake. Get it back.
4. Find the thing you put away yesterday.
5. Change it so Shoebox shows you five posts a day. (Nov 8: the first message said three, which Each day does not offer: 5, 10 or All.)

Record: finished or not, taps, time, and anything they say. Five people find most of the problems.

## 8. Results

Each run's report is on `ci-audit`. Findings go into `backlog.csv` with the prefix `UX-` and their severity.
See section 9 for the runs so far.

## 9. Runs

| Date | Commit | Result |
|---|---|---|
| Nov 7 | 134f3e0 | Test build failed on one line (hasKeyboardFocus). No records. |
| Nov 7 | 7655339 | First full walk. Found UX-1 to UX-8 (backlog.csv): text never grew with Dynamic Type (122 issues), the closed Shoebox list in VoiceOver's reach on Today (it also made Today too slow for UI queries), unlabeled fields, Undo over the panel, a short tap area, quiet text near the contrast line. |
| Nov 7 | e933477 | Text grows (Dynamic Type issues down to the cap we chose, accessibility2). Large text broke words mid-word in Settings rows and choices, and the writing panel overflowed above the keyboard: fixed with ViewThatFits and a cap of xxxLarge on writing screens. The closed Shoebox list was still in VoiceOver's reach: hidden at the sheet, the list and Today's side. Unit tests pass. |
| Nov 7 | 89c9efe | Did not build (BoxView's pull is optional). |
| Nov 7 | 7c7a133 | All five configs and unit tests green, including the new rule that a dated post in the pile comes out before its day. Large text now stacks in Settings. Remaining: the Edit title field had no handle for the test (given one), small opacity raises on Today's count and the box count. |
| Nov 7 | 85924f9 | All configs and unit tests green. Every journey check holds except three that are the test's own: Settings closed by the walk's own swipe down (stone-dark), one slow Back word (big-text), and the return line read as a button ("Back Thursday" shows in every picture). Time replay: all 19 checks hold. Fixed in the journeys for the next run. |
| Nov 8 | 2a0e65b | First run with benchmarks, heavy data, no photos and Plus; its pictures are the first baseline. All five configs and unit tests (now with NotifierTests) green. Time replay: 19 of 19. Found: at the largest text the Shoebox title broke mid-word ("Shoebo / x"), fixed; the no-photos run fetched a stock picture, so stock is off there now; with the default daily limit (All) a heavy pile puts every post on Today ("2 of 286"), while SPEC says the default is 10 (Graham to decide). Test-side: J11 lost its record in every config to UI query timeouts on Today (records now save after every step; counter and box have handles); J4's Why tap landed on the word, so the Why line now focuses its field; Restore purchases was looked for on the wrong screen. Heavy-data responses passed on two configs and ran over on two (flick to Undo 1.8 to 2.3 s, one search 3.8 s): simulator noise until it repeats. |
| Nov 8 | 7a9234f | All configs and unit tests green; 44 journeys recorded (records now survive query timeouts). Benchmarks: all six jobs at their tap targets in every config; one response over (tap to opened 2.1 s, pro-light, once). The Shoebox title holds at the largest text; no-photos is plain Plum; J4 reads the Why; Restore purchases found. Picture comparison: 47 of 234 changed, the intended ones plus noise from shots taken mid-move, stock pictures fetched live, and the order of Go through your Shoebox. New: the Undo carried into the Shoebox covers its Settings word for 5 s (UX-12). The next run, with the daily limit at 10, becomes the baseline. |
| Nov 9 | 0cf77d9 | All configs and unit tests green; 49 journeys recorded; this run is the baseline. UX-8 (Undo names the day), UX-12 (Undo clear of the Shoebox's Settings: the new check holds in every config) and UX-13 hold. Benchmarks: every job at target in four configs. Big-text alone missed two Undo jobs: its UI queries take seconds (+ New took 8.9 s to find), so the 5 s Undo had gone before the walk looked for it; J2's Undo checks hold at the same size. Test-side, not the app. |

## 10. Benchmarks, picture comparison, edges (added November 8)

**Benchmarks.** J11 walks six jobs from Today and counts a person's taps and moves (typing is not counted). Every move's
response, from the move until the app has answered, is timed in J9, J10 and J11. Targets are in
`docs/audit/benchmarks.json`; the report's Benchmarks table marks anything over. Seconds for a whole job are the
simulator's and include its waits, so they are written down but not compared; a person's own time comes from testers.

| Job | Target taps |
|---|---|
| Open a post and close it | 2 |
| Next, then Undo | 2 |
| Put away, then Undo | 2 |
| Keep a note with a reason | 4 |
| Find what you put away | 2 |
| Change how many a day | 4 |

**Picture comparison.** Every run fixes the app's clock to November 7, 2026 (`-demoDate`), so the same step shows the
same dates every time. The report compares each picture with the baseline (branch `ci-audit-baseline`), matched by
config, journey and step name, and lists the ones where more than 1% of the picture changed, with before, now and what
changed side by side. A run whose commit says `[audit] [baseline]` becomes the new baseline; the first run is one on
its own. Approve a change on purpose by making a new baseline after looking at it.

**Edges.** J9 and J9b (section 2). The heavy set is 500 posts across a year with the layouts that break things: a
title that is a whole paragraph, one 57-letter German word, Spanish, Japanese, Arabic, Russian, emoji, a bare link, no
title at all.

**People.** `docs/audit/09-people-tests.md`: a five-second first-impression test of the welcome screen, and a two-week
diary with 2 or 3 testers, with every message ready to send.
