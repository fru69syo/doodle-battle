# Compliance & Monetization（feat/compliance）

SPEC §7 の実装と、Google Play「ファミリー」ポリシー・AdMob・Play Billing への対応をまとめる。
決めたことは §1 に理由と一緒に書き、オーナーの作業は §8、PM に確認したいことは §9 にある。
出典は §10（2026-10-09 に確認）。

| 項目 | どこ |
|---|---|
| 収益化のロジック（広告・購入・購入権） | `app/lib/features/monetization/app_monetization_service.dart`（+ `gateways.dart` の seam、`admob_gateway.dart`、`play_store_gateway.dart`） |
| 結果画面の広告ボタン、1 日の上限 | `features/monetization/rewarded_ad_button.dart`、`GameProgress.adBoostsToday` |
| ショップ（価格・確認・復元） | `features/monetization/shop_section.dart` |
| 設定 ↔ SDK の同期（広告の同意、購入権のキャッシュ、クラッシュの同意） | `features/monetization/monetization_sync.dart` |
| フレームパックの見た目と選択 | `features/monetization/card_frames.dart`、`core/widgets/character_picture.dart`、ずかん詳細の「カードの わく」 |
| Crashlytics（オプトイン） | `core/crash_reporting.dart`、`res/values/crashlytics.xml`、マニフェストの `firebase_crashlytics_collection_enabled=false` |
| 外部 ID・URL（1 ファイル） | `app/lib/core/config/app_config.dart` |
| オンラインの表示名 | `features/online/display_name_picker.dart`、語彙は `shared/names/display_name_words.json` |
| ポリシーのページ | `site/`（`scripts/build_site.py`、`.github/workflows/pages.yml`） |
| リリースの検査 | `scripts/check_release.sh`（AdMob・Crashlytics の検査を追加）、`scripts/write_firebase_config.sh`（プレースホルダーの検出）+ `scripts/test_write_firebase_config.sh` |

---

## 1. 決定事項（Compliance チームが決めたこと）

