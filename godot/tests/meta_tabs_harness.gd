extends Control
## Throwaway harness: NF_TAB=forge|library|gear NF_SHOT=/path.png [NF_ACT=modal|pick|many]
func _ready() -> void:
	theme = Kit.theme()
	var bg := ColorRect.new(); bg.color = Kit.BG; bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	Game.state = "meta"
	var M = Meta
	for id in M.PART_BY_ID: if randi() % 3 > 0 or id in M.STARTER_PARTS: M.meta.syntax[id] = 1
	for m in M.MODULES: if randi() % 2 == 0: M.meta.modules[m.id] = 1 + randi() % 5
	M.meta.equippedGear.core = M.MODULES[0].id; M.meta.modules[M.MODULES[0].id] = 3
	var many := OS.get_environment("NF_ACT") == "many"
	M.meta.cards = []
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var n := 40 if many else 7
	for i in n:
		var sel := {}
		for t in M.CARD_FIELDS:
			var ps: Array = M.unlockedParts(t)
			sel[t] = ps[rng.randi() % ps.size()].id
		var c = Cards.normalizeCard(sel)
		if M._find_duplicate_card(c) == null: M.meta.cards.append(c)
	M.meta.cards[0].name = "テスト改名カード"; M.meta.cards[1].favorite = true
	M.meta.equippedCards = [M.meta.cards[0].id, M.meta.cards[2].id]
	var id := OS.get_environment("NF_TAB")
	var scr: Script = load("res://scripts/ui/meta_tab_%s.gd" % id)
	var tab: Control = scr.new()
	tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := MarginContainer.new(); m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left","top","right","bottom"]: m.add_theme_constant_override("margin_"+s, 24)
	add_child(m); m.add_child(tab)
	tab.build(); tab.refresh()
	await get_tree().create_timer(0.5).timeout
	var act := OS.get_environment("NF_ACT")
	if act == "modal" and id == "library": tab.call("_open_modal", M.meta.cards[0].id)
	if act == "pick" and id == "forge": tab.call("_open_picker", "effect")
	if act == "select" and id == "library": tab.call("_select", M.meta.cards[1].id, true)
	if act == "dup" and id == "forge":
		for k in M.CARD_FIELDS: Cards.forgeSelection[k] = M.meta.cards[0][k]
		tab.call("_update_preview")
	if act == "logic":
		var lib := load("res://scripts/ui/meta_tab_library.gd").new()
		add_child(lib); lib.build(); lib.refresh()
		var c0: Dictionary = M.meta.cards[3]
		lib._do_equip(c0.id, Callable()); print("equipped ", M.meta.equippedCards.size(), " notice ", lib._notice._l.text)
		lib._do_equip(M.meta.cards[4].id, Callable()); print("full notice ", lib._notice._l.text)
		lib._do_delete(M.meta.cards[1].id, Callable()); print("fav del notice ", lib._notice._l.text)
		var forge := load("res://scripts/ui/meta_tab_forge.gd").new()
		add_child(forge); forge.build(); forge.refresh()
		forge._name_edit.text = "新カード"; Cards.forgeSelection.trigger = "on_hit"; Cards.forgeSelection.effect = "explode"; Cards.forgeSelection.power = "p120"; Cards.forgeSelection.chance = "c50"
		var before: int = M.meta.cards.size()
		forge._update_preview(); print("forge status ", forge._status._l.text)
		forge._on_create(); print("cards ", before, "->", M.meta.cards.size(), " ", forge._notice._l.text, " | btn ", forge._create_btn.text)
		var g := load("res://scripts/ui/meta_tab_gear.gd").new()
		add_child(g); g.build(); g.refresh(); g._toggle("rail", "レール"); print("gear ", M.meta.equippedGear, g._notice._l.text)
	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("NF_SHOT"))
	get_tree().quit()
