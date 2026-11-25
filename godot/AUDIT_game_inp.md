# Audit: game.gd / inp.gd vs index.html

Fixed (game.gd):
1. Session hooks (startRunSession, sessionAlreadySettled, markSessionSettled, clearRunSession) were sent through UI.hook, which has no handlers (screen_home states "owned by Game"), so runs never got a sessionId, were never marked settled, and the double-settle guard never fired. Now called directly (resetGame, gameOver, returnHome).
2. addXP: JS `(player.xpMultiplier||1)`; a 0 multiplier was used as 0. Now 0/NaN -> 1.
3. damagePlayer: `attack.kind||'normal'` with a null kind would type-error; now null/"" -> "normal".

Verified identical: playerBase constants, runXpNeeded, resetGame/resetRunSystems order, healPlayer, gainShield/Barrier, updateRunSystems, autoCardPriority, applyRunChoice, drainRunXp, dash, damagePlayer, update order/early returns, updateUI formats, fixed-step loop.
Inp: all stick math, hold-skill logic, key dispatch, escape, presentation verified; no divergences.

Uncertain / minor (not changed):
- JS playPreferences on corrupt JSON drops holdSkills (undefined); port keeps default true.
- F8 in tools state closes only if utilityTab==='developer' in JS; port closes for any tab (UI-owned tab state).
- Duplicate unused vars Game.bossPopulationTimer/finalBossEncounterStarted (real ones live in Enemies).
Test: tests/game_audit.tscn.
