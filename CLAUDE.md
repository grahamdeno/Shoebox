# Shoebox

Native iPhone app (SwiftUI). "Keep it. It comes back to you."

**Read `docs/PLAN.md` before any work.** It holds the product rules, the decisions made, the architecture and the build phases. `docs/SPEC.md` holds the detailed design and behavior, with the agreed screens in `docs/design/screens/`. Where PLAN.md and SPEC.md disagree, SPEC.md wins.

The old app lives in `grahamdeno/edition`, frozen and being archived. Read it for rules and edge cases; don't copy its structure. The website (inmyshoebox.com) lives in `web/`; see `web/README.md`.

## Working with Graham

- Graham picks the model per step: Opus for feel, data safety and judgment; Sonnet for building and shipping. At every handoff, name the model the next step needs.
- Don't merge or ship until Graham says "ship". One big release beats several small ones.
- Claude opens and merges pull requests itself. Work on a branch, never on `main`.
- Graham presses Submit for Review on App Store releases himself. Stop before it.
- Put crucial, irreversible steps (submit, publish, delete, deploy) first in any handoff and make them stand out.
- Write plainly and compactly. No em-dashes. No military metaphors in published or professional text.
- Do the checks you can do yourself (tests, builds, reading the result) instead of handing them back.

## Design rules (short form)

- Today: one full-screen post at a time, Scales' moves. Flick up = Next (back when the why says, or tomorrow). Pull down = Put away (done, archived, never deleted). Tap = open. Undo 5 s.
- A post is a full-bleed graded photo with its words on one Liquid Glass panel. No photo: Plum lit warm with Sunflower.
- The Shoebox is the library of everything not done; Put away posts sit behind one word (Put away (n)), with Just put away (the last 3 days) above the topics, and are found by search. Edit is a word on the opened post; it saves on its own and on Keep. Delete is the last word of Edit, soft, with Undo.
- Your Shoebox across the bottom: Plum glass (the lower 150 pt, clear of the post's panel) rising into the post from below (a lighter Plum `#6A4F73` in dark), under one Sunflower lid: 44 pt tall, 12 pt in from the edges, 8 pt corners, canted 2° on a left hinge, one smooth shape with no side flaps, casting a shadow down; level once the Shoebox is open. Never a band or a slider. It rattles (shake plus rustling haptic) on every flick up and drop in. The Shoebox and Settings open as glass sheets; the lid opens the Shoebox. SPEC 2.2, 2.4, 2.8.
- Photos are framed on their subject (faces, then saliency, on the phone) and shaded by how bright they are where the words sit. Posts without one get a stock picture chosen on the phone with Apple Intelligence first; only generic words leave the phone, never names, and health, money and legal posts are never looked up.
- Every save is read for the date it is about (event day and time, deadlines). Past events move to Kept on their own.
- Writing screens (Keep something, share, Edit) are the post you are making: its photo or Plum as the ground, Cancel and Keep as glass words at the top, one glass panel that rides the keyboard (words, Why, then Photo or file and the return line). Photo or file opens the standard Photo Library, Take Photo, Choose File menu. A photo is read on the phone and fills lighter suggestions you tap to make yours. SPEC 2.5.
- Colors: Pistachio `#F6F3E8` light ground; Plum `#3B2240` dark ground (the Scales plum); Bone `#F1E9D8` text on dark and words on photos; lighter Plum `#6A4F73` the dark-mode box; Plum Ink `#2A1E2E` text on light; Plum is also the light-mode box and accent; Sunflower `#F9C93A` the lid (lip `#D4A21E`), your reason on photos, dark accent. No black anywhere: shadows and scrims use the plum shade `#1A1020`. Brick `#A8402F` is the one red, for the Delete swipe only. No peach. Full table in `docs/SPEC.md` section 5.1. A second set, Stone (Scales' warm stone `#C9C6BD` and graphite `#23262B`, light and dark), is chosen in Settings › Look › Colors; Plum stays the default.
- Settings: laid out like Scales. Short groups under small quiet titles (Your day, Email, Back up, Help and about), cards one step off the ground, each row showing its answer, at most one quiet line under a group; a row opens one screen with a title and its choices as words. Backups say Automatic. How Shoebox works shows the moves as small looping pictures. Delete everything is a quiet word below; the logo and "Your posts stay on your phone." close the list.
- SF Pro throughout. Actions are words, never pills or icon-only buttons. No neumorphism.
- Iterate fast: batch changes, build once when Graham asks. Don't run screenshots or watch CI for every small change.
- Mac minutes are limited (private repo, GitHub Free, about 190 a month, then jobs stop). The Mac build runs once when a PR opens; add `[test]` to a commit message to rebuild. `[audit]` (60 to 90 min) and `[screens]` only before a release.
