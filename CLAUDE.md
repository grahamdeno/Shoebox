# Shoebox

Native iPhone app (SwiftUI). "Keep it. It comes back to you."

**Read `docs/PLAN.md` before any work.** It holds the product rules, the decisions made, the architecture and the build phases. `docs/SPEC.md` holds the detailed design and behavior, with the agreed screens in `docs/design/screens/`. Where PLAN.md and SPEC.md disagree, SPEC.md wins.

The old app lives in `grahamdeno/edition` and is frozen. Read it for rules and edge cases; don't copy its structure.

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
- A post is a full-bleed graded photo with its words on one Liquid Glass panel. No photo: Plum Night lit warm with Nectarine.
- The Shoebox is the library of everything not done; Put away posts sit behind one word (Put away (n)) and are found by search. Edit is a word on the opened post; it saves on its own and on Keep. Delete is the last word of Edit, soft, with Undo.
- Your Shoebox across the bottom: a Plum glass box (the same in both modes and in the logo) under a tall Nectarine lid that casts a shadow down onto it, like a shoebox top over the sides. It rattles (shake plus rustling haptic) on every flick up and drop in.
- Photos are framed on their subject (faces, then saliency, on the phone) and shaded by how bright they are where the words sit. Posts without one get a stock picture chosen on the phone with Apple Intelligence first; only generic words leave the phone, never names, and health, money and legal posts are never looked up.
- Every save is read for the date it is about (event day and time, deadlines). Past events move to Kept on their own.
- Writing screens (Keep something, share) are laid out like Scales: full screen on the ground, Cancel and Keep at the top, hairline fields. Nothing rides the keyboard.
- Colors: Wheat `#FFF6E9` light ground and text on dark; Plum Night `#2F2036` dark ground; Plum Ink `#2A1C30` text on light; Plum `#56395F` the box (app and logo) and light accent; Nectarine `#FFBD76` the lid, your reason, dark accent. No black anywhere: shadows and scrims use the plum shade `#1A1020`. Onyx and Oceanic are retired. Full table in `docs/SPEC.md` section 5.1.
- Settings: no paragraphs. One short list in a card one step off the ground, each row showing its answer; a row opens one screen with a title and its choices as words. Privacy and Delete everything are quiet words below.
- SF Pro throughout. Actions are words, never pills or icon-only buttons. No neumorphism.
- Iterate fast: batch changes, build once when Graham asks. Don't run screenshots or watch CI for every small change.
