# App/UI（feat/ui）

SPEC §2 の体験を 1 本のアプリにまとめる層。画面・ナビゲーション・ローカル保存・保護者機能・各チームのモジュールの統合を担当する。
数値やルールは持たない（バトルは `domain/battle`、解析は `features/drawing_analysis`、NG ワードは `shared/ng_words` が正）。

## 1. 構成

```
lib/
  main.dart                 起動: 縦固定、ライセンス登録、Firebase 初期化（未設定なら offline）、ProviderScope
  app.dart                  MaterialApp.router（テーマ、ja ロケール、文字倍率は最大 1.3）
  firebase_options.dart     プレースホルダー（§5）
  core/                     テーマ、router、共通ウィジェット、サービス provider
  data/                     リポジトリ（キャラ・設定・進み具合）、app_state（Riverpod notifier）、backend/
  features/
    onboarding/ home/ draw/ birth/ collection/ battle_ui/ online/ parent/
    parental_gate/ monetization/ ng_filter/  （+ 既存の drawing_analysis/ ar/）
```

- 状態管理は Riverpod 3（`AsyncNotifier`）、画面遷移は go_router。
- テストで差し替える seam はすべて `core/providers.dart` の provider: リポジトリ、`BackendApi`、`MonetizationService`、`ParentalGate`、解析（`DrawingAnalyzerService`）、画像入力（`DrawingImageSource`）、時計、乱数、spec/roster/NG 辞書。

## 2. ルート

| パス | 画面 |
|---|---|
| `/splash` | 設定の読み込み中 |
| `/setup` | 初回の保護者セットアップ（ゲート → 説明と同意 → 完了）。ポリシー版が上がったときも再表示 |
| `/` | ホーム（かく / ずかん / バトル / オンライン※ / おうちのひと） |
| `/draw` | 撮影 or アルバム → 端末内解析 →（許可時）クラウド判定 |
| `/birth` → `/birth/name` | 誕生演出 → 名前（オフライン NG フィルタ） |
| `/zukan`, `/zukan/:id`, `/zukan/:id/ar` | 一覧、詳細（Lv・XP・進化・パワーのたね・わざ）、AR |
| `/battle`, `/battle/:id/stages`, `/battle/:id/stage/:n`, `/battle/result` | キャラ選択、ステージ 1–30、CPU 戦、結果 |
| `/online`, `/online/queue/:id`, `/online/match/:matchId?c=:id` | ロビー（Lv5+）、審査とマッチング、対戦 |
| `/parent` | おうちのひと（ゲートを通ったときだけ。離れると再ロック） |

すべてのルートは `/` の子なので、どこからでも戻るとホームに着く。リダイレクトは `redirectFor()`（純関数・テスト済み）。

## 3. ローカル保存（`lib/data/`）

- `CharacterRepository`（interface）/ `FileCharacterRepository`（`<documents>/characters/<id>.json` + `<id>.png`、JSON は一時ファイル→rename で書く、壊れたファイルは飛ばす、id は `[A-Za-z0-9_-]{1,64}`）/ `InMemoryCharacterRepository`。
- `SettingsRepository`: `settings.json`（同意・プレイ時間・購入権のキャッシュ・最後にサーバーへ送った同意）と `progress.json`（クリア済みステージ、適用済みオンライン対戦 ID（最新 100 件）、今日のプレイ秒数、オンライン登録時の Lv）。
- ずかんの上限: 12 体。`slots_24` の購入権があれば 36 体（`collectionLimitProvider`）。

## 4. 画面ごとの決定事項

