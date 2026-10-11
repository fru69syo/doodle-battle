# GCP で学ぶ おえかきファイターズのサーバー（オーナー向け学習ガイド）

GCP チーム作成（ブランチ `feat/gcp`、2026-10-11）。v2.0 のサーバー側を、プロのチームと同じやり方で作りました。この文書は、**オーナーが自分の手で動かしながら GCP を学ぶ**ための教科書です。上から順に読めば、最初のセットアップから毎月の運用、片付けまでできます。

- 前提の決定: SPEC §12.6（予算は月 5,000 円まで、超えそうなら自動で止める）、§12.7（クラウドは GCP、学習を兼ねる）
- 関連文書: `docs/V2_INFRA.md`（調査と費用の根拠）、`docs/REALTIME_PROTOCOL.md`（対戦サーバーの通信の決まり）、`docs/BACKEND.md`（Functions とデータ）、`docs/RELEASE.md`（ストアへの公開）
- コード: `infra/terraform/`（構成）、`server/realtime/`（対戦サーバー）、`firebase/functions/src/cost/`（キルスイッチ）、`.github/workflows/`（CI/CD）

> この文書の金額は 2026-10 時点の公開価格からの**目安**です（1 ドル = 150 円で計算）。実際の請求は §10 の方法で毎月確認してください。

---

## 目次

1. 全体の構成図
2. 用語ミニ辞典
3. 使っているサービスと「なぜそれにしたか」
4. はじめてのセットアップ（手順）
5. それぞれの部品をもう少しくわしく
6. 予算とキルスイッチ（自動で節約する仕組み）
7. CI/CD（GitHub Actions）の流れ
8. Terraform のきほん
9. ログとメトリクスの見方
10. 請求書と予算アラートの読み方
11. よくある失敗
12. 費用の目安
13. 片付け・削除
14. 次の一歩（規模が大きくなったら）

---

## 1. 全体の構成図

```
                              ┌─────────────────────── Google Cloud プロジェクト（prod） ───────────────────────┐
 子どものアプリ                │                                                                                  │
 (Android / iOS)               │  Firebase Authentication（匿名）    Firestore（東京）     Cloud Storage（東京）       │
   │  ① 匿名サインイン ───────────►  ID トークン                    users / snapshots     snapshotImages/…       │
   │  ② App Check ───────────────►  Play Integrity / App Attest     rtMatches / replays                        │
   │                             │                                    config/costMode ◄──────────────┐           │
   │  ③ HTTPS（callable）─────────►  Cloud Functions（東京）                                          │           │
   │     judgeDrawing など         │    judgeDrawing ──► Anthropic（Claude）※課金は GCP の外            │           │
   │                             │    registerCharacter / deleteMyData / sweepMatches …              │           │
   │                             │    onBudgetAlert ─────────────────────────────────────────────────┘           │
   │                             │          ▲ Pub/Sub「budget-alerts」                                            │
   │                             │          │                                                                     │
   │                             │  Cloud Billing の予算（¥5,000/月）── メール（50/80/100%）→ オーナー            │
   │                             │                                                                                  │
   │  ④ WebSocket（wss）──────────►  Cloud Run「battle」（東京、0〜1 台）  10 Hz で対戦を進める                     │
   │                             │    ID トークン + App Check を確認 → マッチング → 結果を Firestore に書く        │
   │                             │                                                                                  │
   │                             │  Artifact Registry（コンテナイメージ）  Secret Manager（API キー）               │
   │                             │  Cloud Logging / Monitoring（ログ、ダッシュボード、アラート、死活監視）          │
   │                             └──────────────────────────────────────────────────────────────────────────────┘
                                                      ▲
 GitHub（fru69syo/doodle-battle）                      │ Workload Identity 連携（鍵なしで一時的な権限）
   PR → realtime-ci / infra-ci / ci（テスト）          │
   手動 → realtime-deploy / infra-apply / functions-deploy（承認してから本番へ）
   Terraform の状態ファイル → GCS バケット「<project>-tfstate」
```

ポイントは 3 つです。

- **ふだんの処理は Firebase**（v1 と同じ）。v2.0 で増えたのは、リアルタイム対戦用の **Cloud Run** と、費用を守る **予算 → Pub/Sub → キルスイッチ** です。
- **すべての構成は Terraform のコード**（`infra/terraform/`）。画面でポチポチ作らないので、何があるかがコードを読めば分かり、作り直しもできます。
- **GitHub から GCP へは鍵（JSON ファイル）を使わない**。Workload Identity 連携で、そのつど 1 時間だけ有効な権限をもらいます。

環境は **dev（開発用）** と **prod（本番）** の 2 つのプロジェクトに分けます。同じ Terraform のモジュールを、設定だけ変えて使います（§8.4）。

---

## 2. 用語ミニ辞典

| 用語 | 意味（このプロジェクトでの例） |
|---|---|
| プロジェクト | GCP の入れ物。お金・権限・データはプロジェクトごと。例 `doodle-battle-prod` |
| 請求先アカウント（Billing account） | クレジットカードがつながった財布。プロジェクトを紐付けると有料の機能が使える |
| リージョン | データセンターの場所。ここではほぼ **asia-northeast1（東京）** |
| API（サービス） | GCP の機能は「API を有効にする」と使える（有効にするだけなら無料） |
| IAM | 「だれが」「何を」できるかの設定。だれ（プリンシパル）にロールを付ける |
| ロール | 権限のまとまり。例 `roles/datastore.user` = Firestore の読み書き |
| サービスアカウント（SA） | プログラム用のアカウント。例 `battle-server@…` は対戦サーバーとして動く |
| 最小権限 | 必要な権限だけを付けること。事故や乗っ取りの被害を小さくする |
| Workload Identity 連携（WIF） | 外部（GitHub）の身分証を Google の一時的な権限に交換する仕組み。鍵が要らない |
| Terraform | 構成をコードで書き、`plan`（差分を見る）→ `apply`（反映）するツール |
| state（状態ファイル） | Terraform が「作ったもの」を覚えておくファイル。GCS バケットに置く |
| コンテナイメージ | アプリと動く環境をひとまとめにしたもの。Docker で作り、Artifact Registry に置く |
| リビジョン | Cloud Run の版。デプロイするたびに新しいリビジョンができ、戻すこともできる |
| コールドスタート | 0 台から 1 台目を起動するときの待ち時間（1〜3 秒） |
| ログベースの指標 | ログの行を数えてグラフにしたもの（例「試合が終わった回数」） |

