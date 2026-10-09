# リリース手順書（Release/QA チーム）

リポジトリから Google Play に公開するまでの手順です。**オーナーしかできない作業**（アカウント・鍵・支払い）は §1 に、上から順にやる前提で書いています。それ以外（ビルド・署名・検査・アップロード）は GitHub Actions と fastlane で自動化しています（§2〜§5）。

関連: `docs/STORE_LISTING.md`（Play Console に入力する内容）、`docs/QA_CHECKLIST.md`（実機テスト）、`docs/BACKEND.md` §14（Firebase のデプロイ）。

```
 owner setup (§1) ─► tag v1.0.0-rc.1 ─► release.yml ─► internal testing ─► QA_CHECKLIST
                                                                     │
         production ◄─ staged rollout ◄─ promote_to_production ◄─ closed test (12人×14日) ◄─ tag v1.0.0
```

---

## 1. オーナーがやること（順番どおり）

所要時間の目安を書いています。審査待ちの時間が長いので、**1.1・1.5・1.8 は早めに始めてください**。

### 1.1 Google Play Console のデベロッパーアカウント（数日〜2 週間）
1. <https://play.google.com/console/signup> で登録します（登録料 25 米ドル、1 回だけ）。
2. **個人**か**組織**かを選びます。
   - 組織: D-U-N-S 番号が必要（無料で取れるが数週間かかる）。下の「12 人×14 日のクローズドテスト」が**不要**です。サポート窓口に組織名が出るので、保護者からの信頼も得やすいです。
   - 個人: すぐに作れますが、**2023 年 11 月 13 日以降に作った個人アカウントは、製品版の前に「12 人以上のテスターが 14 日間続けてオプトインしたクローズドテスト」が必須**です（§4.3）。
3. 本人確認（身分証、住所）、連絡先の電話番号とメールの確認、**Android 端末の確認**（Play Console アプリでのログイン）を済ませます。
4. 支払いプロファイル（販売者アカウント）を作ります。アプリ内課金の売上を受け取るのに必要です（銀行口座、税務情報）。

### 1.2 アプリを作成する（15 分）
Play Console → 「アプリを作成」:
- アプリ名「らくがきバトル」、デフォルトの言語「日本語 – ja-JP」、「ゲーム」、「無料」。
- デベロッパー プログラム ポリシー、米国輸出法への同意。
- パッケージ名は**最初の AAB をアップロードしたときに決まり、あとから変えられません**: `com.fru69syo.doodle_battle`（`app/android/app/build.gradle.kts` の applicationId）。変えるなら、この時点より前に PM に相談してください。

### 1.3 アップロード鍵と Play アプリ署名（30 分）
**Play アプリ署名**（Google が配信用の鍵を保管する方式。新しいアプリでは必須）を使います。私たちが持つのは**アップロード鍵**だけで、なくしても Play Console から再登録できます。

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -storetype PKCS12 \
  -alias upload -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=fru69syo, O=fru69syo, C=JP"
