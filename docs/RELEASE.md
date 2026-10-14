# リリース手順書（Release/QA チーム）

リポジトリから Google Play に **v2.0.0** を公開するまでの手順です。**オーナーしかできない作業**（アカウント・鍵・支払い・クラウドの設定）は §1 に、上から順にやる前提で書いています。それ以外（ビルド・署名・検査・アップロード）は GitHub Actions と fastlane で自動化しています（§2〜§5）。

関連: `docs/STORE_LISTING.md`（Play Console に入力する内容）、`docs/QA_CHECKLIST.md`（実機テスト）、`docs/LEARN_GCP.md`（GCP・Terraform の詳しい説明）、`docs/BACKEND.md` §14（Firebase）、`docs/COMPLIANCE.md`（広告・ポリシー）。

```
 owner setup (§1) ─► tag v2.0.0-rc.1 ─► release.yml ─► internal testing ─► QA_CHECKLIST
                                                                     │
  production ◄─ staged rollout ◄─ promote_to_production ◄─ closed test (12人×14日) ◄─ tag v2.0.0
```

---

## 0. 全体の流れと時間の目安

**合計: 作業はおよそ 2〜3 日分。ただし待ち時間（アカウントの審査、AdMob、クローズドテスト 14 日、製品版の審査）があるので、カレンダーでは 4〜6 週間**を見てください。待ちが長いものは ☆ を付けました。同じ日に並べて始めてください。

| # | やること | 作業時間 | 待ち時間 | 節 |
|---|---|---|---|---|
| 1 | ☆ Play Console のデベロッパーアカウント | 1 時間 | 数日〜2 週間（本人確認） | §1.1 |
| 2 | Play Console でアプリを作る | 15 分 | – | §1.2 |
| 3 | アップロード鍵と Play アプリ署名、最初の AAB | 45 分 | – | §1.3 |
| 4 | Play Developer API のサービスアカウント | 30 分 | 最大 36 時間（権限の反映） | §1.4 |
| 5 | GCP プロジェクトと Terraform（bootstrap → prod） | 2〜3 時間 | – | §1.5 |
| 6 | 予算アラート（月 5,000 円）の確認 | 15 分 | – | §1.6 |
| 7 | Anthropic の API キーと利用上限（月 2,000 円） | 30 分 | – | §1.7 |
| 8 | Firebase のクライアント設定・App Check・Crashlytics | 1 時間 | – | §1.8 |
| 9 | Firebase のデプロイ（Functions・ルール・**インデックス**） | 30 分 | インデックスの作成 5〜15 分 | §1.9 |
| 10 | 対戦サーバー（Cloud Run）のデプロイ | 20 分 | – | §1.10 |
| 11 | ☆ AdMob | 1 時間 | 1〜3 日（アカウントの審査） | §1.11 |
| 12 | GitHub の環境・secret・変数 | 30 分 | – | §1.12 |
| 13 | プライバシーポリシーなどのページの公開 | 1 時間 | – | §1.13 |
| 14 | Play Console の入力（レーティング・ターゲット層・データセーフティ・掲載情報） | 2 時間 | – | §1.14 |
| 15 | 内部テスト（rc）と QA_CHECKLIST | 1〜2 日 | – | §4.1 |
| 16 | ☆ クローズドテスト（**個人アカウントは 12 人 × 14 日**） | 2 時間（テスターの招待） | 14 日以上 + 審査 7 日 | §4.3 |
| 17 | 製品版（段階的公開 10 → 100%） | 30 分 | 審査 数日〜1 週間、各段階 24〜48 時間 | §4.4 |

---

## 1. オーナーがやること（順番どおり）

### 1.1 Google Play Console のデベロッパーアカウント
（作業 1 時間、待ち 数日〜2 週間）
1. <https://play.google.com/console/signup> で登録します（登録料 25 米ドル、1 回だけ）。
2. **個人**か**組織**かを選びます（PM 判断、SPEC §17.7）。
   - 組織: D-U-N-S 番号が必要（無料で取れるが数週間かかる）。下の「12 人×14 日のクローズドテスト」が**不要**です。サポート窓口に組織名が出ます。
   - 個人: すぐに作れますが、**2023 年 11 月 13 日以降に作った個人アカウントは、製品版の前に「12 人以上のテスターが 14 日間続けてオプトインしたクローズドテスト」が必須**です（§4.3）。
3. 本人確認（身分証、住所）、連絡先の電話番号とメールの確認、**Android 端末の確認**（Play Console アプリでのログイン）を済ませます。
4. v2.0 はアプリ内課金がないので、支払いプロファイル（販売者アカウント）は**まだ不要**です（課金を有効にするときに作る。STORE_LISTING §8）。

### 1.2 Play Console でアプリを作る（15 分）
Play Console → 「アプリを作成」:
- アプリ名「おえかきファイターズ らくがきが うごいて たたかう」（`store/metadata/ja-JP/title.txt`）、デフォルトの言語「日本語 – ja-JP」、「ゲーム」、「無料」。
- デベロッパー プログラム ポリシー、米国輸出法への同意。
- パッケージ名は**最初の AAB をアップロードしたときに決まり、あとから変えられません**: `com.fru69syo.doodle_battle`（`app/android/app/build.gradle.kts` の applicationId）。

### 1.3 アップロード鍵と Play アプリ署名（45 分）
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