---

## 3. 使っているサービスと「なぜそれにしたか」

| サービス | ここでの役割 | なぜこれ（ほかの案） |
|---|---|---|
| **Firebase Authentication**（匿名） | 子どもの端末を区別する uid を発行。メールや電話番号は使わない | 個人情報を集めない。v1 から使っている。Terraform で管理するため Identity Platform に切り替える（§11） |
| **Firestore**（東京） | ユーザー、登録キャラ、対戦結果、設定（`config/costMode`）を保存 | v1 と同じ。サーバーなしで使え、少量なら無料枠に収まる |
| **Cloud Storage** | 登録キャラの画像 | Firebase のルールで読み取りを制限できる |
| **Cloud Functions**（第 2 世代） | AI の判定、キャラ登録の審査、削除、キルスイッチ | 呼ばれたときだけ動くので安い。v1 から使っている |
| **Cloud Run** | リアルタイム対戦サーバー（WebSocket、10 Hz） | Functions は長い接続を持てない。Cloud Run はコンテナを置くだけで HTTPS と WebSocket が使え、**使われていないときは 0 台（料金 0）** にできる。GKE（Kubernetes）は月 1 万円以上かかり、運用も重い（V2_INFRA §3.2） |
| **Artifact Registry** | 対戦サーバーのコンテナイメージ置き場 | Cloud Run と同じ東京に置くと速く、通信料もかからない。古いイメージは自動で消す |
| **Secret Manager** | `ANTHROPIC_API_KEY` | 鍵をコードや GitHub に置かない。読めるのは Functions のアカウントだけ |
| **IAM / サービスアカウント** | プログラムごとの身分と権限 | 1 つが乗っ取られても、ほかに被害が広がらない |
| **Workload Identity 連携** | GitHub Actions → GCP の認証 | JSON 鍵は漏れると悪用され、期限もない。WIF は 1 時間で切れ、リポジトリと環境を限定できる |
| **Cloud Billing の予算** | 月 ¥5,000。50/80/100% でメール、Pub/Sub に通知 | 予算は「止める」機能ではなく「知らせる」機能。止めるのはキルスイッチ（§6） |
| **Pub/Sub** | 予算の通知をキルスイッチに届ける | 予算の通知の公式な受け口 |
| **Cloud Logging / Monitoring** | ログ、グラフ、アラート、死活監視 | 追加の SaaS なしで、無料枠の中でそろう |
| **Terraform** | 上のすべてをコードで管理 | 画面の操作は忘れる・まちがえる。コードなら PR でレビューでき、何度でも同じものが作れる |
| **GitHub Actions** | テスト、デプロイ、Terraform の実行 | リポジトリと同じ場所。承認（Required reviewers）をはさめる |

**Firebase と GCP の関係**: Firebase のプロジェクトは、中身は GCP のプロジェクトです。Firebase コンソールと Google Cloud コンソールは、同じプロジェクトを別の画面で見ているだけです。

**だれが何を管理するか**（1 つのものを 2 か所で管理すると、お互いに上書きして壊れます）:

| もの | 管理するのは |
|---|---|
| API の有効化、Firestore の作成、Auth の設定、Storage のバケット、アプリの登録、App Check、Cloud Run のサービス、SA と権限、WIF、予算、Pub/Sub、監視、シークレットの「入れ物」 | **Terraform**（`infra/terraform`） |
| Firestore / Storage のセキュリティルール、インデックス、TTL（自動削除）、Cloud Functions | **Firebase CLI**（`firebase deploy`、`functions-deploy.yml`） |
| Cloud Run に載せるイメージ（どの版を動かすか） | **realtime-deploy.yml**（Terraform は最初の 1 回だけ置き、あとは無視する設定） |
| シークレットの「中身」（API キーの値） | **人**（`firebase functions:secrets:set`）。Terraform の state に秘密を残さないため |

---

## 4. はじめてのセットアップ（手順）

全体で半日〜1 日です。まず **dev** で最後まで通し、同じ手順を **prod** でくり返します。

### 4.1 用意するもの
- Google アカウント（オーナー用。2 段階認証を必ずオンに）とクレジットカード
- パソコンに: `gcloud`（Google Cloud CLI）、`terraform`（1.16 以上）、Node.js 22、`git`。Mac なら Homebrew で入ります。インストールが面倒なら、**Cloud Shell**（ブラウザで使える GCP の端末。全部入り）でも OK です
- GitHub のリポジトリの管理者権限

### 4.2 プロジェクトを作って財布をつなぐ（15 分）
```bash
gcloud auth login
gcloud projects create doodle-battle-dev --name="doodle-battle dev"     # ID は世界で 1 つ。使われていたら別名に
gcloud billing accounts list                                              # 請求先アカウント ID（XXXXXX-XXXXXX-XXXXXX）を確認
gcloud billing projects link doodle-battle-dev --billing-account=XXXXXX-XXXXXX-XXXXXX
```
- 請求先アカウントの通貨が **JPY** か確認します（予算は同じ通貨で書く必要があります）。
- Firebase は「Firebase コンソールでプロジェクトを作る」代わりに、Terraform が既存の GCP プロジェクトに Firebase を追加します（`google_firebase_project`）。**Google アナリティクスは使いません**。

