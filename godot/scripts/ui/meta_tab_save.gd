extends Control
## Meta tab: save export / import (原作 6599-6770). File dialog (desktop) + clipboard / paste-JSON fallback (mobile).

const TAB_ID := "save"
const TAB_LABEL := "セーブ"
const TAB_ORDER := 80
const DEFAULT_MSG := "ExportしたJSONは別PC・EXE版への移行にも使える形式です。"

var _root: HBoxContainer
var _msg: RichTextLabel
var _paste: TextEdit
var _preview_panel: Control
var _prev_name: Label
var _prev_high: Label
var _prev_wave: Label
var _prev_cr: Label
var _prev_assets: Label
var _apply: Kit.NeonButton
var _dlg: FileDialog
var _dlg_mode := ""

func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var comp := Kit.is_compact()
	_root = Kit.hbox(Kit.S3)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# ---------------- left: actions
	var lp := Kit.panel(Kit.EMERALD, Kit.S4)
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(lp)
	var b := lp.body
	b.add_theme_constant_override("separation", Kit.S2)
	var hr := Kit.hbox(Kit.S2)
	var ht := Kit.vbox(0)
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ht.add_child(Kit.label("SAVE DATA", Kit.FS_XS, Kit.with_a(Kit.EMERALD, 0.9), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	ht.add_child(Kit.label("セーブの移行・バックアップ", Kit.FS_LG, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true))
	hr.add_child(ht)
	hr.add_child(Kit.label("JSON / v%d" % Meta.SAVE_EXPORT_VERSION, Kit.FS_XS, Kit.MUTE, HORIZONTAL_ALIGNMENT_RIGHT))
	b.add_child(hr)
	b.add_child(Kit.label("ハイスコア、最高ウェーブ、CR、恒久強化、モジュール、解析済み構文、自作カード、装備状態を1ファイルに保存できます。", Kit.FS_SM, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var br := Kit.hbox(Kit.S3)
	var ex := Kit.button("セーブをExport", "success", _export_file)
	var im := Kit.button("セーブをImport", "primary", _import_file)
	for x in [ex, im]:
		x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		x.custom_minimum_size.y = 64 if comp else 56
		br.add_child(x)
	b.add_child(br)

	var mb := PanelContainer.new()
	var sb := Kit.box(Color(0.01, 0.03, 0.07, 0.55), Color(1, 1, 1, 0.07), 1, 8)
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	mb.add_theme_stylebox_override("panel", sb)
	_msg = RichTextLabel.new()
	_msg.bbcode_enabled = true
	_msg.fit_content = true
	_msg.scroll_active = false
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.add_theme_font_size_override("normal_font_size", Kit.fs(Kit.FS_SM))
	_msg.add_theme_font_size_override("bold_font_size", Kit.fs(Kit.FS_SM))
	_msg.add_theme_color_override("default_color", Kit.DIM)
	_msg.text = DEFAULT_MSG
	mb.add_child(_msg)
	b.add_child(mb)

	# clipboard / paste fallback
	b.add_child(Kit.hsep())
	b.add_child(Kit.label("クリップボード / テキストで移行（スマホ・ファイル選択が使えない環境向け）", Kit.FS_SM, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true, true))
	var cr := Kit.hbox(Kit.S2)
	var cp := Kit.button("JSONをコピー", "ghost", _copy_json)
	var pa := Kit.button("クリップボードから貼り付け", "ghost", _paste_clip)
	for x in [cp, pa]:
		x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cr.add_child(x)
	b.add_child(cr)
	_paste = TextEdit.new()
	_paste.placeholder_text = "ここにセーブJSONを貼り付け"
	_paste.custom_minimum_size.y = 70 if comp else 110
	_paste.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_paste.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_paste.add_theme_font_size_override("font_size", Kit.fs(Kit.FS_XS))
	b.add_child(_paste)
	var rd := Kit.button("貼り付けたJSONを読み込む", "primary", _read_pasted)
	b.add_child(rd)

	# ---------------- right: import preview
	var rp := Kit.panel(Kit.CYAN, Kit.S4)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(rp)
	_preview_panel = rp
	var pb := rp.body
	pb.add_theme_constant_override("separation", Kit.S2)
	var ph := Kit.hbox(Kit.S2)
	var pt := Kit.vbox(0)
	pt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pt.add_child(Kit.label("IMPORT PREVIEW", Kit.FS_XS, Kit.with_a(Kit.CYAN, 0.85), HORIZONTAL_ALIGNMENT_LEFT, false, true))
	_prev_name = Kit.label("セーブデータ", Kit.FS_MD, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, false, true)
	_prev_name.clip_text = true
	pt.add_child(_prev_name)
	ph.add_child(pt)
	ph.add_child(Kit.button("取消", "ghost", _cancel_preview))
	pb.add_child(ph)
	var gr := GridContainer.new()
	gr.columns = 2
	gr.add_theme_constant_override("h_separation", Kit.S2)
	gr.add_theme_constant_override("v_separation", Kit.S2)
	_prev_high = _stat(gr, "ハイスコア", Kit.TEXT)
	_prev_wave = _stat(gr, "最高Wave", Kit.TEXT)
	_prev_cr = _stat(gr, "クレジット", Kit.AMBER)
	_prev_assets = _stat(gr, "資産", Kit.VIOLET)
	pb.add_child(gr)
	var warn := PanelContainer.new()
	var wsb := Kit.box(Color(0.5, 0.1, 0.15, 0.12), Kit.with_a(Kit.ROSE, 0.3), 1, 8)
	wsb.content_margin_left = 12; wsb.content_margin_right = 12; wsb.content_margin_top = 8; wsb.content_margin_bottom = 8
	warn.add_theme_stylebox_override("panel", wsb)
	warn.add_child(Kit.label("Importすると現在のセーブを置き換えます。必要なら先にExportしてください。", Kit.FS_SM, Color("#fecdd3"), HORIZONTAL_ALIGNMENT_LEFT, true))
	pb.add_child(warn)
	pb.add_child(Kit.fill_spacer())
	_apply = Kit.button("このセーブに置き換える", "cta", _confirm_apply)
	_apply.custom_minimum_size.y = 60 if comp else 52
	pb.add_child(_apply)

	_dlg = FileDialog.new()
	_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_dlg.use_native_dialog = true
	_dlg.title = "セーブファイル"
	_dlg.size = Vector2i(900, 600)
	_dlg.file_selected.connect(_on_file)
	_dlg.canceled.connect(func(): _dlg_mode = "")
	add_child(_dlg)

func _stat(parent: Control, label: String, col: Color) -> Label:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := Kit.box(Color(0.01, 0.03, 0.07, 0.55), Color(1, 1, 1, 0.07), 1, 8)
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	var v := Kit.vbox(2)
	v.add_child(Kit.label(label, Kit.FS_XS, Kit.MUTE))
	var val := Kit.label("0", Kit.FS_MD, col, HORIZONTAL_ALIGNMENT_LEFT, true, true)
	v.add_child(val)
	pc.add_child(v)
	parent.add_child(pc)
	return val

# ---------------------------------------------------------------- messages
func _say(kind: String, head: String, rest: String = "") -> void:
	var col: String = {"ok": "#a7f3d0", "info": "#a5f3fc", "err": "#fecdd3"}.get(kind, "#cbd5e1")
	_msg.text = "[color=%s][b]%s[/b][/color] %s" % [col, head, rest]

func _stamp() -> String:
	return Time.get_datetime_string_from_system(false).replace(":", "-").replace("T", "T")

# ---------------------------------------------------------------- export
func _default_dir() -> String:
	var d := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if d == "" or not DirAccess.dir_exists_absolute(d): d = OS.get_user_data_dir()
	return d

func _export_file() -> void:
	var fname := "neon-fracture-save-%s.json" % _stamp()
	if OS.has_feature("mobile") or OS.has_feature("web"):
		# No reliable file dialog: save into the app data dir and copy to clipboard.
		var path := "user://" + fname
		var err: int = Meta.export_to_file(path)
		if err == OK:
			DisplayServer.clipboard_set(Meta.export_to_string())
			_say("ok", "Export完了。", "JSONをクリップボードへコピーし、%s にも保存しました。" % ProjectSettings.globalize_path(path))
		else:
			_say("err", "Exportに失敗しました:", error_string(err))
		return
	_dlg_mode = "export"
	_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_dlg.title = "セーブをExport"
	_dlg.filters = PackedStringArray(["*.json ; JSON"])
	_dlg.current_dir = _default_dir()
	_dlg.current_file = fname
	_dlg.popup_centered()

func _copy_json() -> void:
	DisplayServer.clipboard_set(Meta.export_to_string())
	_say("ok", "コピー完了。", "セーブJSONをクリップボードへコピーしました。安全な場所へ貼り付けて保管してください。")
	UI.toast("セーブJSONをコピーしました", "ok")

# ---------------------------------------------------------------- import
func _import_file() -> void:
	_dlg_mode = "import"
	_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dlg.title = "セーブをImport"
	_dlg.filters = PackedStringArray(["*.json ; JSON", "* ; すべてのファイル"])
	_dlg.current_dir = _default_dir()
	_dlg.popup_centered()

func _on_file(path: String) -> void:
	if _dlg_mode == "export":
		var err: int = Meta.export_to_file(path)
		if err == OK: _say("ok", "Export完了。", "JSONファイルを安全な場所へ保存してください。\n[color=#64748b]%s[/color]" % path)
		else: _say("err", "Exportに失敗しました:", error_string(err))
	elif _dlg_mode == "import":
		var r: Dictionary = Meta.read_import_file(path)
		_after_read(r, path.get_file())
	_dlg_mode = ""

func _read_pasted() -> void:
	_read_text(_paste.text)

func _paste_clip() -> void:
	_paste.text = DisplayServer.clipboard_get()
	_read_text(_paste.text)

func _read_text(text: String) -> void:
	Meta.pendingImportedSave = null
	var t := text.strip_edges()
	if t == "":
		_say("err", "Importできません。", "JSONが空です。")
		return
	if t.length() > 8000000:
		_say("err", "Importできません。", "セーブファイルが大きすぎます。8MB以下のJSONを選択してください。")
		return
	var payload = JSON.parse_string(t)
	if payload == null:
		_after_read({"error": "JSON形式が不正です。"}, "")
		return
	var parsed: Dictionary = Meta.validateImportPayload(payload)
	if not parsed.has("error"): Meta.pendingImportedSave = parsed
	_after_read(parsed, "貼り付けJSON")

func _after_read(r: Dictionary, fname: String) -> void:
	if r.has("error"):
		Meta.pendingImportedSave = null
		_preview_panel.modulate.a = 0.35
		_apply.disabled = true
		_say("err", "Importできません。", str(r.error))
		return
	_show_preview(r, fname)

func _show_preview(p: Dictionary, fname: String) -> void:
	_prev_name.text = "%s / %s" % [fname if fname != "" else "save.json", p.gameVersion]
	_prev_high.text = Kit.num(p.high)
	_prev_wave.text = Kit.num(p.wave)
	_prev_cr.text = "%s CR / %s DATA" % [Kit.num(p.meta.credits), Kit.num(p.meta.get("data", 0))]
	var sc := 0
	for v in p.meta.syntax.values(): if Meta._truthy(v): sc += 1
	_prev_assets.text = "構文 %d / カード %d" % [sc, (p.meta.cards as Array).size()]
	_preview_panel.modulate.a = 1.0
	_apply.disabled = false
	_say("info", "Import候補を読み込みました。", "内容を確認してから適用してください。")

func _cancel_preview() -> void:
	Meta.pendingImportedSave = null
	_clear_preview()
	_say("", "", DEFAULT_MSG)

func _clear_preview() -> void:
	_prev_name.text = "セーブデータ"
	for l in [_prev_high, _prev_wave]: l.text = "—"
	_prev_cr.text = "—"
	_prev_assets.text = "—"
	_preview_panel.modulate.a = 0.35
	_apply.disabled = true

func _confirm_apply() -> void:
	if Meta.pendingImportedSave == null: return
	Kit.confirm("セーブを置き換え", "現在のセーブ（ハイスコア・CR・研究・カードなど）を、読み込んだデータで置き換えます。よろしいですか？",
		_do_apply, Callable(), "置き換える", "キャンセル", true)

func _do_apply() -> void:
	if Meta.applyImportedSave():
		_clear_preview()
		_paste.text = ""
		_say("ok", "Import完了。", "セーブデータを置き換えました。")
		UI.toast("セーブをImportしました", "ok")

# ---------------------------------------------------------------- shell API
func refresh() -> void:
	if _root == null: return
	if Meta.pendingImportedSave == null: _clear_preview()