# パスワードを 2 回聞かれます（ストアと鍵で同じで構いません）
keytool -list -v -keystore upload-keystore.jks -alias upload | grep SHA256   # 控えておく
base64 -w0 upload-keystore.jks > upload-keystore.jks.b64                     # GitHub の secret 用
```
- `upload-keystore.jks` とパスワードは、パスワードマネージャーと**オフラインの場所**（USB メモリなど）の 2 か所に保管します。**リポジトリには絶対に入れません**（`.gitignore` で `*.jks` と `key.properties` は除外済み）。
- 手元で署名付きのビルドを作るときは、`app/android/key.properties` を作ります（git には入りません）:
  ```properties
  storeFile=/絶対パス/upload-keystore.jks
  storePassword=****
  keyAlias=upload
  keyPassword=****
  ```

**最初の 1 回だけは、AAB を Play Console から手でアップロードします**（API ではアプリの最初のバイナリを登録できないため）:
1. §2.4 の手順で署名付き AAB を作る（または `release.yml` を `upload: false` で実行し、Artifact から AAB をダウンロード）。
2. Play Console → テスト → 内部テスト → 新しいリリースを作成 → Play アプリ署名を「Google が生成した鍵」で有効にする → AAB をアップロード。
3. Play Console → 設定 → **アプリの完全性** → アプリ署名 で、**アプリ署名鍵の証明書の SHA-256** と**アップロード鍵の証明書の SHA-256** を控えます（Firebase で使います）。

### 1.4 Play Developer API 用のサービスアカウント（30 分）
1. Google Cloud Console で（Firebase とは別でもよい）プロジェクトを選び、**Google Play Android Developer API** を有効にします。
2. IAM → サービスアカウント → 作成（例: `play-publisher`）。ロールは付けません。
3. そのサービスアカウントの「鍵」→ 鍵を追加 → JSON → ダウンロード。
   - 組織のポリシー（`iam.disableServiceAccountKeyCreation`）で作れない場合は、制約の無いプロジェクトで作ります。
4. Play Console → **ユーザーと権限** → 新しいユーザーを招待 → サービスアカウントのメールアドレス → アプリの権限で「らくがきバトル」を追加し、次を付けます:
   - リリースを製品版にする、デバイスを除外する、Play アプリ署名を使用する
   - テストトラックにリリースする
   - ストアでの表示の管理（`fastlane android metadata` を使う場合）
5. JSON の中身をそのまま GitHub の secret `PLAY_SERVICE_ACCOUNT_JSON` に入れます（§1.9）。
6. 確認: `cd app/android && BUNDLE_GEMFILE=fastlane/Gemfile bundle install && PLAY_JSON_KEY_PATH=/path/key.json BUNDLE_GEMFILE=fastlane/Gemfile bundle exec fastlane android validate_key`（権限が反映されるまで最大 24〜36 時間かかることがあります）。

### 1.5 Firebase プロジェクト（1〜2 時間）
`docs/BACKEND.md` §14 も参照してください。
1. Firebase コンソールでプロジェクトを作成します。作成画面の **Google アナリティクスは「オフ」**にします（SPEC §7: Analytics は使わない）。
2. **Blaze プラン**に切り替え、Google Cloud の**予算アラート**（例: 月 5,000 円で 50%・90%・100% に通知）を設定します。
3. Firestore（ネイティブモード、**asia-northeast1**）、Storage（asia-northeast1）、Authentication の**匿名**を有効にします。
4. `firebase/.firebaserc` の `doodle-battle-dev` を実際のプロジェクト ID に置き換えます（PR で）。
5. Android アプリを登録し、クライアント設定を作ります:
   ```bash
   dart pub global activate flutterfire_cli
   cd app && flutterfire configure --project=<projectId> --platforms=android \
     --android-package-name=com.fru69syo.doodle_battle
   # → app/lib/firebase_options.dart と app/android/app/google-services.json ができる
   base64 -w0 lib/firebase_options.dart          # → secret FIREBASE_OPTIONS_DART_B64
   base64 -w0 android/app/google-services.json   # → secret GOOGLE_SERVICES_JSON_B64
   ```
   この 2 つのファイルをリポジトリに入れるかどうかは PM 判断です（中身は秘密情報ではありませんが、ここでは secret から作る前提にしています。入れる場合でも `release.yml` はそのまま動きます）。
6. Firebase コンソール → プロジェクトの設定 → Android アプリに **SHA-256 を 3 つ**登録します: §1.3 の**アプリ署名鍵**、**アップロード鍵**、開発用の debug 鍵（`keytool -list -v -keystore ~/.android/debug.keystore -storepass android`）。
7. **App Check**:
   - Play Console → 設定 → アプリの完全性 → **Play Integrity API** → この Firebase プロジェクトの Cloud プロジェクトをリンクします。
   - Firebase コンソール → App Check → Android アプリに **Play Integrity** プロバイダを登録します。
   - 開発用の端末・エミュレータでは**デバッグプロバイダ**を使い、表示されたデバッグトークンを App Check に登録します。
   - Functions はコードで `enforceAppCheck: true` です。Firestore と Storage は、App Check の指標で正規のリクエストがほぼ 100% になってから「適用」にします。
8. Firebase コンソール → Crashlytics を有効にします。SDK は組み込み済みで、**保護者が「ふぐあいの じょうほうを おくる」をオンにした端末からだけ**レポートが届きます（初期値オフ。docs/COMPLIANCE.md §4）。Crashlytics の Gradle プラグインは使いません（google-services.json は不要のまま）。

### 1.6 Anthropic の API キーとモデル（30 分）
1. Anthropic Console で組織（または専用のワークスペース）を作り、**API キー**を発行します。**月の利用上限**を設定し、利用通知を有効にします。
2. 組織の**データ保持**の設定と、商用利用規約・データ処理契約（DPA）を確認します。プライバシーポリシーに「お子さまの絵は、保護者が許可した場合に Anthropic が処理する」と書くため、保持期間を Compliance チームに伝えてください。
3. Secret Manager に保存します（クライアントには一切渡しません）:
   ```bash
   cd firebase/functions && npx firebase functions:secrets:set ANTHROPIC_API_KEY \
     --project <projectId> --config ../firebase.json
   ```
4. **モデル**: Functions のパラメータ `CLAUDE_MODEL` に、その時点で最新の**安価な Haiku 系**モデルの ID を設定します（画像入力・構造化出力・`effort` に対応していること）。ID は Anthropic のドキュメントの「Models overview」で確認してください。**このリポジトリにはモデル ID を書きません**。
   - GitHub Actions でデプロイする場合: 環境 `firebase-production` の**変数**（Variables）`CLAUDE_MODEL`。
   - 手元からデプロイする場合: `firebase/functions/.env.<projectId>` に `CLAUDE_MODEL=...`（git には入れない）。

### 1.7 Functions デプロイ用のサービスアカウント（30 分）
1. Firebase の Cloud プロジェクトにサービスアカウント（例: `ci-deployer`）を作り、次のロールを付けます:
   Cloud Functions 管理者、Firebase ルール管理者、Cloud Datastore インデックス管理者、Cloud Scheduler 管理者、Secret Manager 閲覧者、Artifact Registry 管理者、Cloud Build 編集者、Eventarc 管理者、サービス アカウント ユーザー（ランタイムのサービスアカウントに対して）。
   デプロイが権限エラーで止まったら、エラーに出たロールを足してください。
2. JSON 鍵を作り、GitHub の環境 `firebase-production` の secret `FIREBASE_SERVICE_ACCOUNT_JSON` に入れます。
3. **最初のデプロイは手元から対話モードで**行います（Storage のルールが Firestore を参照するための権限付与、シークレットへのアクセス付与など、確認のプロンプトに答える必要があるため）:
   ```bash
   cd firebase/functions && npm ci
   npx firebase deploy --config ../firebase.json --project <projectId> --only functions,firestore,storage
   ```
   2 回目からは GitHub → Actions → **Deploy Firebase (manual)** → Run workflow（プロジェクト ID を 2 回入力）。
4. 運用: `moderationQueue` と `moderation.suspectSkill` の確認担当を決めます（BACKEND §14.8）。

### 1.8 AdMob（広告を出す場合。1〜3 日）
1. AdMob アカウントを作り、支払い・税務情報を登録します。
2. アプリを追加（Android、ストア公開前なら「未公開」で作成し、公開後にストアと紐づけ）し、**リワード広告ユニット**を作ります。
3. AdMob の設定:
   - ブロックの管理 → 広告コンテンツの最大レーティング **G**、センシティブなカテゴリをすべてブロック。
   - コードで `tagForChildDirectedTreatment = true`、`maxAdContentRating = G`、パーソナライズしない（Compliance チーム）。
4. **アプリ ID**（`ca-app-pub-...~...`）と**リワード広告ユニット ID**（`ca-app-pub-.../...`）を、環境 `play-release` の secret `ADMOB_APP_ID`・`ADMOB_REWARDED_UNIT_ID` に入れます（§1.9）。アプリ ID は Gradle（`ADMOB_APP_ID` の Gradle プロパティか環境変数）→ マニフェストの meta-data、ユニット ID は `--dart-define=ADMOB_REWARDED_UNIT_ID` で入ります。何も設定しないビルド（開発・CI）は Google の**テスト ID** になり、release.yml は secret が無い・テスト用のユニットだと失敗し、`check_release.sh --require-real-admob` もテストのアプリ ID を拒否します。手元で本番の ID を試すとき: `ADMOB_APP_ID=ca-app-pub-...~... flutter build appbundle --release --dart-define=ADMOB_REWARDED_UNIT_ID=ca-app-pub-.../...`。
5. **app-ads.txt**: Play に登録した「ウェブサイト」の**ドメインの直下**に置く必要があります。`https://fru69syo.github.io/doodle-battle/` で登録した場合、置き場所は `https://fru69syo.github.io/app-ads.txt` です（§1.10 のユーザーサイト用リポジトリに置く。中身は `site/app-ads.txt`、pub ID は `scripts/build_site.py` が入れる）。
6. 広告の仕様（子ども向けの設定、1 日 3 回、許可までは SDK を初期化しない）は docs/COMPLIANCE.md §2。