### 4.3 bootstrap（最初の 1 回だけ、人が手元で実行。20 分）
Terraform が自分の state を置くバケットや、GitHub から使うアカウントは、Terraform を CI で動かす**前に**必要です（にわとりと卵）。これを `infra/terraform/bootstrap/` で作ります。

```bash
gcloud auth application-default login          # Terraform があなたの権限で動くためのログイン
cd infra/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # project_id, env, billing_account_id を書く（git には入らない）
terraform init
terraform plan                                 # 何が作られるか読む（約 30 個）
terraform apply                                # yes と入力
terraform output                               # 次で使う値が出る
```
作られるもの:
- `gs://doodle-battle-dev-tfstate`（state 用。バージョン管理あり、公開禁止、削除防止）
- `tf-plan@…`（読み取り専用）と `tf-apply@…`（変更できる）の 2 つのサービスアカウント
- 請求先アカウントへの権限（`tf-apply` に予算の管理、`tf-plan` に閲覧）。**請求先アカウントの管理者**でないと失敗します。その場合は `grant_billing_roles = false` にして、請求先の管理者に頼んでください
- Workload Identity プール `github` とプロバイダ `github-actions`。**このリポジトリ（`fru69syo/doodle-battle`）以外のトークンは受け付けません**

bootstrap の state はこのフォルダの `terraform.tfstate`（git には入りません）。なくすと困るので、`backend.tf.example` の手順で、作ったバケットに移しておくと安心です。

### 4.4 環境（dev）を作る（初回は手元から。30 分）
```bash
cd ../envs/dev
cp terraform.tfvars.example terraform.tfvars    # bootstrap の output を写す（project_number, wif_pool_name …）と alert_email
terraform init -backend-config="bucket=doodle-battle-dev-tfstate"
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```
- 初回は API の有効化を待つので 5〜10 分かかります。`403 … API has not been used` が出たら、数分待ってもう一度 `apply` します（§11）。
- `alert_email` に「Google Cloud Monitoring の通知先の確認」メールが届くことがあります。確認してください。
- 対戦サーバーは、最初は Google のサンプル（hello）イメージで作られます。本物は §4.8 で載せます。

### 4.5 GitHub の環境と変数（20 分）
GitHub → Settings → Environments で作ります。**値はすべて Variables（秘密ではない）**です。WIF のおかげで Secrets に鍵を入れる必要がありません。

| 環境 | Required reviewers | Variables |
|---|---|---|
| `infra-dev-plan` | なし | `GCP_PROJECT_ID`, `GCP_PROJECT_NUMBER`, `GCP_WIF_PROVIDER`, `GCP_WIF_POOL`, `TF_STATE_BUCKET`, `BILLING_ACCOUNT_ID`, `ALERT_EMAIL`, `GCP_TF_PLAN_SA` |
| `infra-dev` | オーナー | 上と同じ（`GCP_TF_PLAN_SA` の代わりに `GCP_TF_APPLY_SA`） |
| `realtime-dev` | なし（prod はオーナー） | `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA`（output `realtime_deployer_sa`） |
| `firebase-dev` | なし（prod はオーナー） | `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_FIREBASE_DEPLOY_SA`（output `firebase_deployer_sa`）, `CLAUDE_MODEL` |

prod は同じものを `infra-prod-plan` / `infra-prod` / `realtime-prod` / `firebase-prod` で作り、**prod の 3 つ（infra-prod, realtime-prod, firebase-prod）には必ず Required reviewers を付けます**。
`GCP_WIF_PROVIDER` は `projects/<番号>/locations/global/workloadIdentityPools/github/providers/github-actions` の形です（bootstrap の output）。

> 環境の名前は WIF の許可に使われています（`repo:fru69syo/doodle-battle:environment:realtime-prod` のジョブだけが `gha-realtime-deploy@` になれる）。名前をまちがえると `Permission 'iam.serviceAccounts.getAccessToken' denied` になります。

### 4.6 2 回目からの Terraform は GitHub から
GitHub → Actions → **Terraform apply (manual)** → env を選んで Run。
1. `plan` ジョブが読み取り専用のアカウントで差分を出し、結果を Summary に表示します。
2. 変更があれば `apply` ジョブが承認待ちになります。**Summary の plan を読んでから** Approve します。
3. 承認した plan ファイルそのものが適用されます。途中でだれかが変更していたら Terraform が止めます（「saved plan is stale」）。もう一度実行してください。

### 4.7 シークレットを入れる（10 分）
Terraform が作るのは `ANTHROPIC_API_KEY` の「入れ物」だけです。中身はあなたが入れます。
```bash
cd firebase/functions && npm ci
npx firebase functions:secrets:set ANTHROPIC_API_KEY --project doodle-battle-dev --config ../firebase.json
# 画面に貼り付ける。値は画面にもログにも残りません
```
（`gcloud secrets versions add ANTHROPIC_API_KEY --data-file=-` でも同じです。）
Anthropic Console 側で**月の利用上限**も必ず設定します。AI の費用は GCP の請求に入らないので、GCP の予算では止まりません（§6.5）。

### 4.8 Firebase（Functions・ルール）をデプロイ（15 分）
**初回だけは手元から**（確認のプロンプトがあるため。RELEASE.md §1.7）:
```bash
cd firebase/functions
printf 'CLAUDE_MODEL=%s\n' '<最新の Haiku 系モデル ID>' > .env.doodle-battle-dev   # git には入らない
npx firebase deploy --config ../firebase.json --project doodle-battle-dev --only functions,firestore,storage
```
- これでキルスイッチ `onBudgetAlert` も、Terraform が作った Pub/Sub トピック `budget-alerts` につながります。`cost-guard@` アカウントで動きます。
- 2 回目からは Actions → **Deploy Firebase (manual)**（env を選び、プロジェクト ID を 2 回入力）。

