# NEON FRACTURE v28.4 QA

## 今回の入力修正

v28.3には、通常のWASDでも不安定になり得る構造がまだ残っていました。

1. `keys` と `physicalMoveKeys` の2系統を移動判定に使っていたため、
   フォーカス・パネル遷移・入力方式切替のタイミングで状態がずれる余地がありました。
2. `e.isComposing` をWASD判定より先に弾いていたため、日本語IMEの状態によっては
   通常のWASDキー入力が無視される可能性がありました。
3. windowの `focus` イベントでも物理キー状態を消していたため、
   フォーカスイベントの発火順によっては押しているキーが消える経路がありました。

v28.4では `physicalMoveKeys` をキーボード移動の唯一の正本に変更しました。
`keys` は表示・デバッグ用のミラーで、移動計算には使いません。

- keydown: 物理キー集合へ追加
- keyup: window + document captureで確実に削除
- カード / スキル / Pause中: 物理キーは追跡するが戦闘シミュレーションは停止
- 復帰時: 実際に押し続けているキーだけ即反映
- blur / visibilitychange / pagehide: 安全境界として完全クリア
- 日本語IME composition中でもWASD / 矢印キーは処理
- `KeyboardEvent.code` が取れない場合は `key` からWASD/矢印を補完

## 専用入力ストレステスト

**30/30 合格**

含む項目:
- W/A/S/D個別の押下・解放
- 斜め移動
- A+Dなど逆方向同時押し
- 120回の高速WASD重複押下・解放
- 日本語IME `isComposing=true` 相当
- `event.code` 欠落時の `event.key` フォールバック
- Qカード画面をまたいだ押しっぱなし / 画面中のキー解放
- focusイベントで保持キーが消えないこと
- blur後にゴースト入力が残らないこと
- 矢印キーの同等動作
- 未捕捉例外なし

## 回帰テスト

Desktop: **42/42**

Touch / Mobile: **124/124**

## 静的確認

- JavaScript syntax: OK
- Service Worker cache: `neon-fracture-v28-4`
- index.html SHA-256: `9c50b0779f69801cdea0a56336197c9c249e94054af646f124ff9ae991db86c9`

## 未検証

- ユーザー実機の物理キーボード固有ドライバ
- 実機iPhone / Safari / PWA
- OSがキーアップイベントそのものを配送しない特殊ケース