**最初の 1 回だけは、AAB を Play Console から手でアップロードします**（API ではアプリの最初のバイナリを登録できないため）。この時点では Firebase がまだ無いので、テスターには配らない「登録用」のビルドにします（versionCode 1。タグから作る版は 2000001 以上なので、あとで困りません）:
1. `cd app && flutter build appbundle --release --build-name 2.0.0-rc.0 --build-number 1`（`key.properties` がある状態で）。
2. Play Console → テスト → 内部テスト → 新しいリリースを作成 → Play アプリ署名を「Google が生成した鍵」で有効にする → AAB をアップロード → **保存だけ**して、テスターは登録しない。
3. Play Console → 設定 → **アプリの完全性** → アプリ署名 で、**アプリ署名鍵の証明書の SHA-256** と**アップロード鍵の証明書の SHA-256** を控えます（§1.5 の Terraform と §1.8 の Firebase で使います）。

### 1.4 Play Developer API 用のサービスアカウント（30 分）
1. Google Cloud Console で（§1.5 の prod とは別のプロジェクトでもよい）**Google Play Android Developer API** を有効にします。
2. IAM → サービスアカウント → 作成（例: `play-publisher`）。ロールは付けません。
3. そのサービスアカウントの「鍵」→ 鍵を追加 → JSON → ダウンロード（Play の API は Workload Identity 連携に対応していないため、ここだけは JSON 鍵です）。
4. Play Console → **ユーザーと権限** → 新しいユーザーを招待 → サービスアカウントのメールアドレス → アプリの権限で「おえかきファイターズ」を追加し、次を付けます: リリースを製品版にする・デバイスを除外する・Play アプリ署名を使用する／テストトラックにリリースする／ストアでの表示の管理。
5. JSON の中身をそのまま GitHub の secret `PLAY_SERVICE_ACCOUNT_JSON` に入れます（§1.12）。
6. 確認: `cd app/android && BUNDLE_GEMFILE=fastlane/Gemfile bundle install && PLAY_JSON_KEY_PATH=/path/key.json BUNDLE_GEMFILE=fastlane/Gemfile bundle exec fastlane android validate_key`（権限の反映に最大 24〜36 時間かかることがあります）。

### 1.5 GCP プロジェクトを Terraform で作る（2〜3 時間）
Firebase（Firestore・Storage・匿名認証・App Check）、対戦サーバー（Cloud Run）、予算とキルスイッチ、監視、GitHub から鍵なしでデプロイするための Workload Identity 連携は、**すべて Terraform** で作ります。手順の本体は **`docs/LEARN_GCP.md` §4**（はじめてのセットアップ）です。**まず dev で最後まで通し、同じ手順を prod でくり返す**のがおすすめです（初回は dev 3 時間 + prod 1 時間ほど）。
1. **プロジェクトを作って請求先をつなぐ**（LEARN_GCP [§4.2](LEARN_GCP.md)、15 分）: `gcloud projects create doodle-battle-prod` → `gcloud billing projects link …`。請求先アカウントの通貨が **JPY** であることを確認します。Firebase コンソールでプロジェクトを作る必要はありません（Terraform が追加します。**Google アナリティクスは使いません**）。
2. **bootstrap**（LEARN_GCP [§4.3](LEARN_GCP.md)、20 分）: `infra/terraform/bootstrap` で state のバケット、`tf-plan@`・`tf-apply@`、Workload Identity プールを作ります。
3. **環境を作る**（LEARN_GCP [§4.4](LEARN_GCP.md)、30 分）: `infra/terraform/envs/prod` の `terraform.tfvars` に bootstrap の output と `alert_email` を書き、`android_sha256_hashes` に §1.3 で控えた **アプリ署名鍵とアップロード鍵の SHA-256** を入れて `terraform apply`。`monthly_budget_jpy` は既定の **5000** のままにします。
4. **GitHub の環境と変数**（LEARN_GCP [§4.5](LEARN_GCP.md)、20 分）: `infra-prod-plan`・`infra-prod`・`realtime-prod`・`firebase-prod`（prod の 3 つは Required reviewers にオーナー）。2 回目からの Terraform は Actions → **Terraform apply (manual)**（LEARN_GCP §4.6）。
5. `firebase/.firebaserc` の `doodle-battle-dev` を実際のプロジェクト ID に置き換えるか、prod を別名で足します（PR で）。

### 1.6 予算アラート（月 5,000 円、15 分）
SPEC §11.3: **サーバーの予算は月 5,000 円まで**（Anthropic の利用料を含む）。予算そのものは §1.5 の Terraform（`modules/cost_guard`、`monthly_budget_jpy = 5000`）が作ります。ここでは届くことを確かめます。
1. Cloud Console → お支払い → **予算とアラート** に「doodle-battle prod monthly」¥5,000 があり、**50 %・80 %・100 %（実績）と 100 %（予測）**で `alert_email` に通知する設定になっていることを確認します。
2. `alert_email` に届いた「Cloud Monitoring の通知先の確認」メールを承認します。
3. 予算は Pub/Sub `budget-alerts` → キルスイッチ `onBudgetAlert`（§1.9 でデプロイ）につながり、80 % で `saving`、100 % で `minimal` に自動で切り替わります（LEARN_GCP §6）。**dev で一度試してください**（LEARN_GCP [§6.6](LEARN_GCP.md)）。手で切り替えるときは Firestore コンソールで `config/costMode` に `pinned: true`（LEARN_GCP §6.4、QA_CHECKLIST §7.10）。