### 4.9 対戦サーバーをデプロイ（10 分）
Actions → **Deploy realtime server (manual)** → env を選んで Run。
テスト → イメージを作って Artifact Registry に push（タグ = コミット）→ Cloud Run に新しいリビジョン → `/healthz` を確認 → だめなら前のリビジョンに自動で戻す、まで自動です。

> いまは Engine v3（Engine チームが作成中）がまだ入っていないので、**dev は仮のエンジン（`BATTLE_ENGINE=dev`）で動きます**。prod は `v3` 以外では起動しない設定にしてあります（仮のルールでレート戦をしないため）。差し替え手順は `docs/REALTIME_PROTOCOL.md` §9。

### 4.10 動作を確かめる
```bash
URL=$(cd infra/terraform/envs/dev && terraform output -raw realtime_url)
curl -s "$URL/healthz"                       # {"ok":true,"draining":false,"engine":"dev",…}
```
アプリ（dev ビルド）からオンライン対戦をして、§9 のダッシュボードで「Matches ended」が増えることを確認します。

### 4.11 App Check を本番にする（公開後 1〜2 週間）
1. Play Console で Play Integrity と Cloud プロジェクトをリンクし、`android_sha256_hashes`（アプリ署名鍵とアップロード鍵）を `terraform.tfvars` に書いて apply（RELEASE.md §1.5）。iOS は `ios_team_id` も。
2. Firebase コンソール → App Check の指標で「確認済み」がほぼ 100% になるのを待つ。
3. `app_check_enforcement = "ENFORCED"` にして apply。Functions と対戦サーバーは最初から確認しています。

---

## 5. それぞれの部品をもう少しくわしく

### 5.1 サービスアカウントと権限（最小権限）
| アカウント | だれが使う | 主なロール | ねらい |
|---|---|---|---|
| `battle-server@` | Cloud Run の対戦サーバー | Firestore の読み書き、ログ、指標 | Storage や Secret は読めない |
| `cost-guard@` | キルスイッチ関数 | Firestore の読み書き、イベントの受信 | 予算の通知を受けて 1 つの文書を書くだけ |
| `gha-realtime-deploy@` | realtime-deploy.yml | Cloud Run の新しい版を出す、自分のリポジトリにイメージを置く、`battle-server@` として動かす | IAM は変えられない |
| `gha-firebase-deploy@` | functions-deploy.yml | Functions・ルール・インデックス・スケジューラ | Terraform の領分は触れない |
| `tf-plan@` | infra-apply.yml の plan | 閲覧のみ | だれでも差分を見られるが、何も変えられない |
| `tf-apply@` | infra-apply.yml の apply | 管理系のロールをまとめて（Owner ではない） | 承認したときだけ使われる |

「`battle-server@` として動かす（actAs）」権限を別に付けるのは、デプロイする人が**自分より強いアカウント**でプログラムを動かすのを防ぐためです。

ほかの Functions は、いまは既定の Compute Engine のアカウントで動いています（v1 のまま）。専用のアカウントに移すのは §14 の「次の一歩」です。

### 5.2 Workload Identity 連携のしくみ
```
GitHub Actions のジョブ（environment: realtime-prod）
  │ ① GitHub に「私は fru69syo/doodle-battle の realtime-prod のジョブです」という署名付きトークンをもらう
  ▼
Google STS（sts.googleapis.com）
  │ ② プロバイダの条件: assertion.repository == "fru69syo/doodle-battle" を確認
  │ ③ subject = repo:fru69syo/doodle-battle:environment:realtime-prod
  ▼
IAM: gha-realtime-deploy@ に「その subject なら workloadIdentityUser」と書いてある
  │ ④ 1 時間だけ有効なアクセストークン
  ▼
gcloud / docker / terraform がそのトークンで動く
```
環境に Required reviewers を付けると、**人が Approve しないとトークンがもらえない** = デプロイできない、という仕組みになります。

### 5.3 Cloud Run の設定の意味（`modules/realtime_service`）
| 設定 | 値 | 理由 |
|---|---|---|
| リージョン | asia-northeast1 | 子どもに一番近い。往復 10〜40 ms |
| 最小インスタンス | **0** | 遊んでいない時間は 0 台 = CPU とメモリの料金 0。最初の接続だけ 1〜3 秒待つが、「あいてを さがしているよ」の画面に隠れる |
| 最大インスタンス | **1** | マッチングの待ち行列と試合がメモリの中にあるので、全員が同じ 1 台につながる必要がある。1 台で数千試合さばけるので、1k〜10k DAU には十分（V2_INFRA §3.3） |
| 同時リクエスト | 250 | WebSocket 1 本 = 1 リクエスト。1 台で 250 人まで |
| セッションアフィニティ | オン | 同じ端末を同じ台に（台が増えたとき用） |
| CPU の割り当て | リクエストのあいだだけ（`cpu_idle = true`） | 接続があるあいだだけ課金。アプリは**対戦の画面でだけ**接続する（REALTIME_PROTOCOL §1） |
| タイムアウト | 900 秒 | WebSocket は長い 1 つのリクエスト。15 分で切れるので、サーバーは試合中でなければ 14 分で自分から閉じ、アプリは黙ってつなぎ直す |
| CPU / メモリ | 1 vCPU / 512 MiB | Node.js 1 つで十分。CPU を 1 未満にはできない設定（同時接続のため） |
| イメージ | Terraform は無視 | デプロイ（CI）とケンカしないように `lifecycle.ignore_changes` |
| 公開 | 認証なしで呼べる（`invoker_iam_disabled`） | 子どものアプリが直接つなぐため。本人確認は通信の最初の `hello` で行う（ID トークン + App Check） |

