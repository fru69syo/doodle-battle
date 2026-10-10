# Before/After 動画の書き出し（Video チーム, v1.1）

SPEC §11.2-1 の実装。紙に描いた絵（Before）が動き出し、バトルで活躍する（After）10〜15 秒の縦型動画を端末内で作り、保護者ゲートの先で保存・共有する。
コード: `app/lib/features/video_export/`、ネイティブ: `app/android/app/src/main/kotlin/com/fru69syo/doodle_battle/video/`。

## 1. 決定事項（ユーザーには確認せず Video チームで決めた）

| 項目 | 決定 | 理由 |
|---|---|---|
| 形式 | H.264 / MP4、720×1280（9:16）、30 fps、約 4 Mbps、**音声なし** | どの SNS でもそのまま投稿できる。音は投稿先のアプリで（各サービスが権利処理済みの曲を）付けられる。著作物の音楽を同梱する危険がない |
| 長さ | 12.0 秒（決着の一撃がそのまま見せ場のとき）／13.4 秒（見せ場 2 回） | 10〜15 秒の範囲（テストで保証） |
| エンコーダー | Android 標準の `MediaCodec` + `MediaMuxer` を小さな Kotlin プラグインで使う | FFmpegKit は 2025 年に終了。標準 API なら追加の .so が無く 16 KB アラインに影響せず、権限も不要。APK も増えない |
| 入力 | Dart で描いた RGBA を 1 フレームずつ渡し、Kotlin で BT.709 リミテッドの YUV 4:2:0 に変換して `getInputImage()`（Flexible YUV）に書く | Surface 入力＋`lockHardwareCanvas` はタイムスタンプを制御できない端末がある。Flexible の Image なら NV12 / I420 のどちらの機種でも同じコードで書ける |
| 小さい端末 | 720×1280 を受け付けるエンコーダーが無ければ 576×1024 で作り直す | 古い機種のエンコーダーは高さ 1088 までのことがある |
| 共有 | `share_plus 13.3.0`（システムの共有シート）、保存は既存の `gal`（MediaStore、Android 10+ は権限不要） | `share_plus` は権限を追加しない（FileProvider だけ） |
| Before 画像 | 撮影時に紙の部分だけを透視補正して保存（長辺 ≤ 1280px、JPEG 品質 85、端末内のみ） | §2 |
| 文言 | 子ども向けはひらがな。じょうずさ・のびのび度・しょぼ・点数は一切出さない（`VideoTexts` をテストで検査） | SPEC §11.1 |
| ストアの一文 | 「かみに かいた え が たたかう！」「Android アプリ「（アプリ名）」」 | 商標（Google Play バッジ）を動画に入れない。変えるときは `VideoTexts` |
| アプリ名 | ロゴ・透かし・ストアの一文は `core/config/app_config.dart` の `appDisplayName` 1 か所から | 改名（「おえかきファイターズ」予定）は 1 行の変更で済む |

## 2. Before 画像（紙の絵）の保存

- `OnDeviceDrawingAnalyzer.analyze()` が解析レポートの紙の四隅（`paperQuad`）とシルエットを使い、**元の写真から**紙の部分だけを切り出す（`before_photo_extractor.dart`、isolate）。解析と同じ透視変換・同じ inset なので、切り抜き画像の位置（`inkRect`、正規化座標）がそのまま写真に重なる。軽いホワイトバランス（紙が白くなる程度、最大 ×1.6）。
- 紙が見つからない（画面いっぱいが紙）とき: `paperLikeness ≥ 0.5` のときだけ、絵の周り（絵の大きさの 20%、最低 24px の余白）を切り出す。紙らしくない写真（顔・部屋が写りうる）は**保存しない**。カメラの全体のフレームは決して保存しない。
- 抽出は誕生演出の間にバックグラウンドで進み（`PendingBirth.beforePhoto`）、名前を付けて保存するときに最大 8 秒待って `CharacterRepository.saveBeforePhoto()` で保存。失敗しても誕生は止めない。
- 保存先: `<documents>/characters/before/<id>.jpg` + `<id>.json`（`inkRect`）。キャラの削除（`delete`）と全データ削除（`deleteAll` がフォルダごと消す）で一緒に消える。サーバーには送らない。
- 以前からいるキャラ（Before 画像なし）: 元の切り抜きを生成した紙（900×1200、紙の繊維とビネット、固定シード）の上に置いて Before にする。