### 1.7 Anthropic の API キーと利用上限（30 分）
AI の提供元は **Claude だけ**です（SPEC §11.1。Gemini・Vertex AI・Firebase AI Logic は 18 歳未満向けのサービスでの利用が規約で禁止されているため使いません）。
1. Anthropic Console で組織（または専用のワークスペース）を作り、**API キー**を発行します。
2. **月の利用上限（spend limit）を 2,000 円相当（約 13 米ドル）**に設定し、利用通知を有効にします。AI の料金は GCP の請求に入らないので、GCP の予算では止まりません。**本当の歯止めはこの上限**です（LEARN_GCP §6.5）。
3. 組織の**データ保持**の設定と、商用利用規約・データ処理契約（DPA）を確認します。プライバシーポリシー（`site/privacy.html` §3）の「API の入力と出力は学習に使われず、原則 30 日以内に削除」と違えば、ポリシーを直してください（ZDR を契約した場合は「保持しない」に）。
4. Secret Manager に入れます（入れ物は Terraform が作成済み。クライアントには一切渡しません。LEARN_GCP §4.7）:
   ```bash
   cd firebase/functions && npm ci
   npx firebase functions:secrets:set ANTHROPIC_API_KEY --project <projectId> --config ../firebase.json
   ```
5. **モデル**: Functions のパラメータ `CLAUDE_MODEL` に、その時点で最新の**安価な Haiku 系**モデルの ID を設定します（画像入力・構造化出力に対応していること。ID は Anthropic のドキュメントの「Models overview」で確認）。**このリポジトリにはモデル ID を書きません**（`check_release.sh` が検査）。GitHub の環境 `firebase-prod` の**変数** `CLAUDE_MODEL`、手元からなら `firebase/functions/.env.<projectId>`（git には入れない）。

### 1.8 Firebase のクライアント設定と App Check（1 時間）
Terraform が Android アプリの登録まで済ませています。ここでは Terraform では作れないものを行います。
1. クライアント設定を作ります:
   ```bash
   dart pub global activate flutterfire_cli
   cd app && flutterfire configure --project=<projectId> --platforms=android \
     --android-package-name=com.fru69syo.doodle_battle
   # → app/lib/firebase_options.dart と app/android/app/google-services.json ができる
   base64 -w0 lib/firebase_options.dart          # → secret FIREBASE_OPTIONS_DART_B64
   base64 -w0 android/app/google-services.json   # → secret GOOGLE_SERVICES_JSON_B64
   ```
   この 2 つのファイルはリポジトリに入れず、secret から作ります（`write_firebase_config.sh --require` がプレースホルダーを拒否）。
2. Firebase コンソール → プロジェクトの設定 → Android アプリに **SHA-256 が 3 つ**あることを確認します（§1.3 のアプリ署名鍵・アップロード鍵は Terraform で登録済み。開発用の debug 鍵は `keytool -list -v -keystore ~/.android/debug.keystore -storepass android` で足す）。
3. **App Check**: Play Console → 設定 → アプリの完全性 → **Play Integrity API** → このプロジェクトをリンクします。Firebase コンソール → App Check で Android アプリの Play Integrity が「登録済み」であることを確認。QA の開発ビルドは**デバッグトークン**を登録します。Functions と対戦サーバーは最初から App Check を確認します。Firestore・Storage の「適用」は公開の 1〜2 週間後（LEARN_GCP §4.11）。
4. Firebase コンソール → **Crashlytics** を有効にします。レポートは**保護者が「ふぐあいの じょうほうを おくる」をオンにした端末からだけ**届きます（初期値オフ。COMPLIANCE §4）。

### 1.9 Firebase をデプロイする（Functions・ルール・インデックス、30 分）
**初回だけは手元から**（Storage のルールが Firestore を参照するための権限付与など、確認のプロンプトに答える必要があるため。LEARN_GCP §4.8）:
```bash
cd firebase/functions && npm ci
printf 'CLAUDE_MODEL=%s\n' '<最新の Haiku 系モデル ID>' > .env.<projectId>   # git には入らない
npx firebase deploy --config ../firebase.json --project <projectId> --only functions,firestore,storage
```
- `firestore` で**ルールとインデックス**（`firebase/firestore.indexes.json`）が入ります。v2.0 で増えた **`rtMatches`（`playerUids` array-contains + `endedAtMs` 降順）**は、対戦相手の通報（`reportCharacter` の「最近の 50 試合で会った相手か」の確認）とデータ削除に使います。Firebase コンソール → Firestore → **インデックス**で、すべて「有効」（作成中なら 5〜15 分待つ）になったことを確認します。`replays.expireAt` の **TTL**（30 日で自動削除）も「TTL」タブで「有効」を確認します。
- これでキルスイッチ `onBudgetAlert` も Pub/Sub `budget-alerts` につながります（§1.6）。
- 2 回目からは GitHub → Actions → **Deploy Firebase (manual)**（env を選び、プロジェクト ID を 2 回入力）。
- 運用: `moderationQueue`（通報）と `aiSuggestionReports`（AI の提案への通報）を見る担当と頻度（例: 週 2 回）を決めます（BACKEND §14.8）。

