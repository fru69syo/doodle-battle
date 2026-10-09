# AR（AR チーム） — 設計メモ

SPEC §6 の実装メモです。担当範囲は `app/lib/features/ar/`、`app/test/features/ar/`、`app/android/app/src/main/kotlin/com/fru69syo/doodle_battle/ar/`、それに Android の設定ファイルに入れた少しの変更です。

## 1. 技術選定（2026-10 に調査）

| 候補 | 状態（2026-10） | Flutter 3.47 / Dart 3 | AGP 9.1・targetSdk 36・16 KB | 判定 |
|---|---|---|---|---|
| `arcore_flutter_plugin` | 最終版は 0.1.0（2023-02）。Sceneform 1.x に依存しているが、Google は Sceneform をアーカイブ済み | ✗ `sdk: <3.0.0` なので pub が解決できない | ✗ Sceneform のネイティブライブラリは 16 KB に対応していない | 不採用 |
| `ar_flutter_plugin_2`（ar_flutter_plugin のフォーク群） | 最終版は 0.0.3（2025-03）。更新がほとんど無い | ✗ `sdk: <3.0.0` | 不明（古い SceneView） | 不採用 |
| `flutter_sceneview`（公式。pub.dev の `sceneview_flutter`・`sceneview` は別人がアップロードしたもの） | 4.53.0（2026-10-08）。開発は活発だが、状態は **Alpha**。アップロード者は未検証 | ○ | △ Android 側が sceneview **4.6.2** と古い AGP 8.2 の buildscript を固定している | 不採用：モデルを読み込めるのは Flutter の asset か https の URL だけで、**端末で作った GLB を渡す手段が無い**。Android では撮影（キャプチャ）の API も無い |
| **自前の PlatformView（Kotlin）＋ `io.github.sceneview:arsceneview`** | SceneView 本体はとても活発（4.x、ほぼ毎日リリース）。Filament 1.72 と ARCore 1.54 を使う | ○ | ○ 実機確認済み（下記） | **採用** |

採用した理由:
- 保守されているのは SceneView 本体だけです（Flutter 向けのラッパーは止まっているか、Alpha です）。PlatformView を自分たちで薄く書けば、ラッパーが SceneView の更新に追いつくのを待たずに済みます。
- 実行時に作った GLB ファイルを読み込めます。キャプチャ（TextureView）、平面へのヒットテスト、アンカーの付け替えも自由にできます。
- **バージョンは `arsceneview:4.34.0`（2026-09-04）に固定しました。** 4.35 以降は Compose 1.12 と androidx.core 1.19 に依存していて、どちらも **compileSdk 37** を要求します。このプロジェクトは compileSdk 36（AGP 9.1 が推奨する上限）なので、4.34.0 が使える最新版です。compileSdk を 37 に上げれば最新版にできます（§9 の PM 判断事項を参照）。
- 16 KB ページへの対応を確認しました。release の arm64 APK を ELF の `p_align` で調べたところ、64bit の `.so`（filament・gltfio・filament-utils・arcore_sdk_c/jni・androidx など）はすべて ≥16 KB でした。`zipalign -c -P 16` も通っています。32bit の armeabi-v7a 版 ARCore は 4 KB ですが、16 KB の要件は 64bit だけが対象です。

## 2. 構成

```
ArViewScreen(character)                      lib/features/ar/ar_view_screen.dart
 ├─ 準備: GLB 生成（Isolate）→ 一時ファイルへ、checkArSupport()、カメラ権限
 ├─ ArMode.ar     → ArCoreStage          native/arcore_stage.dart
 │                    ├─ ArNativeView（PlatformViewLink, TLHC）──┐
 │                    └─ Flutter 側のジェスチャとヒントの重ね表示 │ MethodChannel
 │                                                               ▼
 │   Kotlin: ArPlugin → ArPlatformView(ComposeView) → DoodleArScene（SceneView ARSceneView, TextureView）
 ├─ ArMode.simple → SimpleArStage（camera ＋ StandeeSprite）  simple_ar/
 └─ シャッター → ArCaptureSource.capture() → PhotoSaver（gal）→ ギャラリー
```

