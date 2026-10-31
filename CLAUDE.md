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

- One full-screen feed, Today, one post per screen. Swipe up = gone until tomorrow (no quiet rule). Box holds what's put away.
- The bar: a full-width Nectarine `#FFBD76` bar across the bottom, words on each end. Today: Later and Open. Opened post: Later and Done. Sheets and first run use it too. Later raises the Later list from the bar. No box-top lid on screen.
- Four colors: Wheat `#FFF6E9` is the light background, Onyx `#0A171D` is the dark background and the light text, Oceanic `#003F47` is the logo box, Nectarine is the bar. Your own words get a pale Nectarine tint `#FFD7AA`. Full table in `docs/SPEC.md` section 5.1.
- Depth is neumorphic: the post is a raised card in the ground color, photos and fields are pressed in. Outer radius = inner radius + padding.
- The opened post is a full-screen photo with the words on Liquid Glass panels.
- SF Pro throughout. Actions are words, never pills or icon-only buttons.