### 1.9 GitHub の設定（30 分）
1. リポジトリ `fru69syo/doodle-battle`（private）を作り、push します。
2. Settings → Environments で 2 つ作ります（どちらも **Required reviewers にオーナーを設定**）:

| 環境 | 種類 | 名前 | 中身 |
|---|---|---|---|
| `play-release` | secret | `ANDROID_KEYSTORE_BASE64` | `upload-keystore.jks` の base64（1 行） |
| | secret | `ANDROID_KEYSTORE_PASSWORD` | キーストアのパスワード |
| | secret | `ANDROID_KEY_ALIAS` | `upload` |
| | secret | `ANDROID_KEY_PASSWORD` | 鍵のパスワード |
| | secret | `PLAY_SERVICE_ACCOUNT_JSON` | §1.4 の JSON の中身 |
| | secret | `FIREBASE_OPTIONS_DART_B64` | §1.5 の `firebase_options.dart` の base64 |
| | secret | `GOOGLE_SERVICES_JSON_B64` | §1.5 の `google-services.json` の base64 |
| | secret | `ADMOB_APP_ID` | AdMob のアプリ ID `ca-app-pub-XXXXXXXXXXXXXXXX~NNNNNNNNNN`（§1.8）。**必須** |
| | secret | `ADMOB_REWARDED_UNIT_ID` | リワード広告ユニット ID `ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN`。**必須** |
| | variable（任意） | `POLICY_BASE_URL` | ポリシーのページの場所を既定（`https://fru69syo.github.io/doodle-battle/`）から変えるときだけ。`https://…/` の形 |
| リポジトリ | variable | `DEVELOPER_NAME`・`SUPPORT_EMAIL`・`ADMOB_PUBLISHER_ID`・`PAGES_ENABLED` | ポリシーのサイト（`pages.yml`、§1.10）。この 3 つの値はページに入れて公開される |
| `firebase-production` | secret | `FIREBASE_SERVICE_ACCOUNT_JSON` | §1.7 の JSON の中身 |
| | variable | `CLAUDE_MODEL` | 最新の Haiku 系モデルの ID（§1.6） |

   - `play-release` の「Deployment branches and tags」を **タグ `v*` だけ**に制限します。手動で実行するときは「Use workflow from」で**タグを選んで**ください（ブランチから実行すると環境の制限で止まります）。
