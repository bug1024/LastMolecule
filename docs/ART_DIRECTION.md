# Research archive art direction

The visual reference is the approved warm archival battle concept: ivory research paper, walnut desktop, oxidized teal instruments, brass edges, ink diagrams, and physical molecular specimens.

## Owners

- `assets/theme/main_theme.tres`: Chinese serif display headings with sans-serif body/data; project-wide controls and text.
- `scripts/ui/ui_kit.gd`: shared palette, cached art, textured folios, primary actions, atlas sampling.
- `assets/art/`: generated original environment layers, transparent scientific specimen atlas, experiment illustration atlas, blank card and specimen pedestal. Text, numeric values, controls, intents, card effects and placement sites remain live Godot UI.
- `MoleculeView`: live molecular placement and feedback; the shared core illustration and drawn fragment miniatures are stylized representations, not chemistry-accurate molecular models.

## Palette

Paper `#EADBC0`, light paper `#F4E9D3`, ink `#302D27`, oxidized teal `#245951`, brass `#95713D`, alert vermilion `#A34235`.

Use ink on paper. Use ivory text on solid teal actions and dark instrument plates. Preserve semantic borders for selection and risk. Decorative lettering must not substitute for actual gameplay state.

## Assets

- `archive-desk.png`: shared paper and desk environment; paper grain is sampled from its central blank area.
- `battle-desk.png`: parchment battle field with a separate walnut hand area.
- `pedestal.png`: transparent brass/teal scientific instrument base.
- `specimens.png`: 3 × 2 transparent atlas: receptor, cell, crystal, folded protein, membrane, molecular core.
- `research-illustrations.png`: 3 × 2 transparent atlas: binding, protection, structure, assay, formulation, inference.
- `record.png`: transparent blank experiment record frame, with no baked text or numbers.

These layers were generated with the built-in image-generation tool for this project. Runtime state is not baked into screenshots.

## Visual verification

Run `Godot --path . --script tools/capture_ui.gd -- --out=/absolute/output/folder` with the desktop renderer. The capture script uses disabled save paths and exercises the actual title, project selection, archive, credits, molecule editor, hub, map, battle, deck, event, reward, settings, help, pause and ending surfaces. It never reads or overwrites player save files. `--english` also captures the English translation.

Run `sh tests/run.sh` for the gameplay/UI regression checks; the wrapper treats GDScript runtime errors as failures.