| # | 決定 | 理由 |
|---|---|---|
| C1 | 広告は**リワード広告だけ**。保護者が許可するまで SDK を**初期化しない**（`MobileAds.initialize()` は最初に許可されたときに 1 回だけ）。許可を取り消すと読み込み済みの広告を破棄する | SPEC §7。子どもに同意なしで広告 SDK の通信をさせない |
| C2 | すべてのリクエストに `ageRestrictedTreatment = child`、`tagForChildDirectedTreatment = yes`、`tagForUnderAgeOfConsent = yes`、`maxAdContentRating = G`、`AdRequest(nonPersonalizedAds: true)`。メディエーションは初期化しない | `tagForChildDirectedTreatment` は SDK で非推奨になり `ageRestrictedTreatment` が後継。両方の信号があると SDK は最も厳しい扱いにするので、両方を設定した（§10 [A1]） |
| C3 | `AD_ID` と Privacy Sandbox の 3 権限（`ACCESS_ADSERVICES_AD_ID / ATTRIBUTION / TOPICS`）をマニフェストで `tools:node="remove"`。`DELAY_APP_MEASUREMENT_INIT=true` | 子ども向けアプリは広告 ID を送ってはいけない（[F1][F2]）。`check_release.sh` がどれか 1 つでも残っていたら失敗する |
| C4 | 広告で経験値 2 倍にできるのは **1 日 3 回**（端末の日付で数える、`dailyAdBoostCap`）。こうこくなしパス（`no_ads_pass`）は広告なしで 2 倍になるが、**同じ 1 日 3 回の上限**を共有する（SPEC §11.4: お金を払うと早く強くなる、という差を作らない） | 広告の見すぎを防ぐ（Teacher Approved の評価観点「しつこい広告」）。上限に達したら「きょうの どうがは おしまい。また あした みてね」 |
| C5 | 広告の読み込みに失敗したら、ボタンを消して「いまは どうがが ないみたい。また こんど みてね」。再試行は 1 分あけて、結果画面を開いたときに行う | オフラインや在庫切れで子どもを待たせない・連打させない |
| C6 | 商品は 3 つとも**買い切り（消費しない）**: `slots_24`、`frame_pack_1`、`no_ads_pass`。価格は Play Console で決め、アプリは**ストアから取得した価格**だけを表示する（取得できないと「買う」は押せない） | SPEC §10・§11.4（パスは買い切り）。価格をアプリに書かないので、価格改定でアプリの更新が要らない |
| C7 | 購入ごとに: 保護者ゲート → 確認ダイアログ（商品名・**価格**・「1回だけの購入（定期購入ではありません）」・「おかねが かかるよ。おうちのひとと いっしょに かってね」）→ Google Play の購入画面 | SPEC §7、ファミリーポリシー（仮想通貨と現金の区別、強引な誘導の禁止） |
| C8 | 購入権を付けるのは Play の状態が **PURCHASED** のときだけ。**PENDING**（コンビニ払いなど）では付けず、確認（acknowledge）もしない。確認に失敗しても購入権は付け、次の「復元」で確認し直す | Play Billing の要件（3 日以内に確認しないと自動返金）[B1]。in_app_purchase_android は復元した PENDING の購入も `restored` として返すので、`PlayStoreGateway` が Play の purchaseState で上書きする |
| C9 | 起動時に毎回、静かに「復元」（Play の所持リストの取得）を行い、**その結果を正とする**（返金された商品は消える）。ストアに届かないときはキャッシュ（`settings.entitlements`）を使い続ける | オフラインでもずかんの枠などが使える。返金・別アカウントにも正しく追従する |
| C10 | v1 は**サーバーでの購入の検証をしない**（Firebase なしで課金が動く） | 下の §3.3 のリスクを受け入れる。v1.1 で検証を足す |
| C11 | 「すべてのデータを削除」のあと、購入は Play から復元してキャッシュに戻す | 購入記録は保護者の Google アカウントのもので、こちらのデータではない |
| C12 | フレームパックの枠（ほし・はな・にじ）は**端末の中だけ**（サーバーに送らない）。パックを持っていないときは、選択の UI も見せない（子どもに購入を勧めない） | 見た目だけのアイテム。Teacher Approved の観点で、子どもの画面に課金の案内を出さない |
| C13 | Crashlytics は**初期設定オフ**。「ふぐあいの じょうほうを おくる」（おうちのひと・初回セットアップ）をオンにしたときだけ、`setCrashlyticsCollectionEnabled(true)`。オフにすると未送信のレポートも削除。Firebase が未設定なら「準備中」で押せない | SPEC §7（Crashlytics だけ使う）、RELEASE §7-4 の PM 判断事項を「任意（保護者の許可制）」で実装。データセーフティで「任意」と申告できる |
| C14 | Crashlytics の **Gradle プラグインは使わない**。代わりに `com.google.firebase.crashlytics.RequireBuildId=false` を resource で設定 | プラグインなしで Firebase を設定すると Crashlytics SDK は起動時に「build ID が無い」と例外でアプリを止める（[C1]）。google-services.json なしでビルドできる方針（UI.md §5）を守る。難読化の対応表のアップロードは任意（§4） |
| C15 | 外部 ID と URL は `app/lib/core/config/app_config.dart` にまとめ、ビルドごとに違う値は `--dart-define`（`ADMOB_REWARDED_UNIT_ID`、`POLICY_BASE_URL`）。AdMob の **App ID** はマニフェストに必要なので Gradle の `ADMOB_APP_ID`（Gradle プロパティか環境変数）→ `manifestPlaceholders`。どちらも既定値は Google の**テスト ID** | 開発・CI・フォークでは何も設定しなくてもテスト広告で動き、リリースでは本物の ID がないと失敗する（`check_release.sh --require-real-admob`、release.yml） |
| C16 | ポリシーのページ（プライバシー・規約・削除・サポート）は `site/`。アプリからはおうちのひと（と初回セットアップの同意画面）でだけ開く（外部ブラウザ） | ファミリーポリシー: アプリの外へ出るリンクは保護者ゲートの先 |
| C17 | オンラインの表示名の語彙を `shared/names/` に移し、サーバー（vendor）とアプリ（asset のバイト単位のコピー + ずれ検出テスト）で共有 | ng_words と同じ方式。ID は再利用・付け替え禁止 |
| C18 | `ParentConsents` に `crashReports` を追加したが、ポリシー版（`currentPolicyVersion`）は 1 のまま | まだ公開前で、公開するポリシーが版 1 になるため |

