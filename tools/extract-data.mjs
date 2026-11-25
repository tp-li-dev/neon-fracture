// Extracts pure data tables from ../index.html into godot/data/*.json so the Godot port uses the exact same numbers.
import { readFileSync, writeFileSync } from "node:fs";
const lines = readFileSync(new URL("../index.html", import.meta.url), "utf8").split("\n");
const L = (a, b) => lines.slice(a - 1, b).join("\n");
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const researchNumber = (n) => String(n);
const mobilityPercent = () => 0, recoveryPercent = () => 0;
const src = [L(6114, 6120), L(6122, 6123), L(6202, 6213), L(6216, 6254), L(6256, 6262),
  L(6267, 6331), L(6332, 6349), L(6870, 6885), L(7425, 7439)].join("\n");
const fn = new Function("clamp", "researchNumber", "mobilityPercent", "recoveryPercent", "meta",
  src + "\nreturn {DIFFICULTIES,CUSTOM_ENEMY_IDS,CUSTOM_BOSS_IDS,META_STATS,MODULES,MODULE_SLOT,CARD_PARTS,STARTER_PARTS,ACHIEVEMENTS,ENEMY_TYPES};");
const r = fn(clamp, researchNumber, mobilityPercent, recoveryPercent, {});
const strip = (o) => JSON.parse(JSON.stringify(o, (k, v) => (typeof v === "function" ? undefined : v)));
const out = {
  difficulties: r.DIFFICULTIES, custom_enemy_ids: r.CUSTOM_ENEMY_IDS, custom_boss_ids: r.CUSTOM_BOSS_IDS,
  meta_stats: strip(r.META_STATS), modules: strip(r.MODULES), module_slot: r.MODULE_SLOT,
  card_parts: r.CARD_PARTS, starter_parts: r.STARTER_PARTS, achievements: strip(r.ACHIEVEMENTS), enemy_types: r.ENEMY_TYPES,
};
writeFileSync(new URL("../godot/data/defs.json", import.meta.url), JSON.stringify(out, null, 1));
console.log(Object.entries(out).map(([k, v]) => `${k}:${Array.isArray(v) ? v.length : Object.keys(v).length}`).join(" "));