- **保護者ゲート**（`features/parental_gate/`）: 3 秒長押し（離すとリセット）→「23 × 7 ＝ ？（二十三 かける 七）」をテンキーで入力。左項は 11–99（10 の倍数を除く）、右項 3–9。3 回間違えると閉じる。`ParentalGate.verify(context)` を Compliance も使える。ゲートの文言は保護者向けなので漢字。
- **同意の初期値はすべて OFF**。クラウド判定・オンラインは Firebase 未設定のとき「現在準備中」で操作不可。
- **かく**: image_picker（最大 2048px, 品質 92）。空っぽの絵は「もうすこし かいてみよう」、読めない画像は「しゃしんが よめなかったよ」。ずかんが満杯なら撮影前に案内する。
- **クラウド判定**: 許可済みかつサーバーありのときだけ。20 秒で打ち切り、失敗・`appropriate:false`・600KB 超は黙って端末の結果を使う（不適切判定の結果は名前候補も含めて一切使わない）。成功時は `applyCloudSkill`、`subject`・わざ名を保存、`suggestedNames` を候補の先頭に出す。
- **たんじょう**: 4.2 秒の演出（たまごが揺れる → 登場 → ステータスが 1 本ずつ → ぞくせい・わざ → しょぼ時のメッセージ）。タップで飛ばせる。しょぼキャラは「げいじゅつか すぎて しょぼキャラに なっちゃった！」＋「そだつのが Nばい はやい」（N = spec の `shoboLevelUpStatPct / levelUpStatPct`、現在 3）。
- **名前**: サーバーと同じ規則（NFKC、1–10 文字、ひらがな/カタカナ/ー/・/英数/漢字、数字 2 個まで）＋ NG 辞書。候補はクラウドの名前 → 画像ハッシュから決まるプリセット名（サーバーと同じ 24 語）。
- **ずかん詳細**: HP は `hp × hpMultiplier` で表示。パワーのたねは各ステータスの「＋」で 1 個ずつ（`allocateSeed`）。「おわかれ する」は確認つき。進化: かがやき＝属性色のオーラ、でんせつ＝金の枠。
- **AR**: `ArViewScreen(allowArCoreInstallPrompt: false)`。ARCore のインストール案内は「おうちのひと → AR の準備」だけ（ゲートの先）。
- **CPU 戦**: ステージ表は spec、CPU は `loadCpuRoster()` + `cpuFighterSetup()`。ステージ一覧は「おすすめ Lv」（`recommendedLevel`）と強さ（よわい/ふつう/つよい）を表示し、クリア済み +1 まで開放。エンジンのイベントを順に再生（攻撃側がぴょこっと跳ねる、被弾側が揺れてダメージ数字が浮く、相性はバナー、まもるは盾アイコン、たおれると傾いて薄くなる）。乱数は seed から `deriveSeed(seed,0)`（バトル）/`(seed,2)`（CPU AI）。
- **結果**: XP（`applyXp`）、レベルアップ、たね、進化を表示して保存。勝てば次のステージへ。
- **オンライン**: ホームのボタンは保護者が許可したときだけ表示（未設定なら「じゅんびちゅう」で押せない）。ロビーは Lv5 以上のみ選べる。未登録・登録後に Lv が上がったキャラは `registerCharacter` で審査し直す（`SNAPSHOT_NOT_ACTIVE` でも再登録）。不合格理由は全 14 種をやさしい文に対応付け（`online_messages.dart`）、名前の不合格ではサーバーのプリセット名から選んで再審査（ローカルの名前もその名前になる）。待機中は 10 秒ごとに `joinQueue`（ハートビート）、やめると `leaveQueue`。対戦は `matches/{id}` を購読し、ターンが進んだら `turns/{n}` のイベントを再生。20 秒タイマー、0 になったら `pollMatch`、送信後は 5 秒ごとに `pollMatch`。終了時は `result[mySide].xp` を matchId 単位で 1 回だけ適用。通報は旗ボタン → 6 つの理由から選ぶ（自由入力なし）。相手の絵は Storage から読む（読めなければ属性アイコン）。
- **おうちのひと**: 同意 4 種、プレイ時間の目安（なし/30/60/90/120 分。超えるとホームに「そろそろ おやすみ しよう」。前面にいた時間を resume〜pause で数える。タイマーなし）、AR の準備、ショップ、サポート ID（サインイン済みのとき）、すべてのデータを削除、プライバシーポリシー（URL はプレースホルダー）、ライセンス（フォントの OFL を `LicenseRegistry` に登録済み）。
- **全データ削除**: 確認 → サーバーがあれば `deleteMyData`（未サインインなら何もしない）→ 失敗なら端末のデータは消さずに再試行を案内 → 端末のキャラ・設定・進み具合を削除 → セットアップに戻る。

## 5. Firebase（オフライン動作とセットアップ）