3. Settings → Branches → `main` に保護ルール: PR 必須、ステータスチェック必須（CI の各ジョブ。パスフィルタでスキップされたジョブは成功扱い）、force push 禁止。
4. Settings → Actions → General: 「Read repository contents permission」を既定に。サードパーティのアクションはすべてコミット SHA で固定しています（更新するときは Dependabot か手動で SHA を差し替える）。

### 1.10 プライバシーポリシー・サポート・削除ページの公開（1 時間）
ページの中身は `site/`（Compliance チーム。プライバシーポリシー、利用規約、データの削除、サポート・よくある質問、app-ads.txt）。デベロッパー名・問い合わせ先メール・AdMob の pub ID は `{{…}}` のプレースホルダーで、`scripts/build_site.py` が置き換えます（値が無いと失敗）。詳しくは docs/COMPLIANCE.md §5。

**private リポジトリの GitHub Pages は有料プランでしか使えません。** 次のどちらかにします。
- **A（有料プランがある）**: Settings → Pages → Source「GitHub Actions」。リポジトリ変数 `DEVELOPER_NAME`・`SUPPORT_EMAIL`・`ADMOB_PUBLISHER_ID` と `PAGES_ENABLED=true` を設定すると、`.github/workflows/pages.yml` が `main` の `site/` を公開します。app-ads.txt だけは B のユーザーサイトの直下に置く必要があります。
- **B（推奨・無料）**: 公開用の**別の public リポジトリ** `fru69syo/fru69syo.github.io`（ユーザーサイト）に、`build_site.py --out` で作ったファイルを置きます:

```
fru69syo.github.io/
  app-ads.txt                    ← AdMob（§1.8）。ドメインの直下
  doodle-battle/index.html       ← サポートページ（連絡先、よくある質問）
  doodle-battle/privacy.html     ← プライバシーポリシー
  doodle-battle/terms.html       ← 利用規約
  doodle-battle/delete.html      ← データ削除ページ（§1.11）
  doodle-battle/style.css
```
- Settings → Pages → Deploy from a branch（`main` / root）。数分で `https://fru69syo.github.io/doodle-battle/privacy.html` が見られるようになります。アプリの既定の URL と同じなので、アプリの設定は不要です。
- ページには子ども向けの広告やトラッキング（Google Analytics など）を**入れません**（`build_site.py --check` が `<script>` を拒否します）。
- プライバシーポリシーを変えたら、アプリの `currentPolicyVersion`（`consent.policyVersion`）を上げて保護者に再同意してもらいます（BACKEND §3）。

