# ビルド & リリース手順 (Godot 4.7.1)

## 1. 開く・実行する
    godot --editor --path godot      # エディタ
    godot --path godot               # 直接実行
初回は `godot --headless --path godot --import` でアセットを取り込んでおくと書き出しが安定します。

## 2. 書き出し
`export_presets.cfg` に Linux / Windows Desktop / macOS / Android / iOS / Web のプリセットを用意済み。
エクスポートテンプレート(4.7.1.stable)が必要です。エディタの「エディタ > エクスポートテンプレートの管理」か、
`Godot_v4.7.1-stable_export_templates.tpz` を `~/.local/share/godot/export_templates/4.7.1.stable/` に展開します
(Windowsは `%APPDATA%\Godot\export_templates\4.7.1.stable\`、macOSは `~/Library/Application Support/Godot/export_templates/4.7.1.stable/`)。

    mkdir -p build/linux build/windows build/macos build/android build/web
    godot --headless --path godot --export-release "Linux"            build/linux/neon-fracture.x86_64
    godot --headless --path godot --export-release "Windows Desktop"  build/windows/neon-fracture.exe
    godot --headless --path godot --export-release "macOS"            build/macos/neon-fracture.zip
    godot --headless --path godot --export-debug   "Android"          build/android/neon-fracture-debug.apk
    godot --headless --path godot --export-release "Web"              build/web/index.html

`tests/ preview/ tools/ icons/ *.md` は各プリセットの除外フィルタで書き出しから外しています。Androidのアダプティブアイコンはエクスポータがpck外から直接APKへ取り込むため、`icons/*` を除外しても問題ありません。

Linuxは `binary_format/embed_pck=false` のため実行ファイルと同じ場所に `.pck` が生成されます(2つ一緒に配布)。

### Android
必要: JDK 17、Android SDK(platform-tools, build-tools 35.0.1, platforms;android-35, cmdline-tools, NDK不要)。
1. エディタ設定 > エクスポート > Android で `Java SDK Path` と `Android SDK Path` を設定(または環境変数 `ANDROID_HOME`, `JAVA_HOME`)。
2. デバッグ用キーストア作成(エディタが初回に自動生成も可):

       keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore \
         -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deploy
       # ~/.local/share/godot/ もしくはエディタ設定の debug_keystore に指定
3. リリース署名: 自前の keystore を作り、環境変数で渡す(コミット禁止)

       export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/release.keystore
       export GODOT_ANDROID_KEYSTORE_RELEASE_USER=alias
       export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
4. プリセット設定: パッケージ `dev.neonfracture.app`、横画面(sensor landscape)、没入モード、armeabi-v7a + arm64-v8a、minSdk/targetSdkはGodot 4.7既定値(空欄=既定)。
   Google Play(AAB)向けは Gradleビルド(`gradle_build/use_gradle_build=true`, `export_format=1`)に切り替え、エディタで「Androidビルドテンプレートをインストール」。
5. 画面常時ONはゲーム側ではなくプロジェクト設定 `display/window/energy_saving/keep_screen_on`(既定true)で制御されます。

### iOS
macOS + Xcode が必須(Linux/Windowsでは書き出し不可)。プリセットは `export_project_only=true` で Xcodeプロジェクトを出力します。
`application/app_store_team_id` とバンドルID(現在 `dev.neonfracture.app` はプレースホルダ)を自分のものに変更し、
Xcodeで署名・実機ビルド。`godot --headless --path godot --export-release "iOS" build/ios/neon-fracture.ipa`
(署名情報が空の間はプロジェクト出力のみ)。

### macOS
Linux上でも zip の書き出しはできますが、署名・公証は macOS 上で `codesign`/`notarytool` が必要です(未署名だと初回起動に右クリック>開くが必要)。

## 3. サイズ最適化(カスタムテンプレート)
標準テンプレートは3D・物理・XR等を含み大きい(Linux release 約70MB、Web wasm 約38MB)。2D専用ゲームなので、
不要モジュールを外した最小テンプレートを自前ビルドできます(本リポジトリでは未ビルド)。`custom.py`:

    # godot ソースのルートに置く
    optimize = "size"            # 4.xでは size / size_extra
    lto = "full"
    production = "yes"
    deprecated = "no"
    disable_3d = "yes"
    disable_advanced_gui = "yes"
    disable_physics_3d = "yes"
    disable_navigation_3d = "yes"
    disable_xr = "yes"
    openxr = "no"
    modules_enabled_by_default = "no"
    module_gdscript_enabled = "yes"
    module_text_server_fb_enabled = "yes"
    module_freetype_enabled = "yes"
    module_svg_enabled = "yes"
    module_regex_enabled = "yes"
    module_noise_enabled = "no"
    module_webp_enabled = "yes"
    module_vorbis_enabled = "yes"
    module_ogg_enabled = "yes"
    module_jpg_enabled = "yes"
    vulkan = "no"                # GL Compatibilityのみ使用
    d3d12 = "no"
    metal = "no"
    minizip = "yes"

ビルド例(必要なモジュールは `scons --help` と `modules/` で確認し、足りなければ有効化):

    scons platform=linuxbsd target=template_release arch=x86_64 custom_modules= profile=custom.py
    scons platform=android target=template_release arch=arm64
    scons platform=web target=template_release threads=no

出来たバイナリを各プリセットの `custom_template/release`(Androidは `custom_template` にAPK)へ指定します。
GDScriptを使うため `gdscript` と、フォント描画の `freetype`/`text_server_fb`(必要なら `text_server_adv`)は残してください。
`.godot/` 内の `editor_features` 変更後は必ず実機テストで描画・音声・保存を確認すること。
Androidはさらに `ProGuard/R8` 無効の標準ビルドでも、armeabi-v7a を外して arm64-v8a のみにするとAPKが約半分になります。

## 4. テスト
    # シミュレーション ストレス(全シナリオ。失敗で終了コード1)
    godot --headless --path godot res://tests/sim_stress.tscn
    NF_SCENARIO=enemies,bosses godot --headless --path godot res://tests/sim_stress.tscn
    # 個別監査
    godot --headless --path godot res://tests/combat_audit.tscn
    godot --headless --path godot res://tests/game_audit.tscn
    godot --headless --path godot --script res://tests/meta_test.gd
    godot --headless --path godot --script res://tests/runsave_test.gd
    # E2E(実UIにイベントを注入。スクショは /tmp/e2e)
    NF_E2E=/tmp/e2e xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path godot --resolution 1600x900
    # 起動スモーク(releaseビルド)
    xvfb-run -a ./neon-fracture.x86_64 --rendering-driver opengl3 --quit-after 240

## 5. CI
`.github/workflows/godot-build.yml` がタグ(`v*`)/手動実行で Linux・Windows・macOS(zip)・Android(デバッグAPK、未署名リリース用ではない)をビルドし artifact を保存します。