**新しい版を出すと何が起きるか**: Cloud Run は新しいリビジョンを起動し、新しい接続をそちらに流します。古い台は、つながっている接続が終わるまで（最大 15 分）動き続けます。止めるときは SIGTERM が来るので、サーバーは**進行中の試合をレートを動かさずに終わらせ**（`end reason:"aborted"`）、アプリに「つなぎ直して」と伝えます（`bye`）。デプロイは**子どもが少ない時間（平日の昼）**にしましょう。

### 5.4 コンテナイメージ（`server/realtime/Dockerfile`）
- 2 段階: Node の大きいイメージで TypeScript をビルド → 小さい **distroless**（シェルもパッケージ管理も無い、root で動かない）に結果だけコピー。攻撃の入り口が少なく、直すべき脆弱性も少ない。
- ベースイメージは**ダイジェスト（sha256）で固定**。同じ Dockerfile からいつも同じものができます。月 1 回くらい、新しいダイジェストに上げます。
- Docker Hub の回数制限を避けるため、Google のミラー `mirror.gcr.io` から取ります。
- Artifact Registry は「最新 10 個は残す、30 日より古いものは消す」の自動お掃除つき（0.5 GB までは無料）。

### 5.5 デプロイの安全装置（`realtime-deploy.yml`）
1. テストが通らなければイメージを作らない
2. タグはコミットの SHA。**同じタグは上書きできない**（どのコードが動いているか必ず分かる）
3. デプロイは「イメージのダイジェスト」で指定
4. `/healthz` が 1 分以内に OK にならなければ、**前のリビジョンに自動で戻す**

手で戻すとき: Cloud Run → battle → リビジョン → 前の版を選び「トラフィックを管理」で 100%。または
```bash
gcloud run services update-traffic battle --region asia-northeast1 --to-revisions <前のリビジョン名>=100
```

### 5.6 シークレットの扱い
- Terraform は `ANTHROPIC_API_KEY` の**入れ物**と「だれが読めるか」だけを作ります。値は人が入れるので、Terraform の state にも GitHub にも残りません。
- データは東京だけに保存（レプリカ 1 つ）。消したバージョンは 7 日間は戻せます。
- キーを替えるとき: 新しいバージョンを追加 → Functions を再デプロイ（新しいインスタンスが新しい値を読む）→ 古いバージョンを無効化。

---

## 6. 予算とキルスイッチ（自動で節約する仕組み）

### 6.1 なぜ必要か
Cloud Billing の**予算は「知らせる」だけで、止めてはくれません**。子どもが急に増えたり、バグで無限ループしたりすると、気づくまでお金が出ていきます。そこで、予算の通知を受けて**費用のかかる機能を自動で弱める**仕組みを入れました。子どもの画面は何も変わりません（SPEC §12.7）。

### 6.2 流れ
```
Cloud Billing（数時間おきに今月の合計を計算）
  └─ 予算「doodle-battle prod monthly」¥5,000
       ├─ 50% / 80% / 100%（実績）と 100%（予測）でメール → オーナー
       └─ 1 日に何回も Pub/Sub「budget-alerts」に { costAmount, budgetAmount, … } を送る
             └─ onBudgetAlert（Cloud Functions、cost-guard@ で動く）
                   ├─ AI の今月の見積り（ops/aiUsage_YYYYMM）を足す
                   ├─ 割合 → normal / saving / minimal を決める
                   ├─ 変わったときだけ config/costMode を書く（ログ event=cost_mode_changed → アラートのメール）
                   └─ 毎回 ops/costStatus に状況を書く（Firestore コンソールで見られる）
                         ▼（1 分以内に）
          judgeDrawing / マッチング / 対戦サーバー / アプリ が読んで、こっそり節約する
```

### 6.3 3 つのモード
| モード | いつ | 何が変わるか | 子どもからは |
|---|---|---|---|
| `normal` | 80% 未満 | すべてふつう | – |
| `saving` | **80% 以上**（または予測が 120% 以上） | クラウドの AI 判定・技の生成を止める（端末の判定だけ）。オンラインはゴーストまで 20 秒 → **8 秒** | 判定は端末のものになる（もともと失敗したら端末に切り替わる作り）。待ち時間が少し短くなる |
| `minimal` | **100% 以上** | 上に加えて、子ども同士の対戦を組まない。ゴーストまで **3 秒** | いつもゴーストと対戦（ゴーストも「ほかの子のキャラ」なので違和感は小さい） |

- **安全のための AI（キャラ登録の審査）は止めません**。止めると不適切な名前や絵が公開されるおそれがあるからです（審査できないときは公開しない、という v1 の決まりのまま）。
- 対戦サーバーは、遊ぶ人がいなければもともと 0 台です。
- 月が変わると合計が 0 に戻るので、**自動で normal に戻ります**。予算を増やしたときも、次の通知で戻ります。
- 値（80% / 100% / 8 秒 / 3 秒）は `shared/cost_mode/cost_mode.json` にあり、Functions と対戦サーバーとアプリが同じファイルを使います。

### 6.4 手で切り替える（ピン留め）
Firestore コンソール → `config/costMode` を開き、`mode` を書き換えて **`pinned: true`** を追加します。キルスイッチは pinned の間は何もしません。戻すときは `pinned` を消します（次の通知で自動の判断に戻る）。
- 例: 障害対応中に AI を止めたい → `mode: "saving", pinned: true`
- 例: 月末に予算を超えそうだけど、イベント中なので止めたくない → 予算を Terraform で一時的に上げる（`monthly_budget_jpy`）方が安全です

