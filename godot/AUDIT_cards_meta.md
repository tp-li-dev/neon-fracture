# Fidelity audit: cards.gd / meta.gd / audio.gd

Method: line-by-line read against index.html (cards 6216-6500 & 8324-8640, meta 6112-7177, audio 5449-5680) plus
node-generated parity data (original JS evaluated in node) compared headless in Godot:
- defs.json vs original (DIFFICULTIES, META_STATS, MODULES id/rarity/icon/name, MODULE_SLOT, CARD_PARTS, STARTER_PARTS, ACHIEVEMENTS): identical.
- 34 module descs x lv1-5, 10 research descs/values x 9 levels (incl. 2^53-1), 3035 sampled card recipes (cost, rarity, describeCard,
  generatedCardName, cardCooldown, recipeIssue), customChallenge/cleanCustomConfig for 5 raw configs: all identical.
- Save: node-built realistic export (40 cards, huge research/credits, growthLimits, odd types) -> Meta.read_import_file ->
  deep-equal with the original sanitizeImportedMeta output; export->import roundtrip; loadMeta vs original loadMeta pipeline.
- Audio: all 24 sound specs identical; playTone limiter/steal/rate logic matches.
- Japanese strings in the ranges are verbatim (only DOM/UI strings are absent, owned by UI).

## Divergences fixed (meta.gd)
1. `MAX_SAFE` was a float literal `9007199254740991.0`; GDScript parses it lossy to ...990, so researchLevel/credits/stats at the
   cap were off by one after import. Now `float(9007199254740991)`.
2. `_growth_choice`: `int(floorf(1e30))` overflowed to 0 (JS clamps to the owned max). Now clamps in float first.
3. `researchNumber`: Intl rounds half-expand on the shortest decimal; printf rounded the binary value (1.005 -> 1.00). Added a nudge, and
   shortest-round-trip zero padding for |n| >= 1e15 (JS prints 45,035,996,273,704,950 where %f printed ...952).
4. `cleanCustomConfig`: explicit JSON `null` numerics are `Number(null)=0` then clamped in JS (not the fallback). Fixed.
5. `scoreRewardProfile`: `Math.floor(Math.log2(cp))` emulated with log/log(2) could land one ULP under an integer; added 1e-12 guard.
6. tests/meta_test.gd: made independent of persisted profile state and of gacha duplicate refunds (it was flaky/order dependent).

## Verified equal / notes (no change)
- Gacha rates, weights, pity (>=24 forces EPIC, reset on >=EPIC), 10-pull guarantee, duplicate refunds, rarityRoll, runRarityRoll, loot guarantees.
- XP maths, earnedCredit/DataAmount, applyMetaBonuses ordering, achievements & rewards, updateRunRecords.
- Card triggers (every effect), conditionPass, cooldown, proc depth, normalizeCard falsy-id/name handling, run upgrade system
  (skills x3 tiers, uniques, legendaries, endless, rarity rolls, buildSkillChoice, chooseUpgradeSet ordering/probabilities).

## Uncertain / accepted differences
- Godot JSON.stringify prints floats with ~15-17 digits and non-integral floats lose last-digit precision (e.g. 0.1+0.2 -> 0.3,
  floats >= 2^53). Integer-valued saves (credits, levels) are exact because they are stored as ints. Affects only records floats.
- loadMeta keeps `credits/pity/totalRuns/modules` raw in JS (no sanitization); Godot normalizes to ints (fractional module levels, e.g. 5.7, become 5).
- searchKey lacks NFKC normalization (no engine API); whitespace collapse covers space/tab only.
- Card name truncation `slice(0,64)` is UTF-16 units in JS, code points in Godot (differs only for astral chars).
- Audio: DynamicsCompressor / analyser / AudioContext state machine intentionally not ported (documented in audio.gd).
- Headless user:// profile is shared by tests; stale nf_run_config/nf_meta_v1 can break meta_test on a dirty profile (cleaned).