### 1.10 対戦サーバーをデプロイする（20 分）
1. GitHub → Actions → **Deploy realtime server (manual)** → env `prod` → Run（承認）。テスト → イメージ → Cloud Run → `/healthz` → だめなら前の版に戻す、まで自動です（LEARN_GCP [§4.9](LEARN_GCP.md)）。
2. 確認（LEARN_GCP §4.10）:
   ```bash
   URL=$(cd infra/terraform/envs/prod && terraform output -raw realtime_url)
   curl -s "$URL/healthz"        # {"ok":true,"draining":false,"engine":"v3",…}
   ```
3. アプリに渡す URL は、この `https://…` を **`wss://…/v2`** にしたものです（例: `wss://battle-xxxx-an.a.run.app/v2`）。§1.12 で環境 `play-release` の変数 `REALTIME_URL` に入れます。release.yml はこれが無いと失敗します（無いビルドではオンラインが「じゅんびちゅう」になるため）。

### 1.11 AdMob（1 時間、審査 1〜3 日）
広告は **Android 版だけ**です（iPhone 版は広告なし。SPEC §10.2）。
1. AdMob アカウントを作り、支払い・税務情報を登録します。
2. アプリを追加（Android、ストア公開前なら「未公開」で作成し、公開後にストアと紐づけ）し、**リワード広告ユニット**を 1 つ作ります。
3. AdMob の設定（コードでも設定済み。`check_release.sh` がコードの設定を検査）:
   - アプリの設定 → **子ども向けの扱い**（Families / 児童向け）を有効にします。
   - ブロックの管理 → 広告コンテンツの最大レーティング **G**、センシティブなカテゴリをすべてブロック。
   - コード側: `ageRestrictedTreatment=child`、`tagForChildDirectedTreatment=yes`、`tagForUnderAgeOfConsent=yes`、`maxAdContentRating=G`、パーソナライズしない、メディエーションなし、**広告 ID の権限なし**、保護者が許可するまで SDK を初期化しない（COMPLIANCE §2）。
4. **アプリ ID**（`ca-app-pub-...~...`）と**リワード広告ユニット ID**（`ca-app-pub-.../...`）を、環境 `play-release` の secret `ADMOB_APP_ID`・`ADMOB_REWARDED_UNIT_ID` に入れます（§1.12）。何も設定しないビルド（開発・CI）は Google の**テスト ID** になり、release.yml は secret が無い・テスト用だと失敗します。
5. **app-ads.txt**: Play に登録した「ウェブサイト」の**ドメインの直下**（`https://fru69syo.github.io/app-ads.txt`）に置きます（§1.13 の B）。

### 1.12 GitHub の設定（30 分）
1. Settings → Environments（`play-release` と prod の環境は Required reviewers にオーナー）:

| 環境 | 種類 | 名前 | 中身 |
|---|---|---|---|
| `play-release` | secret | `ANDROID_KEYSTORE_BASE64` | `upload-keystore.jks` の base64（1 行） |
| | secret | `ANDROID_KEYSTORE_PASSWORD`・`ANDROID_KEY_PASSWORD` | キーストアと鍵のパスワード |
| | secret | `ANDROID_KEY_ALIAS` | `upload` |
| | secret | `PLAY_SERVICE_ACCOUNT_JSON` | §1.4 の JSON の中身 |
| | secret | `FIREBASE_OPTIONS_DART_B64`・`GOOGLE_SERVICES_JSON_B64` | §1.8 の base64 |
| | secret | `ADMOB_APP_ID`・`ADMOB_REWARDED_UNIT_ID` | §1.11。**必須** |
| | variable | **`REALTIME_URL`** | §1.10 の `wss://…/v2`。**必須（v2.0）** |
| | variable（任意） | `POLICY_BASE_URL` | ポリシーのページを既定（`https://fru69syo.github.io/doodle-battle/`）から変えるときだけ |
| リポジトリ | variable | `DEVELOPER_NAME`・`SUPPORT_EMAIL`・`ADMOB_PUBLISHER_ID`・`PAGES_ENABLED` | ポリシーのサイト（§1.13） |
| `firebase-<env>` | variable | `GCP_PROJECT_ID`・`GCP_WIF_PROVIDER`・`GCP_FIREBASE_DEPLOY_SA`・`CLAUDE_MODEL` | §1.5・§1.7（鍵は不要） |
| `realtime-<env>` | variable | `GCP_PROJECT_ID`・`GCP_WIF_PROVIDER`・`GCP_DEPLOY_SA` | LEARN_GCP §4.5 |
| `infra-<env>-plan` / `infra-<env>` | variable | `GCP_PROJECT_ID`・`GCP_PROJECT_NUMBER`・`GCP_WIF_PROVIDER`・`GCP_WIF_POOL`・`TF_STATE_BUCKET`・`BILLING_ACCOUNT_ID`・`ALERT_EMAIL`・`GCP_TF_PLAN_SA`／`GCP_TF_APPLY_SA` | LEARN_GCP §4.5 |

   - `play-release` の「Deployment branches and tags」を **タグ `v*` だけ**に制限します。手動で実行するときは「Use workflow from」で**タグを選んで**ください。
   - **`IAP_ENABLED` はどこにも設定しません**（v2.0 は課金なし。release.yml は渡さず、`check_release.sh` が BILLING 権限を見つけたら失敗します）。