### 6.5 キルスイッチが守れないもの（大事）
- **請求データは数時間〜1 日遅れます**。だから 100% ではなく 80% で節約を始めます。それでも急な増加には遅れるので、Cloud Run の最大 1 台、Functions の最大インスタンス数、レート制限など、**そもそも上限がある**作りにしています。
- **Anthropic（Claude）の料金は GCP の請求に入りません**。Functions が呼び出し回数から見積った金額（`ops/aiUsage_YYYYMM`、1 回あたり少し多めの見積り）を足して判断しますが、**本当の歯止めは Anthropic Console の月の利用上限**です。必ず設定してください（目安: 月 2,000 円）。
- 「プロジェクトの請求を止める（請求先アカウントの紐付けを外す）」完全停止は、**データが消えるおそれがある**ので自動にはしていません。どうしても必要なら手で: `gcloud billing projects unlink <project>`（Cloud Run・Functions が止まり、Firestore も読めなくなります。紐付け直せば戻りますが、長く放置すると削除されることがあります）。

### 6.6 試してみる（dev で）
```bash
gcloud pubsub topics publish budget-alerts --project doodle-battle-dev \
  --message '{"budgetDisplayName":"test","costAmount":450,"budgetAmount":500,"currencyCode":"JPY"}'
```
→ 1 分以内に Firestore の `config/costMode` が `saving` になり、アラートのメールが届きます。`costAmount` を 0 にして送れば `normal` に戻ります。

---

## 7. CI/CD（GitHub Actions）の流れ

| ワークフロー | きっかけ | やること | 本番に触る？ |
|---|---|---|---|
| `ci.yml` | PR / main | アプリ、エンジン、Functions（エミュレータのテスト込み）、actionlint | いいえ |
| `realtime-ci.yml` | `server/realtime/**` などの PR / main | lint、単体テスト、結合テスト（2 人の WebSocket クライアントが 1 試合する）、Firestore エミュレータのテスト、イメージのビルド | いいえ |
| `infra-ci.yml` | `infra/**` の PR / main | `terraform fmt`、`validate`、`tflint` | いいえ（認証なし） |
| `realtime-deploy.yml` | **手動** | テスト → イメージ → Cloud Run → ヘルスチェック → だめなら戻す | はい（prod は承認） |
| `infra-apply.yml` | **手動** | plan（読み取り専用）→ 承認 → apply | はい（承認） |
| `functions-deploy.yml` | **手動** | lint・テスト → `firebase deploy` | はい（prod は承認） |

- サードパーティのアクションは**コミット SHA で固定**しています（タグは書き換えられることがあるため）。
- `push` だけで本番が変わることはありません。

---

## 8. Terraform のきほん

### 8.1 3 つのコマンド
```bash
terraform init      # プロバイダ（Google 用のプラグイン）を取ってくる、state の場所につなぐ
terraform plan      # 「コード」と「いまの GCP」の差を表示する。何も変えない
terraform apply     # 差をなくすように GCP を変える
```
plan の記号: `+` 作る、`~` 変える、`-` 消す、`-/+` 消して作り直す（**データが消えるものに `-/+` が出たら止まって相談**）。

### 8.2 state とロック
- state は「Terraform が作ったものの一覧」です。GCS バケットに置き、**同時に 2 人が apply しないようロック**されます。
- バケットはバージョン管理つきなので、壊れても前の版に戻せます（Cloud Storage → バケット → オブジェクト → バージョン）。
- `ロックが取れない (Error acquiring the state lock)` が出たら、前の実行が途中で止まった可能性があります。だれも実行していないことを確かめてから `terraform force-unlock <ID>`。

### 8.3 フォルダの構成
```
infra/terraform/
  bootstrap/          人が最初に 1 回（state バケット、Terraform 用 SA、WIF）
  envs/dev, envs/prod 環境ごとの入口（main.tf でモジュールを組み合わせる）
  modules/            部品（1 つの役割ごと）
    project_services  API の有効化
    firebase          Firebase、Firestore、Auth、Storage、アプリ、App Check
    artifact_registry イメージ置き場
    service_accounts  SA、権限、GitHub からの許可
    github_wif        WIF プール（bootstrap が使う）
    secrets           シークレットの入れ物
    realtime_service  Cloud Run の対戦サーバー
    cost_guard        予算 → Pub/Sub
    monitoring        死活監視、アラート、ログベースの指標、ダッシュボード
```
dev と prod の違いは、削除保護、予算（dev ¥500 / prod ¥5,000）、App Check の必須、エンジンの種類だけです。

### 8.4 オフラインでの確認（CI と同じ）
```bash
cd infra/terraform
terraform fmt -check -recursive
for d in bootstrap envs/dev envs/prod; do (cd $d && terraform init -backend=false && terraform validate); done
tflint --init --config=$PWD/.tflint.hcl
(cd envs/prod && tflint --config=$PWD/../../.tflint.hcl)
```
`-backend=false` なら GCP に一切つながらず、書き方のまちがいを見つけられます。

### 8.5 画面で変えてしまったら（ドリフト）
コンソールで設定を変えると、次の `plan` に「元に戻す」差分が出ます。変更を残したいなら**コードの方を直して** PR、要らないなら apply で戻します。画面の変更は「その場しのぎ」にとどめ、必ずコードに反映しましょう。

### 8.6 すでにあるものを Terraform に取り込む
コンソールで先に作ってしまったもの（例: Storage の既定のバケット）は、`create_default_bucket = false` にするか、`import` ブロックで取り込みます:
```hcl
import {
  to = module.firebase.google_firebase_storage_default_bucket.default[0]
  id = "projects/doodle-battle-prod/defaultBucket"
}
```

---

## 9. ログとメトリクスの見方