### 1.11 アカウント（データ）削除ページ
Play のデータセーフティに URL を入力します。ページに必ず書くこと:
- ストアと同じアプリ名「らくがきバトル」とデベロッパー名
- 削除の手順:
  1. アプリで: 「おうちのひと」（保護者ゲート）→「すべてのデータを削除」→ 確認。すぐにサーバーと端末のデータが消えます。
  2. アプリを消してしまった場合: 問い合わせ先メールに「らくがきバトルのデータ削除希望」と、わかれば「サポート ID」（おうちのひと画面に表示）を書いて送る。運営が確認して 30 日以内に削除し、完了を返信します。
- 削除されるデータ: サーバーのプロフィール（表示名・レーティング）、登録したキャラクターの絵・名前・ステータス、対戦と通報の記録、匿名の認証 ID。
- 削除されない・残るデータ: クラッシュログ（Crashlytics の保持期間 90 日で自動削除）、法令で必要な記録。クラウド判定の画像はもともと保存していません。
- 運営側の手順（PM 判断で用意する）: サポート ID（= uid）を指定して `deleteMyData` と同じ処理を実行する管理スクリプト。現状はありません（§7）。

### 1.12 Play Console の入力（1〜2 時間）
`docs/STORE_LISTING.md` のとおりに入力します。
1. ストアの設定（カテゴリ、タグ、連絡先）。
2. メインのストア掲載情報: `store/metadata/ja-JP/` の文とグラフィック。手入力でも、`bundle exec fastlane android metadata dry_run:true` で検証 → `metadata` でアップロードしてもよい。スクリーンショットは実機で撮って追加します。
3. アプリのコンテンツ: プライバシーポリシー、広告、アプリのアクセス権、コンテンツのレーティング、ターゲット層とコンテンツ（ファミリー）、データセーフティ、広告 ID、政府機関・金融・健康の申告。
4. 収益化 → 商品: アプリ内アイテム（STORE_LISTING §8。PM が確定してから）。
5. 配信国: 日本（PM 判断）。

---

## 2. バージョンとビルド

### 2.1 バージョンの付け方
タグから決めます（`scripts/version_from_tag.sh`）。

| タグ | versionName | versionCode | 用途 |
|---|---|---|---|
| `v1.0.0-rc.1` | 1.0.0-rc.1 | 1000001 | 内部テストで確認する候補（rc は 1〜98） |
| `v1.0.0-rc.2` | 1.0.0-rc.2 | 1000002 | |
| `v1.0.0` | 1.0.0 | 1000099 | 製品版にする版（同じコミットに付け直す） |
| `v1.0.1` | 1.0.1 | 1000199 | 修正版 |
| `v1.2.3` | 1.2.3 | 1020399 | |

- versionCode = MAJOR×1,000,000 + MINOR×10,000 + PATCH×100 + (rc 番号 または 99)。MINOR と PATCH は 0〜99。
- 同じバージョンの正式版は、必ずその rc より大きい番号になります。タグとバージョンは 1 対 1 なので、同じタグを作り直してもう一度アップロードすることはできません（Play が同じ versionCode を拒否します）。作り直すときは次の rc を切ってください。
- `pubspec.yaml` の `version:` は手元の開発用で、リリースのビルドでは `--build-name` / `--build-number` で上書きします。

### 2.2 署名
`app/android/app/build.gradle.kts`:
- `app/android/key.properties` があれば、その鍵（アップロード鍵）で release を署名します。
- 無ければ debug 鍵で署名します（`flutter run --release` を手元で使えるようにするため）。debug 鍵の AAB は `check_release.sh --require-upload-key` が失敗させ、Play も受け付けません。

### 2.3 R8・リソースの縮小
`isMinifyEnabled = true`、`isShrinkResources = true`、`proguard-rules.pro`（ARCore、Filament・SceneView の JNI、自前の AR の Kotlin、Crashlytics 用の行番号、Play Core の dontwarn）。難読化の対応表 `mapping.txt` は release.yml が Artifact に保存し、fastlane が Play にもアップロードします。Dart のコードは難読化していません（`--obfuscate` を使うかは §7 の PM 判断）。

