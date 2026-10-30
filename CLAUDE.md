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

- One full-screen feed, Today, one post per screen. Swipe up = back tomorrow. Only two words on a post: Later and Done. Box holds what's put away.
- Peach and slate: surface `#FFF8F3`, text `#1E2A3D`, slate `#33415C`, peach `#FFC4A3`; dark is slate `#36445E`, never black. Full table in `docs/PLAN.md` section 5.4.
- SF Pro throughout. Actions are words, never pills or icon-only buttons.
- One accent element per screen: Done.