## 2. 広告（AdMob）

### 2.1 流れ
```
設定の ads 同意 ──► monetizationSyncProvider ──► setAdsAllowed(true)
                                                    └─(初回だけ) updateRequestConfiguration(子ども向け) → disableMediationInitialization → initialize
                                                    └─ RewardedAd.load(unit, AdRequest(nonPersonalizedAds: true))
結果画面 ──► 上限チェック（GameProgress）──► 「どうがを みて けいけんち 2ばい」（読み込み中は押せない／失敗なら案内）
        ──► 注意書き「おうちのひとに きいてから みてね / こうこくが ながれるよ」──► みる ──► show() ──► 最後まで見たら XP 差分を加算 + 回数を記録
```
- 1 バトルに 1 回。
- **こうこくなしパス**（SPEC §11.4）を持っていると: 広告の入口（結果画面の広告ボタン・注意書き）を出さず、`monetizationSyncProvider` が `setAdsAllowed(false)` にするので**広告 SDK も初期化・読み込みしない**（保護者が広告を許可していても）。結果画面は「こうこくなしパスで けいけんち 2ばい」→ 押すとすぐ 2 倍。回数は広告と同じ `GameProgress.adBoostsToday` に数え、**1 日 3 回まで**（上限では「きょうの 2ばいは おしまい。また あした ね」）。おうちのひとの「広告の視聴」スイッチは押せなくなり、理由を表示する。返金されてパスが無くなると、広告の許可の設定どおりに戻る。
- 子どもが押さない限り広告は出ない（起動時・画面遷移時のインタースティシャルやバナーは無い）。リワード広告は 5 秒以内に閉じられる形式（Google 側）。

### 2.2 マニフェストとビルド
- `com.google.android.gms.ads.APPLICATION_ID = ${admobAppId}`（`build.gradle.kts`。形式 `ca-app-pub-<16桁>~<10桁>` 以外はビルドを止める）。
- `AD_ID`・`ACCESS_ADSERVICES_*` を remove、`DELAY_APP_MEASUREMENT_INIT=true`。
- `MobileAdsInitProvider`（SDK の ContentProvider）はマニフェストに残る。これは App ID を確認するためのもので、SDK の初期化（広告の通信）は `initialize()` まで行わない想定。**実機で「許可前に広告ドメインへの通信がない」ことを QA で確認する**（QA_CHECKLIST 8.9）。
- 確認結果（2026-10-09、debug 鍵で署名した release AAB）: `check_release.sh` 合格。マージ後のマニフェストの権限は CAMERA、WRITE/READ_EXTERNAL_STORAGE（maxSdk 28）、INTERNET、ACCESS_NETWORK_STATE、BILLING、WAKE_LOCK、FOREGROUND_SERVICE だけ。AD_ID なし。警告はテストの App ID の 1 件だけ。

### 2.3 AdMob 側の設定（オーナー）
- ブロックの管理 → 最大の広告コンテンツのレーティング **G**、センシティブなカテゴリをすべてブロック。
- アプリの設定で「児童向け」の扱い（Families）を設定（コードでも設定済み）。
- `app-ads.txt`（§5.3）。

## 3. アプリ内購入（Play Billing）

### 3.1 実装
- `in_app_purchase` 3.3 / `in_app_purchase_android` 0.5（**Play Billing Library 8.0.0**。2026-08-31 以降、新規アプリと更新は 8 以上が必須 [B2]）。
- `AppMonetizationService`: `refreshStore()`（可用性と商品・価格）、`purchase()`（`buyNonConsumable` → `purchaseStream` の結果を待つ。15 分で `pending` 扱い）、`restorePurchases()`（`queryPastPurchases`）、`entitlements` ストリーム → `settings.entitlements`（オフライン用のキャッシュ、`collectionLimitProvider` などが使う）。
- 状態ごとの扱い: purchased/restored → 付与 + acknowledge、pending → 何もしない（支払いが済むと stream に purchased が来る）、canceled → 「キャンセルしました」、error → 「購入できませんでした」。
- テスト: `test/features/monetization/app_monetization_service_test.dart`（フェイクの gateway で 23 件）、`monetization_ui_test.dart`（ショップ・広告ボタン・同期・フレーム）。

