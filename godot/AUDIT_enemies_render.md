# AUDIT enemies.gd / world.gd / render.gd

Method: side-by-side with index.html (7404-7550, 7685-7731, 7978-8016, 8038-8111, 8721-8871, 9156-9494, 7178-7260, 5357-5400).

## Logic (enemies.gd, world.gd) - all constants/formulas/orders matched
- ENEMY_TYPES (defs.json) identical to original 13 entries; boss defs, spawn table weights/level gates/caps, spawn point
  rules, cap/batch/timer formulas, enemyShoot, bossSpecial, hazards, scaling: no divergence found.
- FIXED enemyAbilityTick (medic): `ally == e` on Dictionaries compares by value in Godot 4; changed to `is_same()` (reference
  semantics like JS `===`, and avoids deep compares).
- world.gd: generateWorld/updateFieldZones/updateCamera/runXpNeeded identical (Math.round vs roundf only differs for negatives).
- Not mine / noted: PERF caps in game.gd are the desktop values (original uses 760/540/150/190/135 when touchCapable).

## Render fixes
- friendly beam charge label: JS `if(h.slot)` is falsy for slot 0; port tested `!= null` (now `_truthy`).
- Dash patterns: original setLineDash([a,b]) ; draw_dashed_line uses equal gaps -> new `_dashed` ([4,12] beam, [8,7] hazard line,
  [7,7] charge windup, [3,8] aim line).
- Removed glow added by port on friendly beams/ready hazard lines (original shadowBlur=0 there).
- Player ship glow is kept even in heavy scenes (original shadowBlur 8 when heavy, 22 otherwise); text size `t.size||14`.
- Verified (no change): background, grid, border, zones, rings, enemy shapes/colours/rotations, elite ring, hp bars, drones,
  player, reticle, particles, texts, offscreen arrows, minimap, flash, vignette, hazards/loot/projectiles/info overlays.

## Perf (Render.draw, 190 enemies incl. boss + 500 bullets + 40 hazards, llvmpipe, GDScript command build time)
- before: ~17-18 ms, ~2140 canvas draw calls; after: ~10 ms, ~1350 draw calls.
- draw_circle 5us / draw_arc 3.6us / draw_colored_polygon 5us vs textured rect 0.2us / draw_primitive 0.2us:
  small discs+rings use cached textures (`_fcirc/_circ`), 3-4 pt polygons use draw_primitive, dashed circles/lines and bullet
  trails are single multiline commands, enemy bullets use stacked discs (stroke disc under fill disc).
- Remaining cost is mostly draw_string (labels) and GDScript per-entity loops.
