# How we got here

The design explorations from October 29 and 30, 2026, kept so the reasoning isn't lost. Open any page in a browser. The chosen direction is in `docs/design/storyboard.html` (Midnight Gold) and `docs/PLAN.md`.

## The UX audit of the old app (October 29)

A zero-based audit of the web app (`grahamdeno/edition`) found:

- **The one thing:** things you chose come back, with your reason on top, a few at a time, and the day ends. Everything else was noise around that.
- **Cut:** weather, sports scores, live cameras, location, Quote of the day, and the morning cards in the public app. They were removed in edition PRs #164 and #165.
- **Fewer decisions:** a new save joins the pool on its own (one stage, not two). "Why did you keep this?" is asked on the card instead of in a form. Later offers two choices plus a date.
- **What it couldn't fix:** the app still asked you to come back and work a list. That led to the rebuild.

## The design rounds

| Page | What it explored | Outcome |
|---|---|---|
| `six-directions.html` | Six ways the app could look and move: Stack, Daily Issue, Box, Ribbon, Page, Thread | The Daily Issue was the strongest. All six kept the "open the app and work a list" shape, which was the real problem. |
| `storyboard-ember.html` | The rethink: Shoebox comes to you. Ten moments across a day, on the Lock Screen, car, Watch and Siri, in the first (Ember) palette | Became the v1 scope. |
| `first-palettes.html` | Seven palettes on the same two moments | All were the same formula (light paper, dark ink, one accent). Plum and Peach was the favorite. |
| `../plum-and-peach.html` | Plum and Peach five ways (Sharpened, Dusk to dawn, Ripening, Two-ink print, Plum night) plus corner radius | 4 px corners chosen. Kept as the alternate palette (PLAN section 5a). |
| `faded-print.html` | A palette taken from how old photos fade in a shoebox | Considered. |
| `four-keepsake-palettes.html` | Carbon Copy, Developing, Cyanotype, Pressed Flower | Still too similar in structure. |
| `../palettes.html` | Eight palettes that differ in kind: light, dark, no color, one loud color, many soft colors, glass | **Midnight Gold chosen.** |
| `../storyboard.html` | The storyboard repainted in Midnight Gold with a Day twin | The reference for phase 1. |