- 使用パッケージ: firebase_core, firebase_auth（匿名）, cloud_functions（`asia-northeast1`）, cloud_firestore（match/turn の読み取り・同意の書き込み）, firebase_storage（相手の絵の読み取り）, firebase_app_check（Play Integrity、debug ビルドは debug provider）。
- **google-services の Gradle プラグインは使わない**。`lib/firebase_options.dart` から `Firebase.initializeApp(options:)` する。
- 今はプレースホルダーで、`currentPlatform` が `UnsupportedError` を投げる → `initBackend()` が `UnavailableBackendApi` を返し、オンラインとクラウド判定は「じゅんびちゅう」で無効。初期化の失敗も同じ扱いで、落ちない。
- **サーバーに触れるタイミング（PM 決定）**: 起動時は `Firebase.initializeApp` だけ（通信なし）。App Check の有効化と匿名サインインは最初のサーバー呼び出しで行い、呼び出しは保護者がクラウド判定かオンラインを ON にしたときだけ起こる（`SettingsController.ensureConsentSynced`）。最後に送った同意を `settings.json` に保存し、同じ内容は二度と送らない。両方 OFF に戻したときは、サーバー側でオンラインのキャラを非公開にするため、撤回を **1 回だけ** 書き込む（以後は通信なし。サインアウトはしない）。
- 本物のプロジェクトをつなぐ手順:
  ```bash
  dart pub global activate flutterfire_cli
  cd app
  flutterfire configure --project=<firebase-project-id> --platforms=android \
    --android-package-name=com.fru69syo.doodle_battle --out=lib/firebase_options.dart
  # flutterfire が google-services の Gradle プラグインを足そうとしたら入れない（不要）
  ```
  そのあと Firebase コンソールで匿名認証、App Check（Play Integrity・debug トークンの登録）、Functions/Firestore/Storage を docs/BACKEND.md §14 のとおり設定する。CI/リリースでは `scripts/write_firebase_config.sh` がシークレットからこのファイルを書く。プレースホルダーには `demo-doodle-battle` の文字が入っているので、`--require`（リリース）では弾かれる。
- マニフェスト: Firebase が持ち込む `c2dm.permission.RECEIVE`（firebase-iid）と `READ_GSERVICES`（recaptcha）は使わないので `tools:node="remove"` で外した（`scripts/check_release.sh` の許可リストに合わせる）。

## 6. 収益化のフック（Compliance が実装を差し込む）

- `MonetizationService`（`features/monetization/monetization_service.dart`）: `rewardedAdReady`/`showRewardedAd()`、`storeAvailable`/`purchase(Product)`/`restorePurchases()`、`entitlements`（Stream）。既定は `NoopMonetizationService`（広告なし・ストアなし）。`monetizationServiceProvider` を override する。
- 商品 ID（仮）: `slots_24`、`frame_pack_1`、`ouen_pass`。購入権はストリームから `settings.entitlements` にキャッシュされ、`slots_24` でずかんが 36 体、`ouen_pass` で結果画面の「おうえんパスで けいけんち 2ばい」（広告なし）。フレームパックの見た目は未実装（フックのみ）。
- 結果画面の「どうがを みて けいけんち 2ばい」: 広告が許可されているときだけ表示 → 必ず「おうちのひとに きいてから みてね / こうこくが ながれるよ」を出し、「みる」を押したときだけ `showRewardedAd()`。報酬は `xpForBattle(adBoost)` との差分を加算（1 バトル 1 回）。
- ショップ: 課金が許可されているときだけ「おうちのひと」に表示。「おかねが かかるよ。おうちのひとと いっしょに かってね」を常に表示し、**購入ボタンごとに保護者ゲートをもう一度**通す。

## 7. NG フィルタ（`features/ng_filter/`）

- `normalize.dart` / `ng_filter.dart` は `firebase/functions/src/ngwords/*.ts` の移植。NFKC は `unorm_dart`（Unicode 17）。
- 辞書は `app/assets/ng_words/ng_words.json`（`shared/ng_words/ng_words.json` のバイト単位のコピー）。更新は `cd app && dart run tool/sync_ng_words.dart`。ずれるとテストが落ちる。
- `normalize_vectors.json`（48 件）と `ng_check_vectors.json`（74 件）を `shared/` から直接読んで全件テスト。

## 8. テスト

`flutter test --concurrency=2`。UI 側は 193 件（NG ベクトル 128 を含む）:
リポジトリ（ファイル/メモリ）、保護者ゲート（長押し・正解・3 回ミス・取消）、誕生フロー（通常/しょぼ/空っぽ/読めない/NG 名/クラウド成功・失敗・未許可/満杯/購入で 36 体）、CPU 戦（決定性、イベント適用、1 戦通し、ロック、広告 2 倍、しょぼの XP）、同意ゲーティング（セットアップ、オンライン・広告・ショップ・おうちのひと、同意の同期、全削除）、オンライン（不合格メッセージ全種、登録→待機→対戦→XP 1 回、通報、ハートビート）、アプリ全体のハッピーパス（実ゲート → かく → 誕生 → バトル → レベルアップ → たね）。
ウィジェットテストは `test/support/harness.dart` の `pumpApp()` でアプリ全体をフェイク付きで起動する（端末サイズ 393×851dp）。