### 3.2 Play Console で作る商品（オーナー）
| 商品 ID | 種類 | 名前（案） | 価格（案・PM 判断） |
|---|---|---|---|
| `slots_24` | アプリ内アイテム（1 回限り） | ずかんの ほぞんわく +24 | 250 円 |
| `frame_pack_1` | 同上 | カードの フレームパック | 160 円 |
| `no_ads_pass` | 同上 | こうこくなしパス（説明:「こうこくを みないで けいけんち 2ばい（1にち 3かいまで）」） | 320 円 |
- Play Console → 収益化 → 商品 → アプリ内アイテム。ID は**あとから変えられない**ので上の綴りのまま。説明文は保護者向けに、「1 回だけの購入」と書く。
- ライセンス テスター（設定 → ライセンス テスト）に QA のアカウントを登録し、テストカード（常に承認／常に拒否／遅れて承認＝pending）で QA_CHECKLIST §8 を行う。

### 3.3 v1 のリスク（サーバーでの検証なし）と v1.1 の計画
**リスク**: 改造したアプリや root 化した端末では、購入権を端末内で偽装できる。被害は「その端末で有料の見た目・枠・経験値ブーストが使える」ことに限られ（サーバーの対戦結果やほかのユーザーには影響しない。経験値はもともと端末内の値で、サーバーは統計的な上限で検査している: BACKEND §8）、売上の損失も小さい。Google も「バックエンドでの検証を強く推奨」としているため [B1]、v1.1 で対応する。

**v1.1 の計画**:
1. Cloud Function `verifyPurchase({productId, purchaseToken})`（App Check 必須、匿名認証）。サーバーのサービスアカウントで **Google Play Developer API** `purchases.products.get`（または `purchases.productsv2`）を呼び、`purchaseState=0`・`acknowledgementState`・`obfuscatedExternalAccountId` を確認 → `users/{uid}/entitlements/{productId}` に保存 → サーバー側で `purchases.products.acknowledge`。
2. **Real-time developer notifications**（Pub/Sub）で返金・取り消し（voided purchases）を受け取り、購入権を外す。
3. アプリは `purchaseToken` を送るだけにし、購入権はサーバーの値をキャッシュする。ただし Firebase の利用には保護者の同意が要る（SPEC §10）ので、「購入するとサーバーで確認します」をショップの説明とプライバシーポリシーに追加し、データセーフティの「購入履歴」を「収集する」に変える（STORE_LISTING §6.2 ※3）。
4. それまでの間も、`check_release.sh` と R8 で改造の手間を上げ、Play Integrity（App Check）はサーバー機能で使い続ける。

## 4. Crashlytics

- `firebase_crashlytics` 5.4（Android SDK は Firebase BoM 経由）。マニフェストで `firebase_crashlytics_collection_enabled=false`（[C2]）。保護者がオンにすると `setCrashlyticsCollectionEnabled(true)`（ネイティブ側に保存される）、オフ・データ削除で `false` + `deleteUnsentReports()`。
- Flutter のエラー（`FlutterError.onError`、`PlatformDispatcher.onError`）は、オンのときだけ `recordFlutterFatalError` / `recordError` で送る。
- Firebase が未設定（プレースホルダーの `firebase_options.dart`）なら Crashlytics は作らない（`NoopCrashReporter`）。Firebase を設定しても**匿名サインインはしない**（Crashlytics はサインイン不要）。
- **Gradle プラグインなし**（C14）。そのため R8 の `mapping.txt` と Dart のシンボル（`--split-debug-info`）は自動ではアップロードされない。必要になったら、release.yml の Artifact から手で:
  ```bash
  firebase crashlytics:symbols:upload --app=<Firebase Android App ID> build/symbols   # Dart（--obfuscate の対応表）
  ```
  Java/Kotlin の難読化を戻したくなったら Crashlytics Gradle プラグイン（`com.google.firebase.crashlytics`）を足してもよい（google-services.json は不要。`RequireBuildId=false` は残してよい）。
