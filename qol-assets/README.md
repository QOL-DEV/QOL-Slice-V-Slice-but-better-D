# QOL Slice assets

Engine-specific assets for QOL Slice (kept outside the `assets` submodule so the base game's
assets stay untouched). Everything in here is copied into the game's `assets/` folder at build time:

- `qol-assets/images/...` -> `assets/images/qol/...`
- `qol-assets/data/...`   -> `assets/data/qol/...`

## Mod Menu tile icons

Put tile icons in `qol-assets/images/hub/<tool id>.png` (256x256, transparent).
Optionally add `<tool id>.xml` (Sparrow) with `idle` and `selected` animations.

Tool ids: modpack, chart, character, stage, noteskin, death, shader, modchart, menu, hud,
week, freeplay, dialogue, achievements, credits, guide, settings

The Animator has a featured banner instead of a tile. Optional custom art:
`qol-assets/images/hub/animator-banner.png` (1816x300).