- **ジェスチャはすべて Flutter で処理します。** タップ（と 1 本指のドラッグ）では `placeAt(x,y)` を呼び、ネイティブ側が水平面にヒットテストしてアンカーを置き直します。ピンチとひねりでは `setTransform(scale, yaw)` を呼びます。PlatformView 自体はタッチを受け取らないので、タッチを奪い合う問題が起きません。
- 置いたキャラは**カメラのほうを向きます**（アンカーのヨー角を計算しています）。2 回目からはアンカーを付け替えるだけなので、モデルを作り直しません。
- MainActivity は `FlutterActivity`（ComponentActivity ではありません）のままです。そのため Compose 用に `ArViewLifecycleOwner` を用意しました。これは Activity のライフサイクルを写して動き、View を破棄するときに一緒に破棄されます。
- SceneView に組み込まれている英語の権限・インストール表示はオフにしています（`permissionHandler = null` と各 overlay を `null`）。権限とインストールは Dart 側で先に処理します。

## 3. 公開 API

```dart
import 'package:doodle_battle/features/ar/ar.dart';

ArViewScreen(character: c)                    // 画面。戻るボタンは Navigator.maybePop（onBack で差し替え可）
ArViewScreen(character: c, allowArCoreInstallPrompt: false)
Future<ArSupport> checkArSupport()            // supported / needsInstall / unsupported / unknown
Future<ArInstallResult> requestArCoreInstall({bool userRequested = true})
StandeeGlb buildStandeeGlb(Uint8List png, {StandeeGlbOptions options})   // 純 Dart
Future<StandeeGlb> buildStandeeGlbInBackground(...)                       // Isolate.run
ArEffects.forCharacter(c)                     // Lv10 オーラ、Lv20 オーラ＋きらきら
ArDebugPage()                                 // デバッグ入口（サンプルキャラ、Lv・属性の切替、かんたん AR を強制）
```

UI チームへ: `GoRoute(path: '/ar', builder: (_, s) => ArViewScreen(character: s.extra as Character))`、デバッグには `GoRoute(path: '/debug/ar', builder: (_, _) => const ArDebugPage())` のように登録してください。画面は**縦向き**を前提にしています（かんたん AR のプレビューと合成のため）。アプリ全体を縦固定にするかは UI チームで決めてください。

## 4. 「紙の立て札」GLB（`glb/standee_glb.dart`）

- 入力は切り抜き PNG（背景透過、512px 以下）です。不透明な部分の外接矩形で切り詰めてから、紙の白いフチ（長辺の 3.5%）を**正確なユークリッド距離変換**で付けます。テクスチャはフチ込みで 512px 以下にします。
- 座標は **+Y が上、+Z が正面、原点は足元の中心**です。高さは既定で **25 cm**。横幅は最大 40 cm で、それより広い絵は全体を縮めます。アスペクト比は保ちます。
- メッシュ `standee` の構成:
  - 表（z=+1.5 mm、`MASK` 0.5、片面）
  - 裏（z=−1.5 mm、巻き順を逆にして法線 −Z、片面。生成りの紙に絵が 14% 透けて、裏から見ると鏡像になる）
  - 芯の 2 層（±0.5 mm、両面）。斜めから見たときに紙の切り口が白く見える
- 素材は `KHR_materials_unlit` を使っています（部屋の明るさに関係なく、子どもの絵の色が出ます）。`extensionsRequired` には入れていないので、対応していないビューアでは PBR で表示されます。
- アニメーション `idle`（1.2 秒のループ、線形補間で 25 キー）: ぴょこっと跳ねる（高さの 6%）、着地で潰れて伸びる、床の影が縮む。Lv10 以上はオーラが脈打ち、Lv20 はきらきらが瞬きます。ネイティブ側は `autoAnimate` でループ再生します。
- 進化エフェクト:
  - Lv10 以上: オーラ。紙のシルエットからの距離で作ったグロー（`BLEND`、属性の色。にじは虹色のグラデーション）を z=0 に置きます。表と裏の間にあるので、どちらから見ても輪郭だけが光ります。
  - Lv20 以上: さらにきらきら 6 個。
