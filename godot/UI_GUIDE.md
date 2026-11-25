# UI_GUIDE — 画面(screen)の作り方

共有ファイル(`scripts/ui.gd`, `scripts/ui/kit.gd`, `scripts/ui/nf_screen.gd`, `main.gd`)は編集しない。**自分の `scripts/ui/screen_<id>.gd` だけ**を追加する。

## 1. 画面ファイル
- ファイル名 `res://scripts/ui/screen_<id>.gd` → 起動時に自動検出され、`UI.screens["<id>"]` に登録(id = ファイル名から `screen_` と `.gd` を除いたもの)。
- 雛形: `extends NFScreen`(`Control`継承)。`build()` でウィジェットを `content`(セーフエリア込み MarginContainer)へ追加。`NFScreen.setup(ui)` が `UI.root` への追加を済ませる。
- NFScreen を使わない場合は `extends Control` で `func setup(ui)` を実装し、自分で `ui.root.add_child(self)`(初期は `visible=false`)。`open(args)` / `close()` があれば UI が呼ぶ。
- NFScreen のフィールド: `modal`(背面入力を遮断+暗幕 `dim_alpha`), `persistent`(HUD等: `UI.goto` で閉じない), `layer_z`(重なり順, `_init` 相当は `build()` 冒頭でなく宣言時に設定), `default_focus`(開いた時のフォーカス), `fade_time`。
- フック: `on_open(args)`(開く度に Game/Meta から再描画), `on_close()`, `on_cancel() -> bool`(Esc/B を消費するなら true)。

## 2. フックを受ける
sim は `UI.hook("name", [args])` を呼ぶ。ルーティング: UI自身の `h_name` → **最初に `h_name` を持つ画面**(args の個数は自動調整) → 全画面の `b_name`(ブロードキャスト、HUD+他画面が同じ通知を受けたい時)。
```gdscript
func h_showUpgrade() -> void: UI.show_screen("upgrade")      # 戻り値はそのまま sim へ返る
func h_renderCardChoices(info: Dictionary) -> void: ...
func b_syncCombatHud() -> void: ...                           # 複数画面が受けられる
```
未処理フックは `UI.unhandled`(名前→回数)。`NF_HOOKLOG=1` で初回を標準出力に表示。
UI が実装済み: `showInputNotice(msg, ms)`, `utilityMessage(msg, kind)` → トースト。

## 3. 開閉
`UI.show_screen(id, args={})` / `UI.hide_screen(id)` / `UI.toggle_screen(id)` / `UI.is_open(id)` / `UI.goto(id)`(非persistentを全て閉じて開く) / `UI.hide_all()` / `UI.top_screen()`。シグナル `screen_opened/closed`。
トースト: `UI.toast(text, kind="info"|"ok"|"warn"|"err"|"violet", ms=2200)`。確認: `Kit.confirm(title, msg, on_yes, on_no, "OK", "キャンセル", danger)`。
Esc: メイン側 `Inp.handleEscape` が状態別に `closeUtility`/`closeHow`/`closeRunConfig`/`hidePauseConfirm` 等のフックを呼ぶので、それらの `h_` で `UI.hide_screen` する。ダイアログ(Kit.confirm)は UI が Esc を先取りして閉じる。ゲームパッド B は UI が `Inp.handleEscape()` へ転送。
`UI.blocks_game_input()` = modal 画面/ダイアログ表示中。ポインタが UI 上か: `UI.pointer_over_ui()`(main.gd の `_input` で戦闘入力を抑止する用)。