- **Analytics は使わない**。`check_release.sh` が Analytics のコンポーネントを見つけたら失敗するのは従来どおり。新たに「Crashlytics があるのに `firebase_crashlytics_collection_enabled` が false でない」場合も失敗する。

## 5. ポリシーのページ（`site/`）

### 5.1 中身
| ファイル | 内容 |
|---|---|
| `index.html` | サポート・よくある質問（保護者ゲートの開き方、課金・広告・オンライン・データ・プレイ時間・AR）、問い合わせ先 |
| `privacy.html` | プライバシーポリシー（子どものプライバシーへの配慮、取得する情報の表、委託先: Google/Firebase・AdMob・Anthropic、外国にある第三者（米国）、保存期間、保護者の権利、安全管理、変更、問い合わせ） |
| `terms.html` | 利用規約（保護者の役割、課金・返金・未成年者の取消し、広告、絵の権利と表示の許諾、禁止事項、免責、準拠法） |
| `delete.html` | アカウントとデータの削除（Play の要件: アプリ名とデベロッパー名、アプリ内の手順、**アプリを使わずにメールで依頼する方法**、削除されるデータ・残るデータと期間）[P1] |
| `app-ads.txt` | AdMob の app-ads.txt（`{{ADMOB_PUBLISHER_ID}}`） |
| `style.css` | スマートフォン向けの CSS（Web フォント・スクリプト・解析・Cookie なし） |

- `{{DEVELOPER_NAME}}`・`{{SUPPORT_EMAIL}}`・`{{ADMOB_PUBLISHER_ID}}` は公開時に `scripts/build_site.py --out _site --var ...` が置き換える。値が無い・形式が違うと失敗し、置き換え忘れは公開されない。
- `build_site.py --check`（PR でも実行）: 全ページの `lang="ja"`・viewport、`<script>` と外部の画像・スタイルの禁止、リンク切れ・アンカー切れ、未知のプレースホルダー。アプリが開くページ（`PolicyPage`）が `site/` にあることは Flutter のテストでも確認。
- アプリ内の URL: `POLICY_BASE_URL`（既定 `https://fru69syo.github.io/doodle-battle/`）+ `privacy.html` などのファイル名。

### 5.2 公開の方法
**A. このリポジトリの GitHub Pages**（`.github/workflows/pages.yml`）: private リポジトリの Pages は**有料プラン**が必要（RELEASE §1.10）。使えるなら: Settings → Pages → Source を「GitHub Actions」、リポジトリ変数 `DEVELOPER_NAME`・`SUPPORT_EMAIL`・`ADMOB_PUBLISHER_ID` を設定し、`PAGES_ENABLED=true`。`main` で `site/` が変わるたびに公開される。

**B. 別の public リポジトリ（無料・推奨）**: `fru69syo/fru69syo.github.io`（ユーザーサイト）を作り、
```bash
python3 scripts/build_site.py --out /tmp/_site --var DEVELOPER_NAME='…' --var SUPPORT_EMAIL='…' --var ADMOB_PUBLISHER_ID='pub-…'
# fru69syo.github.io の clone で
mkdir -p doodle-battle && cp /tmp/_site/*.html /tmp/_site/style.css doodle-battle/
cp /tmp/_site/app-ads.txt ./app-ads.txt          # ← ドメインの直下（§5.3）
git add -A && git commit -m "おえかきファイターズ: policy pages" && git push
```
Settings → Pages → Deploy from a branch（`main` / root）。URL は A と同じ `https://fru69syo.github.io/doodle-battle/…` になるので、アプリの既定値のままでよい。別のドメインにするなら release の変数 `POLICY_BASE_URL` を設定する。

