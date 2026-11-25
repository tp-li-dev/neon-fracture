extends SceneTree
var fails := 0
func ok(c: bool, m: String) -> void:
	if not c:
		fails += 1
		print("FAIL: ", m)
	else: print("ok: ", m)
func _initialize() -> void:
	await process_frame
	var M = root.get_node("Meta")
	M.storage_remove("nf_meta_v1")
	ok(M.meta.credits == 0 and M.meta.playerLevel == 1, "default meta")
	ok(M.statCost("power", 0) == 90.0 and M.statCost("power", 3) == 180.0, "cost power")
	M.meta.credits = 1000
	var q = M.researchQuote("power", 3)
	ok(q.cost == 90 + 120 + 150 and q.valid, "quote 3 = 360")
	ok(M.affordableResearchCount("power") == 6, "affordable " + str(M.affordableResearchCount("power")))
	ok(M.research_desc("power", 4) == "本体弾ダメージ +20%", M.research_desc("power", 4))
	ok(M.researchNumber(1234.5) == "1,234.5", "number fmt")
	ok(absf(M.mobilityPercent(40) - (24.0 + 8.0 * log(2.0))) < 1e-9, "mobility")
	var c = M.challenge()
	ok(c.cp == 1.0 and M.challengeReward() == 1.0, "easy challenge")
	M.runConfig.difficulty = "custom"
	ok(M.challenge().cp > 0.45, "custom cp %f" % M.challenge().cp)
	M.runConfig.difficulty = "easy"
	ok(M.awardPlayerXp(10000) > 0, "xp award")
	M.meta.stats.power = 7; M.meta.modules["pulse"] = 3; M.meta.syntax["on_crit"] = 1
	M.meta.achievements["first_run"] = 123
	var s: String = M.export_to_string()
	var path := "user://nf_test_export.json"
	ok(M.export_to_file(path) == OK, "export file")
	var before = JSON.stringify(M.meta)
	M.meta = M.defaultMeta()
	var parsed = M.read_import_file(path)
	ok(not parsed.has("error"), "import parse " + str(parsed.get("error")))
	ok(M.applyImportedSave(), "apply")
	ok(M.meta.stats.power == 7 and M.meta.modules.pulse == 3 and M.meta.syntax.has("on_crit") and M.meta.playerLevel == parsed.meta.playerLevel, "roundtrip values")
	ok(M.meta.achievements.first_run == 123, "ach kept")
	var bad = M.read_import_file("user://nonexistent.json")
	ok(bad.has("error"), "missing file error")
	ok(M.validateImportPayload({"app": "x"}).has("error"), "bad app")
	M.saveMeta()
	var re = M.loadMeta()
	ok(re.stats.power == 7 and re.playerLevel == M.meta.playerLevel, "load after save")
	var res = M.grantSyntaxPart()
	ok(res.kind == "syntax", "gacha syntax")
	M.meta.data = 1000
	M.selectedGachaType = "syntax"
	var gr = M.doGacha(10)
	ok(gr.ok and gr.results.size() == 10 and M.meta.data == 1000 - 9 * 90, "gacha 10")
	print("DONE fails=", fails)
	quit(1 if fails else 0)