## 3. 動画の構成（`video_timeline.dart` / `video_composer.dart`）

| 時間 | 場面 | 内容 |
|---|---|---|
| 0–3.0 s | ① Before | 机の上の紙の写真（少しずつズーム）。字幕「かみに かいた え が…」（1 文字ずつ） |
| 3.0–6.0 s | ② たんじょう | 絵が光る → 紙から弧を描いて浮き上がり大きくなる（紙には白い抜け跡）→ 属性色のステージと放射線、きらきら → ぴょこぴょこ。字幕「うごきだした！」 |
| 6.0–10.6 s | ③ バトル | 「バトル！」→ ぞくせいわざ（わざ名）→ 命中・ダメージ・「こうかは ばつぐんだ！」→ 決着の一撃でたおす →「かった！」 |
| 末尾 2.8 s | ④ エンドカード | 紙の写真 → キャラ、名前、カラフルな「らくがきバトル」ロゴ、ストアの一文 |

- 場面 ①〜③ は左上に小さく「らくがきバトル」の透かし。場面の切り替えは白いフラッシュ。
- **バトルは本物のエンジンで台本化**（`battle_highlight.dart`）: キャラのぞくせいが有利な CPU（`typeMultiplierPct > neutral`、キャラ ID から決定的に選ぶ）を同じレベルで用意し、プレイヤーはぞくせいわざ（ゲージ満タンならひっさつ）、CPU はたいあたり。シード 1〜48 を順に試し、最初のヒットが「ばつぐん」で KO 勝ちになる最短の試合を採用。ダメージ・HP は実際のイベント（`DamageEvent` など）の値。
- **キャラの絵は Loop の表示画像** `displayImageServiceProvider.displayImageFor(c)`（描き足したパーツ込み）。紙の上にいる間は元の切り抜き（`readImage`）で、浮き上がる途中でパーツ込みの絵に切り替わる。子どもが描いた**わざの絵**（`effectImageFor(c, DrawnMove.element / special)`）があれば、それが回転しながら飛ぶ（無ければ属性色の光の玉）。
- 描画は `dart:ui` の `PictureRecorder` → `Picture.toImage(720, 1280)` → `toByteData(rawRgba)`。乱数は固定シードで、同じ入力なら同じフレーム（テストでバイト一致を確認）。プレビューも同じ `VideoComposer` を `CustomPainter` で描くので、見たものがそのまま動画になる。

## 4. エンコード（`video_encoder.dart` / `VideoEncoderPlugin.kt` / `EncoderSession.kt`）

- チャンネル `doodle_battle/video_encoder`: `start{path,width,height,fps,bitrate}` → `addFrame{rgba}`（エンコードが終わってから返る＝描画側が自然に待つ）→ `finish` → `{path,bytes,durationUs,frames}`、`cancel`。エラーコード `size_unsupported` / `unavailable` / `not_started` / `failed`。
- Kotlin 側は `makeBackgroundTaskQueue()` 上で直列に動くので UI スレッドを止めない。Dart 側は次のフレームを描きながら前のフレームのエンコードを待つ（1 フレーム分の先読み）。
- エンコーダーの選択: `MediaCodecList` から H.264 エンコーダーでサイズと Flexible YUV に対応するもの（Android 10+ はハードウェア優先）。I フレーム間隔 1 秒、BT.709 / リミテッドレンジを `MediaFormat` に明記。
- 進捗 UI「どうがを つくっているよ…」＋進捗バー、「やめる」で中止（ファイルは削除）。
- 出力: `<cache>/video_export/rakugaki_battle_YYYYMMDD_HHMMSS.mp4`（名前に子どもやキャラの名前を入れない。位置情報も書かない）。書き出しの前にフォルダを空にし、画面を閉じたら削除する。