### 5.3 app-ads.txt
AdMob は Play に登録した「ウェブサイト」の**ドメインの直下**（`https://fru69syo.github.io/app-ads.txt`）を読む。A（プロジェクトサイト）では `/doodle-battle/app-ads.txt` にしか置けないため、**app-ads.txt だけは B のユーザーサイトの直下に置く**必要がある。Play Console の「ウェブサイト」は `https://fru69syo.github.io/doodle-battle/` のままでよい（AdMob はホスト名で探す）。

## 6. オンラインの表示名

- ロビーの上に「オンラインの なまえ」カード → 「かえる」→ 形容詞 30 語・名詞 30 語から選ぶ（プレビュー付き）→ 「これに する」で `setDisplayName({adjectiveId, nounId})`。サーバーが組み立てた文字列を `GameProgress.displayName` に保存して表示する。自由入力は無い。
- 初回登録でサーバーが自動で付けた名前（`registerCharacter` の応答の `displayName`）も保存して表示する（その場合 ID は空）。
- 語彙は `shared/names/display_name_words.json` が正。サーバーは `sync-shared.mjs` で `src/vendor/names/` にコピーして使い、アプリは `app/assets/names/` にバイト単位のコピー（`dart run tool/sync_shared_names.dart`、ずれると `display_name_test.dart` が失敗）。**ID の再利用・付け替えは禁止**（保存済みの表示名が別の言葉になる）。

## 7. リリースの安全装置

- `write_firebase_config.sh --require`: 次のどれかに当てはまる `firebase_options.dart` を拒否する — マーカー `DOODLE_BATTLE_FIREBASE_PLACEHOLDER`（UI チームのプレースホルダーと CI のスタブの両方に入れた）、`projectId` が `demo-` で始まる、Android の `FirebaseOptions` が無い、Android の appId が無い・全部 0。`scripts/test_write_firebase_config.sh`（12 件、CI の android ジョブ）。
- `check_release.sh`: AdMob の App ID の形式、`--require-real-admob`（release.yml で使用。テスト ID なら失敗）、`DELAY_APP_MEASUREMENT_INIT` が true でなければ失敗、Ads SDK があるのに App ID が無ければ失敗、Crashlytics のオプトインの検査。
- release.yml: secret `ADMOB_APP_ID`・`ADMOB_REWARDED_UNIT_ID` が無い、またはテスト用のユニットなら失敗。任意の変数 `POLICY_BASE_URL`。

## 8. オーナーがやること

1. **AdMob**（RELEASE §1.8）: アプリとリワード広告ユニットを作り、環境 `play-release` の secret に `ADMOB_APP_ID`（`ca-app-pub-…~…`）と `ADMOB_REWARDED_UNIT_ID`（`ca-app-pub-…/…`）を入れる。ブロックの管理で G・センシティブなカテゴリをブロック。
2. **Play Console**: §3.2 の 3 商品を作成して有効にする（価格は PM と決める）。ライセンス テスターを登録。
3. **問い合わせ先メール**（公開される専用アドレス）と**デベロッパー名**（Play の表示と同じ）を決め、§5.2 の変数（または `build_site.py --var`）に入れる。
4. **ページの公開**（§5.2 の A か B）。B の場合は `app-ads.txt` をユーザーサイトの直下に置く。Play Console の「プライバシーポリシー」と「データの削除の URL」に `privacy.html`・`delete.html` の URL を入れる。
5. **Anthropic の契約とデータ保持**を確認し（RELEASE §1.6）、`privacy.html` の「原則 30 日以内に削除」と違えば直す（ZDR を契約した場合は「保持しない」に）。
6. Firebase を設定したら、Crashlytics をコンソールで有効にする（データは保護者がオンにした端末からだけ届く）。
7. ウェブからの削除依頼に対応する手順（RELEASE §1.11・§7-6 の管理スクリプト）を用意する。

## 9. PM に確認したいこと（未決定）

