# INTEGRATION_LOG

Headless stress harness: `tests/sim_stress.tscn` (+ `tests/sim_stress.gd`).

    cd godot && NF_SCENARIO=enemies,bosses  godot --headless --path . res://tests/sim_stress.tscn
    NF_RENDER=1 ...   # also calls Render.draw each few steps (catches draw-side errors)
    scenarios: enemies bosses elites levelups modules gear cards drones actives dash death clear hardcore fracture custom marathon perf perf2

The harness drives `Game.update(1/60)` directly with a bot (Inp touch-stick state + `Inp.mouse.down`), auto-picks
level-up cards / ability rewards, checks NaN and PERF-cap growth, and prints coverage + max array sizes.
Waves are derived from `Game.time` (original behaviour), so the harness uses `set_wave(n)` (sets time) rather than `Game.wave = n`.

## Fixes
1. combat.gd `_update_projectiles_inner`: `b._dead` read on bullets without the key -> `b.get("_dead", false)`.
   (All other `_dead` reads in the code base already use `.get`; every writer sets `true` only.)
2. cards.gd `_load_defs`: gear modules from defs.json had no `apply` Callable, so `Meta.applyMetaBonuses` silently
   skipped every equipped gear module. Each module now gets `apply = func(p, lv): module_apply(id, p, lv)`.
   Verified all 34 modules (constants identical to index.html 6217-6252) change the player when equipped (scenario `gear`).
3. combat.gd `_update_projectiles_inner`: player-bullet vs enemy sweep was O(bullets x enemies) (50 ms/step at 190
   enemies + ~500 bullets). Now uses a 128px uniform grid of live enemies (same hit set, still sorted by t): 7.6 ms/step.

## Results (0 SCRIPT ERROR / ERROR outside scripts/ui; no NaN; arrays within PERF caps)
See final report; max array sizes observed: bullets 590, enemies 190, particles 260, gems <=40, texts <=46, rings <=48, hazards 48.

## Known / notes
- scripts/ui/* (owned by the UI agent) printed parse errors during development (meta_tab_gear.gd `eq` inference,
  screen_runconfig.gd) - not touched.
- `hard`/`hardcore`/`fracture` are one-hit difficulties: the harness's "invincible" hp refill cannot save the bot, so those
  scenarios legitimately end in `gameover`.