## 4. Kit(デザインシステム)
色: `Kit.CYAN/VIOLET/FUCHSIA/AMBER(CR)/EMERALD/ROSE/SLATE/TEXT/DIM/MUTE`、`Kit.rarity_color("EPIC")`, `Kit.rarity_label()`。余白 `Kit.S1..S7`(4/8/12/16/24/32/48)、文字 `Kit.FS_XS..FS_3XL`。
- 文字: `Kit.label(text,size,color,align,wrap,bold)`, `Kit.heading(text,accent)`, `Kit.hsep()`, `Kit.spacer()`, `Kit.fill_spacer()`, `Kit.hbox/vbox(sep)`, `Kit.margin(ctl)`。
- 面: `Kit.panel(accent,pad)` → `GlassPanel`(子は `.body` に追加)。
- 操作: `Kit.button(text, kind, cb)` kind=`primary|cta|ghost|danger|success|tab`、`Kit.toggle(v,cb)`, `Kit.slider(min,max,step,v,cb)`, `Kit.segmented([...],idx,cb)`(signal `selected(i)`), `Kit.setting_row(title, ctl, desc)`。
- 表示: `Kit.chip(label,value,color,icon)`, `Kit.bar(0..1,color,text,h)`(`set_value_smooth`), `Kit.rarity_card(rarity,title,desc,icon,lv)`(signal `pressed`, `.selected`), `Kit.scroll_list()`+`Kit.list_of(sc)`, `Kit.tooltip(ctl,text)`。
- 書式(ja-JP): `Kit.num(n)`=`12,345`, `Kit.short(n)`=`1.2万/2.3億`, `Kit.pct(x,d)`, `Kit.mmss(sec)`。
- 見本: `NF_SCREEN=kitgallery`(`scripts/ui/screen_kitgallery.gd`)。パターン最小例: `screen_example.gd`。
テーマは `UI.root` に設定済みなので素の `Label`/`HSlider`/`LineEdit`/スクロールバー/ツールチップも自動でネオン調になる。画像アセットは使わない(StyleBoxFlat/_draw)。

## 5. ゲーム状態の読み方
読み取りのみ推奨。`Game.state/player/wave/time/score...`、`Meta.*`(永続データ・CR・保存は `Meta.storage_get/set`)、`Cards.*`。操作は原作関数名で `Game.resetGame()`, `Game.togglePause()`, `Meta.closeMeta()` 等を呼ぶ。毎フレーム更新が要る HUD は `_process` で差分だけ更新(文字列を変えない限り `Label.text=` を避ける)。

## 6. タッチ/コンパクト
`Kit.is_compact()`(タッチ操作中・ウィンドウ高さ<700・`NF_COMPACT=1`)。コンパクト時は `Kit.fs()` が文字を1.2倍、ボタン最小高 56px(PC 44px)。レイアウトは HBox/Grid の列数を `Kit.is_compact()` で切替え、固定ピクセル配置を避ける。長いリストは `ScrollContainer`(`Kit.scroll_list`)でドラッグスクロール可。タップ対象は 44px 以上、ホバー依存の情報を作らない(tooltip は補助のみ)。
セーフエリア: `NFScreen.content` は `Kit.safe_margins()`(`DisplayServer.get_display_safe_area()` 由来 {l,t,r,b} + 最小8px)を自動適用。`content` を使わず全面に置く場合は自分で `Kit.safe_margins()` を使う。HUDで端に寄せる要素も同様。

## 7. フォーカス / ゲームパッド
Kit のボタン/トグル/カードは `FOCUS_ALL`、フォーカス時に白縁+グロー。`default_focus` を設定すると開いた時にそこへ、未設定なら最初のフォーカス可能コントロール。方向キー/スティックで移動、`ui_accept` で決定(標準 GUI 機能)。

## 8. 確認用スクリーンショット
```
cd godot
NF_SCREEN=<id> NF_SHOT=/tmp/shots [NF_COMPACT=1] xvfb-run -a -s "-screen 0 1600x900x24" \
  /tmp/godot/Godot_v4.7.1-stable_linux.x86_64 --rendering-driver opengl3 --path . --resolution 1600x900
```
→ `/tmp/shots/screen_<id>.png` を保存して終了(`main.gd` の `NF_SCREEN`)。状態依存の画面は `on_open` でダミーを出す or `Game`/`Meta` を事前に設定できないため、`args` を使って `UI.show_screen(id, args)` したい場合は `h_`/`on_open` に既定値を持たせる。モバイル確認は `--resolution 1280x600 NF_COMPACT=1`。
構文確認: `/tmp/godot/Godot_v4.7.1-stable_linux.x86_64 --headless --import --path . 2>&1 | grep -A2 -e screen_<id>.gd`