2. Settings → Branches → `main` に保護ルール: PR 必須、ステータスチェック必須、force push 禁止。
3. Settings → Actions → General: 「Read repository contents permission」を既定に。

### 1.13 プライバシーポリシー・サポート・削除ページの公開（1 時間）
ページの中身は `site/`（2026-10-14 に v2.0 用に改定: お絵かきツール、リアルタイム対戦とレート、課金なし）。デベロッパー名・問い合わせ先メール・AdMob の pub ID は `{{…}}` のプレースホルダーで、`scripts/build_site.py` が置き換えます。詳しくは COMPLIANCE §5。

**private リポジトリの GitHub Pages は有料プランでしか使えません。** 次のどちらかにします。
- **A（有料プランがある）**: Settings → Pages → Source「GitHub Actions」。リポジトリ変数を設定して `PAGES_ENABLED=true`。app-ads.txt だけは B のユーザーサイトの直下に置く必要があります。
- **B（推奨・無料）**: 公開用の**別の public リポジトリ** `fru69syo/fru69syo.github.io` に、`build_site.py --out` で作ったファイルを置きます（COMPLIANCE §5.2 のコマンド）:
```
fru69syo.github.io/
  app-ads.txt                    ← AdMob（§1.11）。ドメインの直下
  doodle-battle/index.html       ← サポートページ
  doodle-battle/privacy.html     ← プライバシーポリシー
  doodle-battle/terms.html       ← 利用規約
  doodle-battle/delete.html      ← データ削除ページ（Play の要件）
  doodle-battle/style.css
```
- ページには広告やトラッキングを**入れません**（`build_site.py --check` が `<script>` を拒否）。
- 公開前なのでポリシー版は 1 のままです。**公開したあとで**ポリシーを変えたら、アプリの `currentPolicyVersion` を上げて保護者に再同意してもらいます（BACKEND §3）。
- **削除ページの運用**: ウェブからの依頼は、サポート ID（= uid）を確認して `deleteMyData` と同じ処理をする必要があります。管理スクリプトはまだ無いので、当面は Firebase コンソールで `users/{uid}`・その uid の `snapshots`（と Storage の画像）・`rtMatches`・`replays`・`reports`・`aiSuggestionReports` を消し、Authentication から uid を削除します（30 日以内。§7-5）。

### 1.14 Play Console の入力（2 時間）
`docs/STORE_LISTING.md` のとおりに入力します。
1. ストアの設定（カテゴリ「カジュアル」、タグ、連絡先）。
2. メインのストア掲載情報: `store/metadata/ja-JP/` の文とグラフィック（スクリーンショット 8 枚・フィーチャーグラフィック・アイコン）。`bundle exec fastlane android metadata dry_run:true` で検証 → `metadata` でアップロード（手入力でもよい）。
3. アプリのコンテンツ（ポリシー → アプリのコンテンツ）:
   - プライバシーポリシーの URL
   - **広告**: 「はい、広告を含む」
   - **アプリのアクセス権**: 保護者ゲートの答え方とオンラインの条件（STORE_LISTING §5）
   - **コンテンツのレーティング**（IARC。STORE_LISTING §4。v2.0 は「デジタル商品の購入: いいえ」）
   - **ターゲット層とコンテンツ**: 6〜8 歳・9〜12 歳、ファミリーポリシーに同意（STORE_LISTING §5）
   - **データセーフティ**（STORE_LISTING §6。v2.0 のデータの流れで確認済み）と**データの削除の URL**（`delete.html`）
   - **広告 ID**: 使用しない
   - 政府機関・金融・健康・ニュース: いいえ
4. **アプリ内アイテムは作りません**（v2.0 は無料・課金なし。STORE_LISTING §8）。
5. 配信国: 日本。

---

## 2. バージョンとビルド

### 2.1 バージョンの付け方
タグから決めます（`scripts/version_from_tag.sh`）。`app/pubspec.yaml` の `version:` は **2.0.0+2000099**（次の正式版と同じ）にしてあり、リリースのビルドでは `--build-name` / `--build-number` で上書きします。

| タグ | versionName | versionCode | 用途 |
|---|---|---|---|
| （手で 1 回） | 2.0.0-rc.0 | 1 | §1.3 の登録用（テスターに配らない） |
| `v2.0.0-rc.1` | 2.0.0-rc.1 | 2000001 | 内部テストで確認する候補（rc は 1〜98） |
| `v2.0.0-rc.2` | 2.0.0-rc.2 | 2000002 | |
| `v2.0.0` | 2.0.0 | 2000099 | 製品版にする版（QA に合格した rc と同じコミットに付ける） |
| `v2.0.1` | 2.0.1 | 2000199 | 修正版 |

- versionCode = MAJOR×1,000,000 + MINOR×10,000 + PATCH×100 + (rc 番号 または 99)。MINOR と PATCH は 0〜99。
- 同じバージョンの正式版は、必ずその rc より大きい番号になります。同じタグを作り直してもう一度アップロードすることはできません（Play が同じ versionCode を拒否します）。作り直すときは次の rc を切ってください。
- リリースノートは `store/metadata/ja-JP/changelogs/default.txt`（v2.0.0、はじめての配信）。版ごとに変えるときは `<versionCode>.txt`（例 `2000199.txt`）を足します。