1. 商品の価格（§3.2 の案: 250 / 160 / 320 円。320 円はこうこくなしパスの目安として SPEC §11.4 で決定）。
2. 広告の 1 日の上限（3 回）でよいか。
3. v1.1 のサーバー検証（§3.3）を入れる時期。入れると購入に Firebase（保護者の同意）が必要になる。
4. ターゲット年齢に「5 歳以下」を含めるか（含めるなら広告と文言の見直し。STORE_LISTING §5）。
5. ポリシーの文面の法務確認（特に外国にある第三者への提供の記載、未成年者の取消し、免責）。
6. 公開方法 A / B（§5.2）と、問い合わせの返信の目安（サポートページに「5 営業日以内」と書いた）。
7. 今後、端末の日付を戻して広告の上限を回避できる点は許容する（サーバーを使わない設計のため）。

## 10. 出典（2026-10-09 に確認）

- [F1] Google Play「ファミリー ポリシー」: <https://support.google.com/googleplay/android-developer/answer/9893335> — 子どもに表示する広告は Families 自己認証済み広告 SDK のみ、インタレスト ベース広告・リマーケティングの禁止、リワード広告は 5 秒後に閉じられること、起動直後の広告の禁止、子どもだけが対象のアプリは API 33 以上で AD_ID 権限を要求しない・広告 ID を送らない、仮想通貨と現金の区別。
- [F2] 「ファミリーの広告と収益化」: <https://support.google.com/googleplay/android-developer/answer/11043825> と Families 自己認証済み広告 SDK の一覧: <https://support.google.com/googleplay/android-developer/answer/9283445>（Google AdMob `play-services-ads` 19.0.0 以上が掲載）。
- [A1] AdMob「ターゲティング」: <https://developers.google.com/admob/android/targeting> — `setTagForChildDirectedTreatment` は非推奨で `setAgeRestrictedTreatment`（CHILD）が後継、子ども向けの扱いでは AAID を送らない、`MAX_AD_CONTENT_RATING_G`、複数の信号では最も厳しいものが適用。Flutter の `RequestConfiguration.ageRestrictedTreatment`（google_mobile_ads 9.1.0）。
- [A2] AdMob「テスト広告」: <https://developers.google.com/admob/android/test-ads>（リワードのテストユニット `ca-app-pub-3940256099942544/5224354917`）と「Quick start」: <https://developers.google.com/admob/android/quick-start>（テスト App ID `ca-app-pub-3940256099942544~3347511713`、App ID の meta-data が無いと起動時にクラッシュ）。
- [A3] AdMob「Play のデータ開示」: <https://developers.google.com/admob/android/privacy/play-data-disclosure>（IP アドレス、操作、診断、端末とアカウントの ID を収集・共有。目的は広告・分析・不正防止。マニフェストで広告 ID の収集を止められる）。
- [B1] Play Billing「統合」: <https://developer.android.com/google/play/billing/integrate> — 3 日以内に acknowledge しないと自動返金、PENDING では付与・確認しない、バックエンドでの検証を強く推奨。
- [B2] Play Billing Library の非推奨化 FAQ: <https://developer.android.com/google/play/billing/deprecation-faq>（2026-08-31 以降、新規・更新は 8 以上。延長は 2026-11-01 まで）。
- [P1] Play「アカウントの削除の要件」: <https://support.google.com/googleplay/android-developer/answer/13327111>（アプリ内の削除に加えてウェブのリンクが必須、アプリ名またはデベロッパー名、アプリに戻らずに依頼できること、残すデータの説明）。
- [C1] Crashlytics Android SDK のソース（`CrashlyticsCore.onPreExecute`、`com.google.firebase.crashlytics.RequireBuildId`）: <https://github.com/firebase/firebase-android-sdk/blob/main/firebase-crashlytics/src/main/java/com/google/firebase/crashlytics/internal/common/CrashlyticsCore.java>
- [C2] Crashlytics「オプトインのレポート」: <https://firebase.google.com/docs/crashlytics/android/customize-crash-reports#enable-reporting>（`firebase_crashlytics_collection_enabled=false` と `setCrashlyticsCollectionEnabled`）。
- [AN] Anthropic「How long do you store my organization's data?」: <https://privacy.claude.com/en/articles/7996866>（API の入力と出力は原則 30 日以内に削除。契約で変わりうる）。
