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

## E2E (tests/e2e.gd, wired from main.gd via NF_E2E=<shotdir>)
Drives the REAL app with injected input (Input.parse_input_event mouse clicks at button rects, keys, ScreenTouch/Drag sticks).

    cd godot && NF_E2E=/tmp/e2e NF_FLOW=main [NF_COMPACT=1] XDG_DATA_HOME=/tmp/e2e_home NF_HOOKLOG=1 \
      xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . --resolution 1600x900
    flows: main (boot->config->play->levelup(Q/dock click)->pause tabs->suspend->resume->die->retry->die->meta tabs->settings->how),
           meta (home -> every meta tab), aspect (short tour for 16:10/4:3/21:9/phone), touch (stick/tap on phone landscape),
           extra (G drones, E ability panel, Q toggle, 1/2/3 picks, F8 from pause, pause confirm dialogs/restart)
Verified at 1600x900, 1440x900, 1200x900, 2100x900, 1000x560, 2400x1080 (NF_COMPACT=1): 0 FAIL, 0 SCRIPT ERROR, 0 unhandled hooks.
(Coordinates: events must be converted logical->window with get_window().get_final_transform() under canvas_items stretch.)

### E2E fixes
1. ui.gd: added hooks h_focusCombat (release GUI focus), h_focusPanel (focus screen default control), h_tryLandscapeLock (mobile orientation) - were unhandled.
2. screen_hud.gd: HUD fades out for every non-"playing" state (pause/upgrade/ability panel headers overlapped the HP/score plates).
3. screen_home.gd: removed duplicate "中断セーブを復元しました" toast (runsave already emits suspendMessage).
4. screen_settings.gd: opening settings from home left the home panel visible/focusable behind it; now hides home on open and re-shows on close (state menu).

### Open / notes
- Render draws the minimap + FLOW/CHARGE/LINK legend (world-space, fixed 16:9 camera) also under home/config panels; on non-16:9 it is not at the screen edge. Original did the same (cosmetic).
- Dock buttons are custom-drawn (no Label), so they are only reachable by position in tests.

## Real-device fixes (Android: HUD/pause/skills/dash invisible)
1. ROOT CAUSE game.gd step_frame: `_hook("syncInputPresentation")` (UI hook = HUD refresh only) instead of `Inp.syncInputPresentation()`
   (original loop() line 9502). `Inp.combatDockVisible`/`mobileControlsVisible` therefore only became true after a mouse press
   (focusCombat) - never on a touch-only device, so the dock (cards/skill/auto/pause/drone, 3 skill slots, DASH) and the sticks stayed hidden.
2. project.godot `pointing/emulate_mouse_from_touch=true` (was false): Slider/ScrollContainer-less custom controls ignore ScreenTouch; verified
   HSlider does not react to touch with false. Inp ignores emulated mouse (device==EMULATION). Kit.toggle/rarity card/DashBtn no longer also
   handle ScreenTouch (would double-fire with emulation).
3. Touch HUD buttons enlarged (dock row 72, skill slots 84, dash 96 wide); Inp.layoutTouchZones honours Kit.safe_margins().
4. Test hooks: NF_TOUCH=1 (force touch mode on desktop), NF_SAFE="l,t,r,b" (simulated cutout, window px). Flow:
   `NF_TOUCH=1 NF_COMPACT=1 NF_SAFE=100,0,100,40 NF_E2E=/tmp/p NF_FLOW=phone godot --path . --resolution 2400x1080`