### 9.1 ダッシュボード
Cloud Console → Monitoring → ダッシュボード → **「おえかきファイターズ prod」**。週に 1 回見る価値のあるグラフを並べています。
- **Battle server: instances** — 0 なら寝ている（料金 0）。夜にずっと 1 なら、だれかが接続を開きっぱなし（アプリのバグ）
- **billable instance time** — 対戦サーバーの料金にそのまま比例
- **Battle tick lag p95** — 10 Hz の処理の遅れ。50 ms を超えたら CPU 不足を疑う
- **Matches ended (pvp vs ghost)** — PvP が少ないのは、1k DAU では想定どおり（V2_INFRA §3.1）
- **Functions requests / judgeDrawing latency** — AI 判定の回数と速さ
- **Firestore reads/writes**、**Error log entries**、**Auth rejections**、**Cost mode changes**

### 9.2 ログ（Logs Explorer）
Cloud Console → Logging → ログ エクスプローラ。クエリの例:
```
resource.type="cloud_run_revision" resource.labels.service_name="battle" severity>=WARNING
resource.type="cloud_run_revision" resource.labels.service_name="battle" jsonPayload.event="match_end"
jsonPayload.event="auth_rejected"
jsonPayload.event="cost_mode_changed"
resource.labels.service_name="judgedrawing" severity>=ERROR
```
対戦サーバーは 1 行 1 つの JSON（`severity`, `message`, `event`, …）で書きます。**トークン、絵、子どもが打った文字はログに出しません**。

### 9.3 アラート（メールが来るもの）
| アラート | 意味 | まずやること |
|---|---|---|
| `[battle] /healthz failing` | 外から対戦サーバーが見えない | Cloud Run のリビジョンとログを見る。直前にデプロイしたなら前の版に戻す（§5.5） |
| `[battle] 5xx ratio > 5 %` | エラーが多い | ログで `severity>=ERROR` |
| `[app] error logs > 10 / 10 min` | どこかでエラーが続いている（`service` ラベルで場所が分かる） | そのサービスのログ |
| `[battle] tick lag p95 > 80 ms` | 処理が追いつかない | CPU を 2 にする、利用者数を確認 |
| `[functions] judgeDrawing p95 > 20 s` | AI が遅い | Anthropic のステータスページ。アプリは端末の判定に切り替わるので緊急ではない |
| `[cost] kill switch changed costMode` | 節約モードに入った | §10 で何が高いか確認。必要なら予算やモードを見直す |
| 予算のメール（50/80/100%） | 今月の支出 | §10 |

### 9.4 Firestore の中身
Firebase コンソール → Firestore。運用でよく見るのは `config/costMode`（いまのモード）、`ops/costStatus`（最後の予算通知と判断）、`ops/aiUsage_YYYYMM`（AI の回数と見積り）、`moderationQueue`（通報）。

---

## 10. 請求書と予算アラートの読み方

1. Cloud Console → **お支払い（Billing）→ レポート**。期間「今月」、グループ化「サービス」で見ると、どのサービスにいくら使ったか分かります。
2. 「SKU」でグループ化すると、もっと細かく分かります（例: Cloud Run の「CPU Allocation Time」）。
3. ラベル `app=doodle-battle`、`env=prod` で絞れます（Terraform がすべてのリソースに付けています）。
4. **予算とアラート** で、予算に対する実績と予測が見られます。
5. 無料枠: Cloud Run（毎月 CPU 18 万 vCPU 秒など）、Firestore（1 日 5 万読み取り・2 万書き込み）、Functions（月 200 万回）、Logging（月 50 GiB）などは、請求書では「割引（クレジット）」として差し引かれます。予算は**クレジットを差し引いた後**で数えています。

メールが来たときの考え方:
- **50%（月の半ばより前）** → 想定より速い。ダッシュボードで「何が増えたか」を見る
- **80%** → 自動で saving に入る。月末までもちそうか、予測（Forecast）を見る
- **100%** → minimal。来月の予算を見直すか、利用を抑える工夫（§12 の下）を検討

---

## 11. よくある失敗

| 症状 | 原因と対処 |
|---|---|
| `Error 403: … API has not been used in project … or it is disabled` | API を有効にした直後で、まだ反映されていない。数分待って apply し直す |
| `Permission 'iam.serviceAccounts.getAccessToken' denied`（GitHub Actions） | 環境の名前が WIF の許可と違う（例 `realtime-production`）、`id-token: write` が無い、変数 `GCP_WIF_PROVIDER` のまちがい |
| `The caller does not have permission` で予算が作れない | `tf-apply@` に請求先アカウントの「費用管理者」が無い（§4.3） |
| `Error acquiring the state lock` | 前の実行が途中で止まった。§8.2 |
| `terraform destroy` で Firestore が消えない | prod は削除保護つき（わざと）。dev は保護なし |
| Identity Platform に切り替わった | Terraform で Auth を管理すると自動で切り替わる（**元に戻せない**）。無料枠（月数万人）を大きく超えなければ費用は変わらない。いやなら `manage_auth = false` にして、Auth は Firebase コンソールで匿名をオン |
| デプロイ後にアプリが対戦サーバーにつながらない | URL のまちがい（`wss://…/v2`）、App Check（dev ビルドはデバッグトークンを登録）、`REQUIRE_APP_CHECK` |
| 対戦サーバーが起動しない（prod） | `BATTLE_ENGINE=v3` なのに Engine v3 がまだ入っていない（意図どおり）。REALTIME_PROTOCOL §9 |
| 夜中もインスタンスが 1 台ある | アプリが接続を開きっぱなし。または監視（15 分おき）の直後。請求は「接続中」だけなので、billable instance time のグラフで確認 |
| Firebase CLI のデプロイで「ルールの権限付与」を聞かれて止まる | 初回は手元から対話モードで（§4.8） |
| JSON 鍵を作ろうとしてしまう | 不要です。WIF を使います。組織のポリシーで鍵の作成を禁止しておくとさらに安全 |
| コンソールで変えた設定が戻った | Terraform の apply が「コードどおり」に戻した。コードを直す（§8.5） |
| GitHub の Secrets にプロジェクト ID を入れた | 秘密ではないので Variables に。Secrets はログで伏せ字になり、調べにくくなる |