### 2.4 手元での署名付きビルドと検査
```bash
source /opt/sdk/env.sh                      # この開発環境の場合
cd app && flutter build appbundle --release --build-name 1.0.0 --build-number 1000099
cd .. && scripts/check_release.sh app/build/app/outputs/bundle/release/app-release.aab \
          --require-upload-key --expect-version-code 1000099
scripts/check_16kb.sh app/build/app/outputs/bundle/release/app-release.aab
```
2026-10-09 の計測（テスト用の鍵で署名）: ビルド成功、AAB 61.8 MiB（全 ABI 入り）、arm64 端末のダウンロードサイズの見積もり 16.9 MiB。64 bit のネイティブライブラリ 22 個はすべて 16 KB 境界（`zipalign -c -P 16` 合格、ELF の `p_align` ≥ 16384）。
2026-10-09 の再計測（Compliance: AdMob・Play Billing・Crashlytics・url_launcher を追加、debug 鍵、`--obfuscate` なし）: AAB 88.5 MiB、arm64 のダウンロードサイズの見積もり **26.9 MiB**、64 bit のネイティブライブラリ 24 個すべて 16 KB 境界、`check_release.sh` 合格（警告はテストの AdMob ID と debug 鍵だけ）。増えた分の大部分は Google Mobile Ads SDK（と依存する WebView 関連）。

---

## 3. CI/CD（GitHub Actions）

| ワークフロー | きっかけ | やること |
|---|---|---|
| `ci.yml` | PR、`main` への push、手動 | 変更があった部分だけ実行: Flutter（format・analyze・test とカバレッジの基準）、TS バトルエンジンのテスト、Functions（lint・build・unit・emulator）、Android の debug APK とリリース用マニフェストの検査、ストア文の文字数、actionlint。`main` への push では release AAB も作って 16 KB を確認 |
| `release.yml` | タグ `v*` の push、手動 | 署名付き AAB → 検査（署名・権限・targetSdk・16 KB）→ Artifact（AAB と mapping、90 日）→ fastlane で**内部テスト**にアップロード |
| `functions-deploy.yml` | **手動だけ** | lint と unit テスト → Functions・ルールのデプロイ（push では絶対に動きません） |
| `pages.yml` | `site/` の変更（PR・`main`）、手動 | `build_site.py --check`。`PAGES_ENABLED=true` なら `main` で GitHub Pages に公開（§1.10） |

- docs だけの変更では、重いジョブ（Flutter・Android・Functions）は動きません。
- `scripts/check_release.sh` の許可リスト: CAMERA、INTERNET、ACCESS_NETWORK_STATE、WAKE_LOCK・RECEIVE_BOOT_COMPLETED・FOREGROUND_SERVICE（WorkManager などライブラリ由来）、com.android.vending.BILLING、WRITE/READ_EXTERNAL_STORAGE（maxSdkVersion ≤ 28 のときだけ）。AD_ID、位置情報、RECORD_AUDIO、連絡先、READ_MEDIA_*、POST_NOTIFICATIONS、インストールリファラなどは理由つきで失敗します。
- 広告と課金の SDK は組み込み済みで、`AD_ID` と `ACCESS_ADSERVICES_*` は `tools:node="remove"` で外しています（Compliance）。`check_release.sh` は AdMob のアプリ ID の形式・`DELAY_APP_MEASUREMENT_INIT=true`・Crashlytics の初期値オフも検査し、release.yml では `--require-real-admob`（テストのアプリ ID を拒否）を付けます。
- `scripts/write_firebase_config.sh --require` はプレースホルダー（マーカー `DOODLE_BATTLE_FIREBASE_PLACEHOLDER`、`demo-` のプロジェクト、Android の設定なし）を拒否します。テストは `scripts/test_write_firebase_config.sh`（CI の android ジョブ）。

---

## 4. リリースの流れ

### 4.1 リリース候補（内部テスト）
1. `main` の CI がすべて緑であることを確認します。
2. `git tag v1.0.0-rc.1 && git push origin v1.0.0-rc.1`
3. Actions → Release (Play internal) が動きます。環境 `play-release` の承認を求められたら承認します。
   - アプリをまだ一度も公開していない（審査前の「下書き」の）間は、手動実行で `release_status: draft` を選ぶ必要がある場合があります。その場合は Play Console で内部テストのリリースを開いて「公開」します。
