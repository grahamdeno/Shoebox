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
- The box top: a Nectarine `#FFBD76` lid with an Oceanic lip in the bottom-right corner, one word, Later. Tap it for the Later list; flick out of it to open the post. Opened posts get a full-width Nectarine strip with Later and Done.
- Four colors: Wheat `#FFF6E9` is the app background, Onyx `#0A171D` is text, Oceanic `#003F47` is the logo box and the dark ground (never black), Nectarine `#FFBD76` is the box top. Your own words get a pale Nectarine tint `#FFD7AA`. Full table in `docs/PLAN.md` section 5.4.
- SF Pro throughout. Actions are words, never pills or icon-only buttons.