- 床には影の円（`BLEND`、y=1.5 mm）を置いています。
- 検証:
  - `test/features/ar/standee_glb_test.dart`（ヘッダ、チャンク、4 バイト境界、buffer と BIN の長さ、各 accessor が使うバイト長、PNG のデコード、素材、巻き順、原点と寸法、ループのつながり、エフェクト）
  - Khronos の **gltf-validator 2.0.0-dev.3.10**: `app/test/features/ar/gltf_validator/run.sh` を実行すると、4 種類のサンプルすべてで **errors=0 / warnings=0** でした。info の `IMAGE_NPOT_DIMENSIONS` だけ出ますが、GLES3 の Filament は NPOT のミップマップに対応しているので問題ありません。
- 大きさと生成時間: 単色のサンプル絵では、Lv1 が約 17 KB、Lv20 が約 33 KB でした（PNG 2 枚が大半を占めるので、実物の絵を撮った画像だと数百 KB になる見込み）。512px の絵で、デスクトップ JIT で 70〜140 ms。端末では Isolate で実行します。

## 5. かんたん AR（フォールバック）

- 使う場面: ARCore 非対応、`unknown`、ARCore のインストールを断ったとき、セッションの作成やモデルの読み込みに失敗したとき（その場で「かんたん AR に きりかえたよ」と表示して切り替えます）。AR 対応端末では、右上のチップで AR とかんたん AR を行き来できます。
- `camera`（CameraX）で背面カメラを `ResolutionPreset.high`、音声なし、縦向きで撮影します。`StandeeSprite` は GLB と同じ曲線（`idleHop`・`idleSquash`・`sparkleScale`）で跳ね、オーラときらきらも付きます。
- 操作: 1 本指でドラッグ、2 本指でピンチとひねり（足元を中心に回転）。
- 撮影: `takePicture` で撮った写真を、画面で見えていた範囲（`BoxFit.cover` で切り取られた範囲）に切り抜き、同じ配置でスプライト（オーラ・紙・きらきら）を合成して JPEG にします。処理は Isolate（`photo_compositor.dart`、テストあり）で行います。

## 6. 権限・保存

- カメラは `ArPlugin` 経由で実行時に許可を求めます。「今後表示しない」の状態なら「せっていを ひらく（おうちのひと）」を出します。設定画面から戻ってきたら、もう一度確認します。
- ギャラリーへの保存は `gal` で行い、**アルバムは作りません**。Android 10〜15 は MediaStore 経由なので権限は不要です。Android 7〜9 だけ `WRITE_EXTERNAL_STORAGE`（`maxSdkVersion=28`）を求めます。API 29 でアルバムを作ると権限が必要になるため、アルバムは使っていません。
- AR の写真は TextureView の `getBitmap()` で撮った JPEG（品質 92）です。カメラ映像と 3D（オーラ・きらきらも含む）が写り、Flutter の UI は写りません。

## 7. Android の変更（共有ファイル）

- `settings.gradle.kts`: `org.jetbrains.kotlin.plugin.compose` 2.4.0 を `apply false` で追加（Kotlin のバージョンとそろえるため）。
- `app/build.gradle.kts`: compose プラグイン、`buildFeatures.compose = true`、依存関係（`io.github.sceneview:arsceneview:4.34.0`、`com.google.ar:core:1.54.0`、`androidx.compose:compose-bom:2026.06.01` の ui と foundation）。applicationId・minSdk（`flutter.minSdkVersion`＝24）・targetSdk・compileSdk は変えていません。
- `MainActivity.kt`: `configureFlutterEngine` で `flutterEngine.plugins.add(ArPlugin())` を呼ぶ 1 行を追加。
- `AndroidManifest.xml`:
  - 追加: `CAMERA`、`WRITE_EXTERNAL_STORAGE` と `READ_EXTERNAL_STORAGE`（どちらも maxSdk 28）
  - `<meta-data com.google.ar.core = optional>`
  - `uses-feature` の `camera`・`camera.any`（camera プラグインが required にしているのを上書き）・`camera.ar`・`glEsVersion 0x30000`（SceneView が required にしているのを上書き）をすべて `required=false`
  - プラグインが勝手に入れる `RECORD_AUDIO`（camera）と `VIBRATE`（SceneView）を `tools:node="remove"` で削除
  - ARCore を使わない端末にもインストールできるように、OpenGL ES 3.0 未満の端末は `checkArSupport()` が `unsupported` を返します