4. 内部テスターに配信されます（Play Console → 内部テスト → テスター。メールのリストで最大 100 人）。
5. `docs/QA_CHECKLIST.md` を実施します。不具合があれば修正して `v1.0.0-rc.2` を切ります。

### 4.2 製品版にする版を作る
1. QA に合格した rc と**同じコミット**に `v1.0.0` を付けて push します（versionName から `-rc` が消え、versionCode は 1000099）。
2. 内部テストに上がった `1000099` を、スモークテスト（QA_CHECKLIST の「S」の項目）で確認します。
3. クローズドテストに昇格させます:
   ```bash
   cd app/android
   export BUNDLE_GEMFILE=fastlane/Gemfile PLAY_JSON_KEY_PATH=/path/play.json
   bundle exec fastlane android promote_to_closed version_code:1000099        # internal → alpha
   ```

### 4.3 クローズドテスト（個人アカウントの場合は必須）
- 2023 年 11 月 13 日以降に作った**個人**デベロッパーアカウントは、「**12 人以上のテスターが 14 日間続けてオプトインしている**クローズドテスト」を行ってからでないと、製品版へのアクセスを申請できません。条件を満たしたら、Play Console のダッシュボードから申請します。審査は通常 7 日以内で、クローズドテストの内容、アプリについて、製品版の準備について質問されます。テスターが 12 人未満だったり、テスターの利用が少なかったりすると、テストを続けるよう求められます。
  （出典: Play Console ヘルプ「新しいデベロッパー アカウントのアプリのテスト要件」 <https://support.google.com/googleplay/android-developer/answer/14151465>、2026-10-09 に確認）
- 進め方:
  - テスターは**保護者（大人）の Google アカウント**で集めます（子どもが遊ぶのを見てもらう）。脱落に備えて 15〜20 人。Google グループを作ってトラックに登録すると管理が楽です。
  - オプトインの URL を送り、**アプリを実際にインストールして**もらいます。14 日の間に人数が 12 人を下回らないように注意します。
  - 期間中もアップデートは出してかまいません（rc → 正式版の流れは同じ）。フィードバックは申請の質問（何を直したか）に使うので記録しておきます。
- 組織アカウントにはこの条件はありませんが、クローズドテストで実機の確認をすることを推奨します。

### 4.4 製品版（段階的公開）
1. 「製品版」のページで国（日本）を選び、リリースノートを確認します。
2. 10% から始めます:
   ```bash
   bundle exec fastlane android promote_to_production version_code:1000099 rollout:0.1   # alpha → production
   ```
   初回は Google の審査（ファミリー向けアプリは数日〜1 週間かかることがある）が入ります。
3. 広げる目安（各段階で 24〜48 時間見る）:

| 段階 | コマンド | 次に進む条件 |
|---|---|---|
| 10% | `promote_to_production ... rollout:0.1` | Android vitals のクラッシュ率 < 1.09%、ANR 率 < 0.47%（Play の「不良な動作」の閾値）、Crashlytics に新しい重大なクラッシュが無い、Functions のエラー率に変化なし、保護者からの重大な報告なし |
| 25% | `rollout version_code:1000099 rollout:0.25` | 同上 |
| 50% | `rollout ... rollout:0.5` | 同上 |
| 100% | `rollout ... rollout:1` | |

### 4.5 ロールバック
Play では、一度出した版より**小さい versionCode に戻すことはできません**。問題が見つかったら:
1. **段階的公開を止める**: `bundle exec fastlane android halt_rollout version_code:1000099 rollout:<今の割合>`（または Play Console で「公開を停止」）。新しく受け取る人はいなくなりますが、すでに更新した人はそのままです。
2. **修正版を出す**: 修正（または問題のコミットを revert）して `v1.0.1` を切り、§4.1〜4.4 を短縮して行います（内部 → スモーク → 昇格）。緊急時はクローズドテストからそのまま 100% にしてもかまいません。
3. **サーバー側**: 問題が Functions やルールなら、前のタグをチェックアウトして `functions-deploy.yml` を**そのタグで**手動実行します。バトルエンジンが変わると対戦中の試合は中断されます（BACKEND §7。仕様どおり）。Firestore のデータを壊す変更は、デプロイ前にエクスポート（`gcloud firestore export`）を取っておきます。
4. 止めた版を再開する場合は Play Console の「公開を再開」を使います（fastlane の `rollout` は停止中の版には使えません）。

---

## 5. fastlane のレーン