### 2.2 署名
`app/android/app/build.gradle.kts`:
- `app/android/key.properties` があれば、その鍵（アップロード鍵）で release を署名します。
- 無ければ debug 鍵で署名します（`flutter run --release` を手元で使えるようにするため）。debug 鍵の AAB は `check_release.sh --require-upload-key` が失敗させ、Play も受け付けません。

### 2.3 R8・リソースの縮小・課金の権限
- `isMinifyEnabled = true`、`isShrinkResources = true`、`proguard-rules.pro`。`mapping.txt` は release.yml が Artifact に保存し、fastlane が Play にもアップロードします。Dart は `--obfuscate --split-debug-info=build/symbols`（シンボルは Artifact）。
- **課金オフ（`IAP_ENABLED` なし）の release ビルドは、`src/noIap/AndroidManifest.xml` で BILLING 権限を外します**（Play Billing Library が足すため。残っていると Play が「アプリ内購入あり」と表示します）。`build.gradle.kts` が Flutter の `dart-defines` を読んで切り替えます。

### 2.4 手元での署名付きビルドと検査
```bash
source /opt/sdk/env.sh                      # この開発環境の場合
cd app && flutter build appbundle --release --build-name 2.0.0 --build-number 2000099 \
  --dart-define REALTIME_URL=wss://<host>/v2
cd .. && scripts/check_release.sh app/build/app/outputs/bundle/release/app-release.aab \
          --require-upload-key --expect-version-code 2000099 --expect-version-name 2.0.0
scripts/check_16kb.sh app/build/app/outputs/bundle/release/app-release.aab
python3 scripts/check_listing.py
```
- メモリの少ない環境では Gradle のヒープを下げます（例 `GRADLE_OPTS=-Dorg.gradle.jvmargs=-Xmx5G` か `~/.gradle/gradle.properties`）。Maven Central が 429 を返すときは、キャッシュ済みの `GRADLE_USER_HOME` を使います。
- 2026-10-14 の計測（v2.0.0+2000099、debug 鍵、`--obfuscate` なし）: §8 を参照。

---

## 3. CI/CD（GitHub Actions）

| ワークフロー | きっかけ | やること |
|---|---|---|
| `ci.yml` | PR、`main` への push、手動 | 変更があった部分だけ実行: Flutter（format・analyze・test とカバレッジの基準）、TS バトルエンジンのテスト、Functions（lint・build・unit・emulator）、Android の debug APK とリリース用マニフェストの検査、**ストアの掲載情報の検査（`check_listing.py`）**、actionlint。`main` への push では release AAB も作って 16 KB を確認 |
| `release.yml` | タグ `v*` の push、手動 | 署名付き AAB（`REALTIME_URL` 必須、課金オフ）→ 検査（署名・権限・targetSdk・課金・広告・16 KB）→ Artifact（AAB・mapping・シンボル、90 日）→ fastlane で**内部テスト**にアップロード |
| `functions-deploy.yml` | **手動だけ** | lint と unit テスト → Functions・ルール・インデックスのデプロイ。認証は Workload Identity 連携 |
| `realtime-ci.yml` | `server/realtime/**` などの PR・`main` | 対戦サーバーの lint・テスト・イメージのビルド |
| `realtime-deploy.yml` | **手動だけ** | テスト → イメージ → Cloud Run → `/healthz` → 失敗したら前の版に戻す |
| `infra-ci.yml` / `infra-apply.yml` | `infra/**` の PR / **手動だけ** | `terraform fmt`・`validate`・`tflint` / plan → 承認 → apply |
| `pages.yml` | `site/` の変更、手動 | `build_site.py --check`。`PAGES_ENABLED=true` なら公開 |

`scripts/check_release.sh` が見ること（v2.0）:
- 権限の許可リスト: CAMERA、INTERNET、ACCESS_NETWORK_STATE、WAKE_LOCK・RECEIVE_BOOT_COMPLETED・FOREGROUND_SERVICE（ライブラリ由来）、WRITE/READ_EXTERNAL_STORAGE（maxSdkVersion ≤ 28 のときだけ）。AD_ID・ACCESS_ADSERVICES_*、位置情報、RECORD_AUDIO、連絡先、READ_MEDIA_*、POST_NOTIFICATIONS、FCM、インストールリファラなどは理由つきで失敗。
- **課金**: BILLING 権限があれば失敗（`--iap` を付けたときだけ許可）。`app_config.dart` の `IAP_ENABLED` の既定がオフであること。
- **広告**: AdMob のアプリ ID の形式（`--require-real-admob` でテスト ID を拒否）、`DELAY_APP_MEASUREMENT_INIT=true`、広告リクエストが子ども向け（`admob_gateway.dart` の ageRestrictedTreatment・TFCD・TFUA・G・パーソナライズなし・メディエーションなし）、広告は Android だけ（`adsSupportedProvider`）。
- Crashlytics の初期値オフ、Analytics なし、ARCore は optional、`uses-feature` はすべて required=false、minSdk 24・targetSdk 36、debuggable・cleartext・testOnly なし、署名の鍵、versionCode/versionName。
- **リポジトリに Claude のモデル ID が無いこと**（SPEC §11.1）。

---

## 4. リリースの流れ