## 5. 保存・共有と保護者ゲート

- 入口: 名前を付けた直後のキャラ詳細（絵の下端に重ねたピンクのボタン「うごく どうがに しよう！」。ページのレイアウトは動かさない）、キャラ詳細の「どうがに する」、バトル結果の「どうがに する」。
- 子どもが作れるのは端末内の動画まで。「おうちのひとに わたす」→ **保護者ゲート** → 保護者向けの注意（「えに なまえや がっこうめいが かいていないか かくにんしてね」＋漢字の説明: 顔・声・部屋は入らないこと、名前・学校名・住所が絵に書かれていないかの確認）→「確認しました」のあとで初めて「ギャラリーに保存」「共有する」が出る。ゲートは画面を開いている間 1 回だけ。
- 子どもの顔・声は入らない（入力は紙の部分の写真と切り抜きだけ。音声トラックなし）。

## 6. 変更した共有ファイル

- `pubspec.yaml`: `share_plus: 13.3.0` を追加（権限なし。マージ後のマニフェストに FileProvider と receiver が入る）。
- `core/config/app_config.dart`: `appDisplayName` を追加。
- `MainActivity.kt`: `VideoEncoderPlugin()` の登録 1 行。Gradle・`AndroidManifest.xml` の変更なし。
- `lib/data/`: `before_photo.dart`（新規）、`CharacterRepository` に `saveBeforePhoto` / `readBeforePhoto`（File / InMemory 実装、`delete` で一緒に削除）。
- `drawing_services.dart`（`AnalysisOutcome.beforePhoto`）、`draw_flow.dart`、`pending_birth.dart`、`naming_screen.dart`（保存と `justBornCharacterProvider`）、`character_detail_screen.dart`・`battle_result_screen.dart`（ボタン）。
- `dart_test.yaml`: タグ `video_frames`（通常はスキップ）。

## 7. テストと確認用ツール

- `test/features/video_export/`: タイムライン（長さ 10〜15 秒・場面・ビート・禁止語）、バトル台本（全ぞくせいで「ばつぐん」と KO、エンジンの再生と一致、決定性）、Before 画像（紙だけ・≤1280・縦横比・紙の無い写真は保存しない・リポジトリの保存と削除）、レンダラー（720×1280／576×1024 の不透明 RGBA、決定性、場面ごとに違う絵、フォールバック、描いたわざの絵、パーツ込みの絵）、エンコーダーのチャンネル契約（フェイクのプラットフォーム側）とエクスポーター（順番・進捗・サイズのフォールバック・中止・失敗）、画面（ゲート → 注意 → 保存・共有、ゲート拒否、注意の取り消し、エンコーダー非対応、誕生からの入口、結果画面の入口）。
- フレームの確認: `tool/video_frames.sh [出力先] [--all]` が見本の動画（合成した子どもの絵の写真から本物の解析を通したもの）のフレームを PNG に書き出す。`--all` なら全フレームなので `ffmpeg -framerate 30 -i photo_t%05d.png` などで動きを見られる。

## 8. 実機でしか確かめられないこと

- 各社のハードウェアエンコーダーでの YUV の向き・色（Flexible Image のストライド対応は実装済み）、`getInputImage` が null を返す機種がないか。
- 書き出しにかかる時間（目安: 402 フレーム × (描画＋読み出し＋変換)。中位機で 10〜20 秒を想定）と発熱、書き出し中にアプリを離れたときの挙動。
- ギャラリー保存（Android 7〜9 の権限ダイアログ）と共有シートで LINE / Instagram / TikTok などが MP4 を受け付けるか。
- 実際の紙の写真での Before の切り出し（紙の検出が外れたときの余白の大きさ）。
