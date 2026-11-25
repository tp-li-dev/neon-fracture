# AUDIT combat.gd (vs index.html 7551-7806, 7896-8037, 8648-8720, 8945-9066)

Fixed:
1. Projectile sweep grid: `hits.sort_custom` is unstable while JS `Array.sort` is stable. Overlapping enemies give identical t (segmentCircleT returns 0 when the bullet starts inside), so hit order differed from enemies-array order. Now tie-broken by enemies-array index (`order` map built with the grid).
2. chainLightning: loop bound `Math.min(hops, enemies.length)` was evaluated once and `hops` truncated to int. Now float hops and bound re-evaluated per iteration like JS (matters for fractional chainTargets / enemies spawned mid-chain).

Verified equivalent (no change): castPattern constants, activeCharge, dischargeFriendly beam weight/branches, friendly well/orbit timings, gear/loadout effects and cooldowns, ACTIVE_DEFS, activePower/Cooldown, useActive, assign/queueAbilityReward, drones, homing/bounce/pierce, shoot (`||` vs `??` defaults), firePlayer, hitEnemy (Math.round vs roundi only differs for negatives, n/a), explode, dropGem/collectGem merge logic, killEnemy ordering and RNG consumption order, combo.
Grid: bbox of old->new position padded by b.r+maxR covers fast bullets; enemies never move/appear (spawnDelay>0 excluded) during the projectile step, so build-time cells stay valid.

Uncertain: enemy ids must be unique ints (dict keys 5 vs 5.0 differ); none seen. `addFriendly` slot<->effect reference cycle is erased on death (benign). dealEnemyDamage returns 0.0 for rejected hits (JS returns undefined -> NaN lifesteal); GDScript behaviour is saner and not reachable in practice.

Tests: tests/combat_audit.tscn (explosion falloff, chain counts/falloff, arc ranges, crit/drone crit, execute, pierce decay, tie order, grid-vs-brute-force on fast bullets).
