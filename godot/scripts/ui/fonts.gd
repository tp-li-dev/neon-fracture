class_name NFFonts
extends RefCounted
## Shared font builder. Primary: bundled Noto Sans JP subset (res://fonts, OFL).
## Fallbacks: bundled symbol subsets, then SystemFont (desktop only), then ThemeDB fallback.
## Android has no usable named system CJK fonts, so the bundled font is what makes Japanese render.

const NAMES := ["Noto Sans CJK JP", "Noto Sans JP", "Hiragino Sans", "Yu Gothic UI", "Meiryo", "WenQuanYi Zen Hei", "sans-serif"]
const DIR := "res://fonts/"
const SYMBOLS := ["NotoSansSymbols2.subset.ttf", "NotoSansMath.subset.ttf", "NotoSansSymbols.subset.ttf", "NotoSans-Greek.subset.ttf"]

static var _regular: Font
static var _bold: Font

static func _file(fname: String) -> FontFile:
	var f: FontFile = null
	if ResourceLoader.exists(DIR + fname):
		f = load(DIR + fname) as FontFile
	if f == null and FileAccess.file_exists(DIR + fname):
		f = FontFile.new()
		f.load_dynamic_font(DIR + fname)
	if f == null:
		return null
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.generate_mipmaps = false
	f.multichannel_signed_distance_field = false
	return f

static func _tail() -> Array[Font]:
	var out: Array[Font] = []
	for s in SYMBOLS:
		var f := _file(s)
		if f != null: out.append(f)
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(NAMES)
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.hinting = TextServer.HINTING_NONE
	out.append(sf)
	if ThemeDB.fallback_font != null:
		out.append(ThemeDB.fallback_font)
	return out

static func _build() -> void:
	var tail := _tail()
	var reg := _file("NotoSansJP-Regular.subset.ttf")
	if reg == null:  # bundled font missing: system font only
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(NAMES)
		sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		var sb := SystemFont.new()
		sb.font_names = PackedStringArray(NAMES)
		sb.font_weight = 700
		sb.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_regular = sf
		_bold = sb
		return
	reg.fallbacks = tail
	# Faux-bold of the regular face for glyphs absent from the (smaller) bold subset.
	var fake := FontVariation.new()
	fake.base_font = reg
	fake.variation_embolden = 0.5
	var bold := _file("NotoSansJP-Bold.subset.ttf")
	if bold != null:
		var bt: Array[Font] = [fake]
		bt.append_array(tail)
		bold.fallbacks = bt
		_bold = bold
	else:
		_bold = fake
	_regular = reg

static func regular() -> Font:
	if _regular == null: _build()
	return _regular

static func bold() -> Font:
	if _bold == null: _build()
	return _bold