### 4.1 リリース候補（内部テスト）
1. `main` の CI がすべて緑であることを確認します。§1 がすべて終わっていること（特に `REALTIME_URL`、Firebase のデプロイとインデックス、対戦サーバー）。
2. `git tag v2.0.0-rc.1 && git push origin v2.0.0-rc.1`
3. Actions → Release (Play internal) が動きます。環境 `play-release` の承認を求められたら承認します。
   - アプリをまだ一度も公開していない（「下書き」の）間は、手動実行で `release_status: draft` を選ぶ必要があります。その場合は Play Console で内部テストのリリースを開いて「公開」します。
4. 内部テスター（QA の大人の Google アカウント、最大 100 人）に配信されます。
5. `docs/QA_CHECKLIST.md` を実施します（2 台の端末と古い Android を含む。1〜2 日）。不具合があれば修正して `v2.0.0-rc.2` を切ります。

### 4.2 製品版にする版を作る
1. QA に合格した rc と**同じコミット**に `v2.0.0` を付けて push します（versionCode 2000099）。
2. 内部テストに上がった 2000099 を、スモークテスト（QA_CHECKLIST の「S」）で確認します（約 1 時間）。
3. クローズドテストに昇格させます:
   ```bash
   cd app/android
   export BUNDLE_GEMFILE=fastlane/Gemfile PLAY_JSON_KEY_PATH=/path/play.json
   bundle exec fastlane android promote_to_closed version_code:2000099        # internal → alpha
   ```

### 4.3 クローズドテスト（個人アカウントの場合は必須）
- 2023 年 11 月 13 日以降に作った**個人**デベロッパーアカウントは、「**12 人以上のテスターが 14 日間続けてオプトインしている**クローズドテスト」を行ってからでないと、製品版へのアクセスを申請できません。条件を満たしたら、Play Console のダッシュボードから申請します。審査は通常 7 日以内で、クローズドテストの内容、アプリについて、製品版の準備について質問されます。
  （出典: Play Console ヘルプ「新しいデベロッパー アカウントのアプリのテスト要件」 <https://support.google.com/googleplay/android-developer/answer/14151465>、2026-10-09 に確認）
- 進め方:
  - テスターは**保護者（大人）の Google アカウント**で集めます（子どもが遊ぶのを見てもらう）。脱落に備えて **15〜20 人**。Google グループを作ってトラックに登録すると管理が楽です。
  - オプトインの URL を送り、**アプリを実際にインストールして**もらいます。14 日の間に 12 人を下回らないように、1 週目の終わりに人数を確認します。
  - お願いすること（例）: 紙の絵とアプリの絵で 1 体ずつ作る、ぼうけんを 10 ステージ、かぞくで たいせん 1 回、（許可してくれる家庭は）オンライン対戦。感想は Google フォームなど（子どもの名前や顔写真を送らないように書く）。
  - 期間中もアップデートは出してかまいません（rc → 正式版の流れは同じ）。フィードバックと直したことは申請の質問で使うので記録しておきます。
- 組織アカウントにはこの条件はありませんが、クローズドテストで実機の確認をすることを推奨します。

### 4.4 製品版（段階的公開）
1. 「製品版」のページで国（日本）を選び、リリースノートを確認します。
2. 10% から始めます:
   ```bash
   bundle exec fastlane android promote_to_production version_code:2000099 rollout:0.1   # alpha → production
   ```
   初回は Google の審査（ファミリー向けアプリは数日〜1 週間かかることがある）が入ります。
3. 広げる目安（各段階で 24〜48 時間見る）:

| 段階 | コマンド | 次に進む条件 |
|---|---|---|
| 10% | `promote_to_production ... rollout:0.1` | Android vitals のクラッシュ率 < 1.09%、ANR 率 < 0.47%、Crashlytics に新しい重大なクラッシュが無い、Functions と対戦サーバーのエラー率に変化なし（LEARN_GCP §9 のダッシュボード）、コストモードが normal のまま、保護者からの重大な報告なし |
| 25% | `rollout version_code:2000099 rollout:0.25` | 同上 |
| 50% | `rollout ... rollout:0.5` | 同上 |
| 100% | `rollout ... rollout:1` | |

### 4.5 ロールバック
Play では、一度出した版より**小さい versionCode に戻すことはできません**。問題が見つかったら:
1. **段階的公開を止める**: `bundle exec fastlane android halt_rollout version_code:2000099 rollout:<今の割合>`（または Play Console で「公開を停止」）。
2. **修正版を出す**: 修正（または revert）して `v2.0.1` を切り、§4.1〜4.4 を短縮して行います。
3. **サーバー側**: Functions やルールなら前のタグで `functions-deploy.yml` を手動実行、対戦サーバーなら `realtime-deploy.yml`（失敗時は自動で前のリビジョンに戻る）。対戦サーバーのエンジンが変わると対戦中の試合は中断されます。Firestore のデータを壊す変更は、デプロイ前に `gcloud firestore export` を取ります。
4. **費用が急に増えたとき**: Firestore コンソールで `config/costMode` を `{mode: "minimal", pinned: true}` にすると、AI と対人戦をすぐ止められます（子どもの画面は変わらない。LEARN_GCP §6.4）。

---

## 5. fastlane のレーン

`app/android` で `export BUNDLE_GEMFILE=fastlane/Gemfile PLAY_JSON_KEY_PATH=...` のあと `bundle exec fastlane android <lane> [key:value ...]`。

