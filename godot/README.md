# NEON FRACTURE — Godot 4.7 ネイティブ版

HTML版(`../index.html`)は原作として無改変のまま残しています。この `godot/` は
Godot 4.7 (GL Compatibility) による**フル移植版**です(以前の戦闘コア試作は本移植に置き換え済み)。
Windows / macOS / Linux / Android / iOS(およびWeb)へ同一プロジェクトから書き出せます。

## 実行

    godot --path godot            # 実行
    godot --editor --path godot   # エディタで開く

書き出し・テスト・サイズ最適化は [BUILD.md](BUILD.md) を参照。

## 構成
- `main.tscn` / `main.gd` — エントリ。画面遷移とメインループ
- `scripts/` — ゲームロジックのモジュール(autoload): `u`(ユーティリティ) `audio` `world` `inp`(入力) `meta`(永続成長・セーブ)
  `cards` `game`(ラン状態) `enemies` `combat` `render`(コード描画) `ui` `runsave`(中断セーブ)
- `scripts/ui/` — 画面: home / runconfig / hud / upgrade / pause / gameover / meta(各タブ) / settings / how ほか。共通部品は `kit.gd`, `nf_screen.gd`
- `data/defs.json` — 原作 `index.html` から抽出したデータ表(同一の数値を使うため)
- `../tools/` — 抽出スクリプト: `extract-data.mjs`(defs.json生成)、`make-index.mjs`(PORTING_INDEX.md生成)
- `tests/` — ヘッドレス/E2Eテスト(sim_stress, combat_audit, game_audit, meta_test, runsave_test, e2e)
- `preview/` — 画面確認用スクリーンショット(書き出しから除外)
- `icons/` — Androidアダプティブアイコン素材
- 設計資料: `CONTRACT.md` `PORTING.md` `PORTING_INDEX.md` `UI_GUIDE.md` `INTEGRATION_LOG.md`

## 操作
PC = WASD / マウス照準 / SPACE(ダッシュ)。モバイル = 左半分で移動スティック、右半分で照準、DASHボタン。横画面固定。
