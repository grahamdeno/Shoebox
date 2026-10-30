# Shoebox

Native iPhone app (SwiftUI). "Keep it. It comes back to you."

**Read `docs/PLAN.md` before any work.** It holds the product rules, the decisions made, the architecture and the build phases. `docs/SPEC.md` (written in phase 0) holds the detailed behavior. `docs/design/storyboard.html` shows the target experience in the Midnight Gold palette.

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

- Midnight Gold: navy `#0F1630`, cream `#F3EAD7`, gold `#D8B45A`. Day twin in `docs/PLAN.md` section 5.
- Your reason is the largest text, in DM Serif Display. Labels in Archivo.
- One gold element per screen: the thing to tap.
- Corners 4 to 6 px. Thin outlines. No pill buttons.