| レーン | 内容 |
|---|---|
| `validate_key` | サービスアカウントで API に届くか確認 |
| `internal aab:<path> mapping:<path> status:<completed\|draft>` | 内部テストへアップロード（release.yml が使う）。リリースノートは `changelogs/<versionCode>.txt`、無ければ `default.txt` |
| `promote_to_closed version_code:<n> [from:internal] [to:alpha]` | テストトラック間の昇格 |
| `promote_to_production version_code:<n> [from:alpha] [rollout:0.1]` | 製品版へ段階的公開 |
| `rollout version_code:<n> rollout:<0-1>` | 公開の割合を変える（1 で完了） |
| `halt_rollout version_code:<n> rollout:<今の割合>` | 段階的公開を停止 |
| `metadata [dry_run:true]` | 掲載文とグラフィック（スクリーンショットを含む）をアップロード |

---

## 6. よくあるエラー

| 症状 | 対処 |
|---|---|
| `Package not found: com.fru69syo.doodle_battle` | 最初の AAB を Play Console から手でアップロードしていない（§1.3） |
| `Only releases with status draft may be created on draft app` | アプリがまだ一度も公開されていない。`release_status: draft` で実行し、Console で公開 |
| `APK specifies a version code that has already been used` | 同じタグを作り直した。次の rc を切る |
| `The caller does not have permission` | Play Console でサービスアカウントの権限が足りない、または反映待ち（§1.4） |
| `variable REALTIME_URL … must look like wss://…/v2` | 環境 `play-release` の変数 `REALTIME_URL` が無い・形が違う（§1.10・§1.12） |
| `check_release: forbidden permission com.android.vending.BILLING` | `IAP_ENABLED=true` でビルドした、または `src/noIap` の上書きが効いていない。v2.0 は課金なし（§2.3）。課金を有効にする版なら `--iap`（STORE_LISTING §8） |
| `check_release: forbidden permission com.google.android.gms.permission.AD_ID` | 広告や Firebase のライブラリが権限を足した。マニフェストで `tools:node="remove"` |
| `check_release: … Claude model id … in the repo` | モデル ID を書いてしまった。`CLAUDE_MODEL`（GitHub の変数か `.env.<projectId>`）に移す |
| `firebase_options.dart is missing` / `is not a real Firebase config` | secret `FIREBASE_OPTIONS_DART_B64` が無い（§1.8） |
| `Missing secrets in environment play-release: ADMOB_APP_ID …` | AdMob の secret が無い（§1.11・§1.12） |
| `check_release: AdMob APPLICATION_ID is Google's *test* app id` | `ADMOB_APP_ID` が Gradle に渡っていない |
| 起動直後に「The Crashlytics build ID is missing」で落ちる | `res/values/crashlytics.xml`（`RequireBuildId=false`）が消えた（COMPLIANCE §4） |
| オンラインが「じゅんびちゅう」のまま | ビルドに `REALTIME_URL` が無い、または Firebase 未設定 |
| オンラインの通報が失敗する（Functions のログに `FAILED_PRECONDITION` … index） | `rtMatches` のインデックスが未作成・作成中（§1.9） |
| GitHub Actions で `Permission 'iam.serviceAccounts.getAccessToken' denied` | Workload Identity 連携の設定違い（LEARN_GCP §11） |
| Functions のデプロイで `CLAUDE_MODEL` を聞かれて止まる | 環境変数 `CLAUDE_MODEL` か `.env.<projectId>` が無い（§1.7） |
| App Check で本番のアプリが弾かれる | アプリ署名鍵の SHA-256 が未登録、または Play Integrity のリンクがない（§1.8） |

---

## 7. 決まっていないこと（PM 判断）

1. デベロッパーアカウントを個人で作るか組織で作るか（クローズドテストの条件が変わる）。SPEC §17.7。
2. ターゲット年齢に「5 歳以下」を含めるか（SPEC §17.7）。
3. Teacher Approved を狙うか（オンライン対戦が「ソーシャル機能」とみなされると対象外）。
4. 審査担当者がオンライン対戦を確認するための手順（Lv5 にするまで 10〜15 分。STORE_LISTING §5）。
5. ウェブからの削除依頼を処理する管理スクリプト（uid を指定して `deleteMyData` と同じ処理）を Backend チームに作ってもらうか（現状は手作業、§1.13）。
6. 課金を有効にする時期（オーナーの副業申請のあと。手順は STORE_LISTING §8）。
7. ~~Crashlytics を保護者の設定でオフにできるようにするか~~ → **決定**: 保護者が許可したときだけ送る（初期値オフ）。
8. ~~Dart の難読化~~ → **決定**: release.yml で `--obfuscate --split-debug-info`（シンボルは Artifact。Crashlytics へのアップロードは COMPLIANCE §4）。

---

## 8. 計測の記録

| 日付 | ビルド | 結果 |
|---|---|---|
| 2026-10-09 | v1 系、テスト用の鍵 | AAB 61.8 MiB、arm64 のダウンロード 16.9 MiB、64 bit のネイティブライブラリ 22 個すべて 16 KB 境界 |
| 2026-10-09 | v1 系 + AdMob・Billing・Crashlytics | AAB 88.5 MiB、arm64 のダウンロード 26.9 MiB、24 個すべて 16 KB 境界、`check_release.sh` 合格 |