---

## 12. 費用の目安

**前提（1k DAU、2.5D、クラウド 3D なし）**: オンラインは DAU の 20% が 1 日 3 試合（接続は 1 試合あたり約 1.5 分）、新しいキャラは 1 人 1 日 0.5 体、AI 判定は保護者が許可した 40%（V2_INFRA §4.1 と同じ）。1 ドル 150 円。

| 項目 | 月の目安 | 計算 |
|---|---|---|
| Cloud Run（対戦サーバー） | **約 1,500〜2,500 円** | 接続がある時間 ≈ 1 日 6〜8 時間 → 約 75 万 vCPU 秒 − 無料枠 18 万 = 57 万 × $0.000024 ≈ $14。メモリはほぼ無料枠内 |
| Firestore | 約 0〜300 円 | 多くは 1 日の無料枠（5 万読み取り、2 万書き込み）の中。ゴーストの検索は 1 回 10〜20 読み取り |
| Cloud Functions / Cloud Build / Scheduler | 約 0〜100 円 | 月 200 万回の無料枠の中 |
| Cloud Storage・通信（エグレス） | 約 50〜300 円 | 対戦は 1 人 1 試合 約 90 KB |
| Logging・Monitoring・死活監視・Pub/Sub・予算・Secret Manager | 約 0 円 | 無料枠の中 |
| Artifact Registry | 約 10 円 | 0.5 GB を超えた分だけ（古いイメージは自動で削除） |
| **GCP 合計** | **約 1,600〜3,200 円** | 予算 5,000 円の 30〜65% |
| Anthropic（Claude、GCP の外） | 約 1,500 円 | 判定 + 技 1 回 ≈ $0.0006（V2_INFRA §2.5）。Anthropic Console で上限を設定 |
| **全体** | **約 3,100〜4,700 円** | 5,000 円の中。上ぶれしたらキルスイッチが saving に入る |

10k DAU では Cloud Run が 1 日中 1 台動き（約 $45〜95）、AI も 10 倍になるので、**月 2〜3 万円**になります。そのときは予算を見直すか、広告の収入（V2_INFRA §4.3）と比べて判断が必要です。

**安くするコツ**: アプリは対戦画面でだけ WebSocket を開く／最小インスタンスは 0 のまま／ログを出しすぎない（1 tick ごとにログを書かない）／Firestore の読み取りを減らす（一覧の画面でリスナーを張りっぱなしにしない）／使わない dev 環境は対戦サーバーを消しておく。

---

## 13. 片付け・削除

### 13.1 dev の対戦サーバーだけ止める（いちばんよく使う）
最小インスタンスが 0 なので、**使っていなければ料金は 0** です。完全に消したいときは `envs/dev` で:
```bash
terraform destroy -target=module.realtime
```

### 13.2 dev 環境をまるごと消す
```bash
cd infra/terraform/envs/dev && terraform destroy            # Firestore も消える（dev は保護なし）
```
- Firebase の Functions は Terraform の管理外なので、先に `firebase functions:delete <名前> --project …` で消すか、プロジェクトごと消します。
- 一部（Firestore のデータベース名、サービスアカウント名）は、消したあとしばらく同じ名前で作り直せません。

### 13.3 プロジェクトごと消す（いちばん確実）
```bash
gcloud projects delete doodle-battle-dev
```
30 日間は「削除予定」で、`gcloud projects undelete` で戻せます。そのあと完全に消え、課金も止まります。state バケットも一緒に消えるので、**prod では絶対にしない**でください。

### 13.4 prod の注意
- Firestore と Storage と Cloud Run は**削除保護つき**です（`deletion_protection`）。外すにはコードで `false` にして apply してから destroy、の 2 段階が必要です（わざと面倒にしています）。
- state バケットは `prevent_destroy` です。
- 子どものデータの削除は、`deleteMyData`（保護者の操作）とポリシーに従います（COMPLIANCE）。

---

## 14. 次の一歩（規模が大きくなったら）

1. **Functions 専用のサービスアカウント**: いまは既定の Compute Engine のアカウント（強い権限が付いていることがある）で動いています。`functions-runtime@` を作り、Firestore・Storage・Auth・シークレットだけを付けて、`setGlobalOptions({ serviceAccount })` で切り替える。既定のアカウントの「編集者」ロールを外す
2. **最小インスタンス 1**（約 3k DAU から）: コールドスタートがなくなる代わりに月 $40 前後
3. **シャーディング**（約 2,000 人同時から）: `battle-0..K` の複数サービスに分け、マッチングの callable が行き先を決める（V2_INFRA §3.3）
4. **試合の引き継ぎ**: いまは再起動で試合が「なかったこと」になる。入力ログを Firestore に書き、新しい台が再現して続ける
5. **依存関係の自動更新**: Dependabot で npm・GitHub Actions・Docker のダイジェスト・Terraform のプロバイダを更新する PR を作らせる
6. **組織のポリシー**: サービスアカウントの鍵の作成禁止、リソースの場所を asia-northeast1 に限定
7. **バックアップ**: Firestore の定期エクスポート（または PITR）。費用とのバランスで決める
8. **クラウド 3D**（予算が増えたら）: V2_INFRA §1 の Cloud Run GPU。予算と `cost_mode.json` に `cloud3d` のフラグを足す
