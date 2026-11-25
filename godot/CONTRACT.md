# 移植契約 (全エージェント必読)

原作: `../index.html` の `<script>` (5257-10544行)。仕様の正は常に原作JS。**数値・確率・文言・順序を変えない。**
索引: `PORTING_INDEX.md` に、原作の全関数・全トップレベル変数と所有モジュールが載っている。

## 所有と配置
- 各モジュールは autoload (`project.godot [autoload]` 登録済み): U, Audio, World, Inp, Meta, Cards, Game, Enemies, Combat, Render, UI。ファイルは `scripts/<小文字>.gd`(骨組みのスタブ有り。自分の担当だけ編集)。
- **自分の担当ファイル以外は編集禁止**(project.godot も触らない)。必要な追加は担当者への依頼としてレポートに書く。
- 他モジュールの関数/変数は `Owner.name` で参照(索引に載っている名前のみ。名前は原作と同一)。索引に無い名前を新設して他所から呼ばないこと。
- 原作のトップレベル `let/const` は、その行の所有者の `var/const` として**同名**で置く。関数も同名(camelCaseのまま)。
- UI(DOM)関連の関数(索引の UI)は呼ばない: 代わりに `UI.hook("関数名", [引数...])`。戻り値が要る場合は null を考慮。
- DOM操作・innerHTML・localStorage・Tailwind・PWA・Diagnostics は移植しない(該当箇所は UI.hook か省略)。保存が必要なら `Meta.storage_get(key)` / `Meta.storage_set(key, str)`(user://へ保存; Metaが提供)を使う。

## 翻訳ルール
- JSオブジェクト → Dictionary(同じキー名)。`p.damage` のドット記法で読み書き可。未定義キーは `p.get("k", 既定)`。JSの `a?.b`, `a||b`, `??`, `undefined` の挙動に注意(0/空文字のfalsy差)。
- JS配列 `.push/.filter/.some/.reduce` → Array 同等メソッド。ループ中の削除は逆順 or 新配列。
- `Math.*` → GDScript の `sin/cos/atan2/sqrt/floori/ceili/roundi/absf/minf/maxf/pow/hypot→Vector2.length or sqrt(dx*dx+dy*dy)`。`TAU` は組込み。`Math.random()` → `randf()`、`rand(a,b)` → `U.rand`。`pick/dist2/clamp` → `U.*`。
- `performance.now()` → `U.now_ms()`、`Date.now()` → `Time.get_unix_time_from_system()*1000`。
- 時間は秒(JSの dt と同じ)。`update(dt)` 系は `Game` の固定ステップから呼ばれる(原作 9495-9530)。
- JSの `state` は文字列('menu','playing','paused',...)のまま `Game.state`。
- 型: 辞書の値は型推論不可 → `var x: float = d.k` と明示。`:=` を辞書値に使うとパースエラーになる。
- 描画は `Render`(Renderモジュール)が担当: `Render.draw(ci: CanvasItem)` を1つの `_draw()` から呼ぶ。canvas 2D API は `ci.draw_*` に置換。グロー(shadowBlur)は半透明の太線/大円の二重描きで近似。
- 検証: `godot --headless --path godot --check-only --script res://scripts/<file>.gd` 相当 または `godot --headless --path godot --import` で**自分のスクリプトに Parse Error が無いこと**。Godot は `/tmp/godot/Godot_v4.7.1_stable_linux.x86_64`(Godot_v4.7.1-stable_linux.x86_64)。他モジュール未完成による参照エラーは許容。
- コミットしない/pushしない(PMがまとめて行う)。完了時、**公開した関数・変数の一覧**と**未移植/他担当への依頼**を短く報告。

## 結合タイミング
PMが `main.gd` と結合する。モジュール単体の動作確認は不要。ただし純粋ロジック(Meta, Cards)は可能なら小さなテスト(`--script`)で確認すること。