- マージ後のマニフェストに残る、ライブラリ由来の通常権限: `INTERNET`（SceneView）と `ACCESS_NETWORK_STATE`（SceneView が依存している media3）。

## 8. ビルド結果（この環境、AGP 9.1・Gradle 9.3.1）

| | ベースライン（main） | feat/ar |
|---|---|---|
| `flutter build apk --debug`（全 ABI） | 153.6 MB | 190.7 MB（+37 MB） |
| `--release --split-per-abi`、arm64 | 15.7 MB | 27.6 MB（**+11.9 MB**。.so が +6.8 MB、dex が +1.4 MB 圧縮後、camera と gal も含む） |
| ビルド時間（依存はキャッシュ済み） | debug の初回 約 2 分（NDK のインストールを含む）／release（arm64）87 秒 | debug のクリーンビルド 57 秒、差分ビルド 10 秒前後／release（arm64）182 秒 |

R8（release）は警告なしで通りました。

> この環境では Maven Central が HTTP 429 を返すため、手元では `GRADLE_USER_HOME=/home/user/.gradle-ar` に Google のミラーを使う init script を置いてビルドしました。リポジトリには何も入れていません。

## 9. PM の判断が必要なこと

1. **ARCore のインストール案内**: `needsInstall` のとき、Play ストアで「Google Play 開発者サービス for AR」を入れる案内を出しています（ボタンの文言は「おうちのひとと いれる」）。ファミリーポリシーの観点から保護者ゲートの後ろに置くか、出さないか（`allowArCoreInstallPrompt: false`）を決めてください。
2. compileSdk を 37 に上げるかどうか（上げれば SceneView と Compose を最新にできます。AGP 9.1 の推奨上限は 36）。
3. 写真の保存先: アルバムは作らず `Pictures/` に保存します（`rakugaki_ar_YYYYMMDD_HHMMSS.jpg`）。「らくがきバトル」アルバムを作る場合、Android 10 では保存に権限が必要になります。
4. 共通モデル（domain）: 変更は不要です。GLB は画面を開くたびに作り直し、`<tmp>/ar/standee_<imageHash 先頭16桁>_<stage>_<element>.glb` に書き出しています。

## 10. 実機でしか確かめられないこと（QA 用チェックリスト）

- [ ] TLHC（`initSurfaceAndroidView`）の上で、SceneView の TextureView が表示されること。表示されない端末があれば、`ArNativeView.forceHybridComposition = true` で Hybrid Composition に切り替える
- [ ] 平面を見つけたときのヒント → タップで置く → カメラのほうを向く → ドラッグで移動、ピンチで 0.4〜3 倍、ひねりで回転
- [ ] `autoAnimate` で idle のアニメーションがループすること。Lv10 のオーラと Lv20 のきらきらの見え方（BLEND の重なり順）
- [ ] シャッター: AR の写真にカメラ映像と 3D が写ること。かんたん AR の写真で、スプライトの位置がプレビューと合っていること（プレビューと静止画で画角が違う端末があるかもしれない）
- [ ] Android 7〜9 での保存権限、Android 10〜15 では権限なしで保存できること
- [ ] ARCore 未インストール → インストール → アプリに戻る、の流れ。インストールを断ったときにフォールバックすること
- [ ] バックグラウンドに回して戻ったとき（ARCore セッションとカメラの pause・resume）。画面を出入りしたときのメモリ（Filament エンジンの解放）
- [ ] Pixel 8 以降（16 KB ページのカーネル）で起動して AR が動くこと
