# 完全移植メモ (index.html -> Godot 4.7)

状況: 全モジュール・全画面の移植と、実フローE2E・原作との突き合わせ監査まで完了。
詳細は `AUDIT_*.md` / `INTEGRATION_LOG.md` / `BUILD.md` / `UI_GUIDE.md` を参照。

方針: 原作JSの変数名・関数名・構造を保って GDScript へ機械的に翻訳(JSオブジェクト=Dictionary)。
データ表は `tools/extract-data.mjs` が index.html から `data/defs.json` へ抽出(数値の一致を保証)。
所有範囲は `PORTING_INDEX.md`(`tools/make-index.mjs` で生成)。

| 領域 | ファイル | 状況 |
|---|---|---|
| Game/Inp/Enemies/Combat/Cards/Meta/World/Render/Audio | scripts/*.gd | 完了・監査済 |
| 中断セーブ(原作と同一JSフォーマット) | scripts/runsave.gd | 完了・往復テスト済 |
| UI基盤・全画面・研究室タブ | scripts/ui.gd, scripts/ui/* | 完了・E2E済 |
| 書き出し・CI | export_presets.cfg, ../.github/workflows/godot-build.yml | Linux/Web実測済、他OSは未実機 |

## 未検証/既知の差
- Android/iOS/Windows/macOS の実機書き出し・実機操作は未検証(サンドボックスにSDK/Xcodeなし)。
- 標準テンプレートのLinuxバイナリは約70MB(pck 0.6MB)。軽量化はカスタムテンプレート(BUILD.md参照・未実施)。
- 背景グラデ/ビネットは同心円近似。searchKey に NFKC 正規化なし。
- ボス報酬フローのE2E、実ゲームパッド操作は未テスト。