`app/android` で `export BUNDLE_GEMFILE=fastlane/Gemfile PLAY_JSON_KEY_PATH=...` のあと `bundle exec fastlane android <lane> [key:value ...]`。

| レーン | 内容 |
|---|---|
| `validate_key` | サービスアカウントで API に届くか確認 |
| `internal aab:<path> mapping:<path> status:<completed\|draft>` | 内部テストへアップロード（release.yml が使う）。リリースノートは `store/metadata/ja-JP/changelogs/<versionCode>.txt`、無ければ `default.txt` |
| `promote_to_closed version_code:<n> [from:internal] [to:alpha]` | テストトラック間の昇格 |
| `promote_to_production version_code:<n> [from:alpha] [rollout:0.1]` | 製品版へ段階的公開 |
| `rollout version_code:<n> rollout:<0-1>` | 公開の割合を変える（1 で完了） |
| `halt_rollout version_code:<n> rollout:<今の割合>` | 段階的公開を停止 |
| `metadata [dry_run:true]` | 掲載文とグラフィックをアップロード |

---

## 6. よくあるエラー

| 症状 | 対処 |
|---|---|
| `Package not found: com.fru69syo.doodle_battle` | 最初の AAB を Play Console から手でアップロードしていない（§1.3） |
| `Only releases with status draft may be created on draft app` | アプリがまだ一度も公開されていない。`release_status: draft` で実行し、Console で公開 |
| `APK specifies a version code that has already been used` | 同じタグを作り直した。次の rc を切る |
| `The caller does not have permission` | Play Console でサービスアカウントの権限が足りない、または反映待ち（§1.4） |
| `check_release: forbidden permission com.google.android.gms.permission.AD_ID` | 広告や Firebase のライブラリが権限を足した。マニフェストで `tools:node="remove"` |
| `firebase_options.dart is missing` | secret `FIREBASE_OPTIONS_DART_B64` が無い（§1.5） |
| `firebase_options.dart is not a real Firebase config (placeholder marker …)` | secret が無く、リポジトリのプレースホルダーのままビルドしようとした（§1.5） |
| `Missing secrets in environment play-release: ADMOB_APP_ID …` | AdMob の secret が無い（§1.8・§1.9） |
| `check_release: AdMob APPLICATION_ID is Google's *test* app id` で失敗 | `ADMOB_APP_ID` が Gradle に渡っていない（release.yml の env、手元なら環境変数） |
| 起動直後に「The Crashlytics build ID is missing」で落ちる | `res/values/crashlytics.xml`（`RequireBuildId=false`）が消えた／縮小で消された（docs/COMPLIANCE.md §4） |
| Functions のデプロイで `CLAUDE_MODEL` を聞かれて止まる | 環境変数 `CLAUDE_MODEL`（GitHub）か `.env.<projectId>` が無い（§1.6） |
| App Check で本番のアプリが弾かれる | Firebase にアプリ署名鍵の SHA-256 が登録されていない、または Play Integrity の Cloud プロジェクトのリンクがない（§1.5） |

---

## 7. 決まっていないこと（PM 判断）

1. デベロッパーアカウントを個人で作るか組織で作るか（クローズドテストの条件が変わる）。
2. 配信国（日本のみを推奨）、ターゲット年齢に「5 歳以下」を含めるか、カテゴリ（カジュアル／教育）。
3. `firebase_options.dart` と `google-services.json` をリポジトリに入れるか、secret から作るか（現状は secret）。
4. ~~Crashlytics を保護者の設定でオフにできるようにするか~~ → **決定**: 保護者が許可したときだけ送る（初期値オフ。docs/COMPLIANCE.md C13）。匿名サインインも保護者の許可まで行わない（UI チーム、実装済み）。
5. Dart の難読化（`--obfuscate --split-debug-info`）を使うか。使う場合はシンボルを Crashlytics にアップロードする手順を足す。
6. ウェブからの削除依頼を処理する管理スクリプト（uid を指定して `deleteMyData` と同じ処理）を Backend チームに作ってもらうか。
7. 審査担当者がオンライン対戦を確認するための手順（Lv5 にするまでの時間）。
8. Teacher Approved を狙うか（オンライン対戦が「ソーシャル機能」とみなされると対象外）。
9. ~~おうえんパスを定期購入にするか買い切りにするか~~ → **決定**: 買い切り（SPEC §10）。商品の価格と広告の 1 日の上限は docs/COMPLIANCE.md §9。
