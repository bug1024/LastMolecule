# Dark laboratory with scientific specimen art

The page layout, typography, backgrounds, panels, dialogs, map and HUD use commit `0cb89b52` as their baseline. The subsequent warm research-archive page treatment has been removed without rewriting Git history.

Retained art:

- `assets/art/specimens.png`: six scientific specimens in a 3 × 2 transparent atlas; receptor, cell, crystal, folded protein, membrane and molecular sculpture. Reworked in cool glass, silver, teal and blue for the original dark-lab theme. Live hit, death and enemy-specific tint feedback remain.
- `assets/art/research-illustrations.png`: six experiment illustrations, with cool light engraving suitable for dark cards. Live cards select their illustration by effects and preserve per-card crops.
- `assets/art/record.png`: the retained record-card silhouette and compartments with a dark navy face, silver border and teal cost seal; text and numbers remain live.
- `MoleculeView`: the original live scaffold and placement interactions, scientific shading, fragment colors and animation. `MoleculeArt` uses the retained molecular sculpture in title/hub artwork.

`UIKit` retains its original palette and controls. Only the art cache and atlas sampler have been added. Paper/wood desk backgrounds and antique pedestals are no longer used.

Generate screenshots with the desktop renderer:

```
Godot --path . --script tools/capture_ui.gd
```

The script writes to `.godot/lab-review/` by default; `-- --out=/absolute/path` selects another folder and `--english` captures English. It disables company, settings and run persistence before creating scenes. It captures actual UI, with synthetic review state for rewards/events/endings, without reading or overwriting player save files.

Regression checks: `sh tests/run.sh`.

## Card identity and artwork bounds

Title strips and outer edges communicate role: red attack, blue defense, green skill, gold power and grey status. A separately colored type label identifies molecular, experiment, clinical, AI and process cards; role icons and rarity marks provide an additional cue.

Illustrations render in a dedicated clipped child control. Mirroring uses a canvas transform with positive destination dimensions. Atlas source crops remain within their individual cell at hand, pick and detail scales. The live effects panel masks the baked card-frame divider so it cannot cross effect text.
