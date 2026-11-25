# 完全移植メモ (index.html -> Godot 4.7)

方針: 原作JS(index.html 5257-10544行)を**変数名・関数名・構造を保ったまま**GDScriptへ機械的に翻訳する。
- JSオブジェクト = Dictionary(同じキー名)。`p.damage` のドット記法で書く。
- グローバル状態は autoload `G` (scripts/g.gd) に集約。定数テーブルは `scripts/defs.gd`。
- 描画は `world.gd` の `_draw()`(原作の Render 節)。UIはコードで組むControl(`ui/*.gd`)。
- セーブは `user://nf_meta_v1.json` 等(localStorageキーと同名)。Export/Importは原作と同じJSON形式を維持。
- 数値・確率・文言は原作と同じ値を使う(コピーして変換)。

## 原作の節 (行番号は index.html)
| 行 | 内容 | 状況 |
|---|---|---|
| 5257-5500 | Diagnostics/storage/Sound/定数 | 未 |
| 6087-6330 | 難易度/カスタム/研究(META_STATS)/MODULES | 未 |
| 6265-6500 | カード構文/emitCardTrigger | 未 |
| 6500-7250 | 成長制限/meta/セーブ/実績/Upgrades | 未 |
| 7251-8660 | Entities(player/敵/ボス/弾) | 未(試作に敵6種のみ) |
| 8660-9300 | Update/spawn/戦闘 | 未 |
| 9300-9700 | Render | 未 |
| 9700-10544 | UI/モバイル/PWA/中断再開 | 未 |
