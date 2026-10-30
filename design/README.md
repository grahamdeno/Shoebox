# Design tokens

`tokens.json` is the single source of every design value in Shoebox: colors in four themes, the type scale, spacing, corners, shadows and sizes. The published Design System artifact ("Shoebox") is built from this same file, with component guidelines and live previews.

## Themes

In order: Plum and Peach Day, Plum and Peach Night (the primary), Midnight Gold Night, Midnight Gold Day (the alternate). The phone follows the system's light or dark setting within the chosen palette.

## Colors are roles

Use the role, never the hex: `surface`, `surface-raised`, `deep`, `text`, `quiet`, `act`, `on-act`, `act-edge`, `act-text`, `mark`, `done`, `line`, `control-line`, `edge`, `fill-soft`, `focus`. Each token's `usage` says where it goes. `act` is the one thing to tap on a screen.

## Checks

`python3 check_contrast.py` checks every text role against `surface` and `surface-raised`, plus outlines and focus, in every theme. It exits 1 if any pair misses its floor (4.5:1 for text, 3:1 for outlines). Run it after any color change.

## Swift, and later clients

Phase 2 generates Swift from this file (colors as asset-catalog colors with light and dark appearances per palette, type styles scaled with Dynamic Type, spacing and corners as constants). A web or Android client reads the same file.
