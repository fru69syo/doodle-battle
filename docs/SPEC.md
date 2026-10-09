# らくがきバトル (doodle-battle) 製品仕様 v1.0

子どもが紙に描いた絵をカメラで取り込み、キャラクターにして戦わせるゲーム。
**絵が上手すぎるとキャラが弱くなる（「しょぼキャラ」になる）**のが最大の特徴。
大人が本気で描いた絵や、ネットの画像を取り込んでも強くならない。

- 対象: 子ども（13歳未満を含む）。Google Play ファミリーポリシーに準拠する
- プラットフォーム: Android を先に出す（minSdk 24 / targetSdk 36）。iOS は v1.1 以降
- 技術スタック: Flutter 3.47 / Dart 3、Riverpod、go_router、Firebase、ARCore
- 言語: 日本語のみ（ひらがなを主にする）。英語は v1.1 以降

---

## 1. 用語

| 用語 | 意味 |
|---|---|
| のびのび度 (energy) | 0–100。インクの量・色の数・大きさ・線の勢い。キャラの「元気の総量」になる |
| じょうずさ (skill) | 0–100。線のなめらかさ・対称性・陰影・描き込みの細かさ・写実性。**高いほど弱くなる** |
| しょぼキャラ | じょうずさが 75 を超えたキャラ。ステータス予算が 0.35 倍になる。見た目に「げいじゅつか」の称号が付く |
| ぞくせい (element) | 一番多く使われた色から決まる。fire / water / leaf / thunder / shadow / rainbow |

## 2. 体験の流れ

1. 初めて起動したとき: 保護者セットアップ（保護者ゲート → 同意 → 設定）
2. 「かく」: 紙に描く → カメラで撮影（ギャラリーからも選べる）→ 自動で切り抜き → 必要なら手で調整
3. 「たんじょう」: 解析の演出 → キャラ誕生（ステータス・ぞくせい・わざを表示）→ 名前を付ける（NG ワードはその場で弾く）
4. 「ずかん」: 持っているキャラの一覧（無料では12体まで）
5. 「AR」: カメラ越しに床や机の上へキャラを置き、写真を撮る
6. 「バトル」: CPU と戦う（ステージ制）。勝つと経験値をもらってレベルアップする
7. 「オンライン」: キャラが **Lv5 以上** で、保護者が許可していれば遊べる。サーバーの審査を通ったキャラだけが出場できる
8. 「おうちのひと」: 保護者ゲートの先にある設定画面。課金・広告・クラウド判定・オンラインの許可、データの削除

## 3. 絵の解析（Vision チーム） — `app/lib/features/drawing_analysis/`

### 3.1 処理の流れ（端末内で完結し、isolate で実行する）
1. 正規化: 長い辺を 512px に縮小し、ホワイトバランスで紙の色を白に補正する
2. 紙の検出と切り抜き: 最も大きい明るい四角形を探して透視変換する。見つからなければ画像全体を使う
3. 前景の抽出: 紙の背景色との差を適応的に二値化する → 連結成分 → ゴミを除く → 輪郭を少し膨らませる → アルファマスクを作る
4. 特徴量の抽出（`DrawingFeatures`）:
   - inkCoverage: 前景の画素の割合
   - colorCount: 有意な色相のクラスタ数（白・黒・灰は別に数える）
   - dominantHue: 一番多い色
   - strokeSmoothness: 輪郭の曲率のばらつきの逆数（なめらかなほど高い）
   - symmetry: 左右反転したマスクとの IoU
   - shadingLevel: 同じ色相の中での明度の階調数（グラデーションや陰影）
   - detailDensity: 前景の中のエッジ密度、細かい連結成分の数
   - spikiness: 凸包の周長と輪郭の周長の比、凸性の欠けの数
   - roundness: 円形度 4πA/P²
   - aspectRatio: 外接矩形の縦横比
   - lineThickness: 距離変換で求めた平均の線の太さ
   - photoLikelihood: 写真らしさ（色数が多すぎる、なめらかなグラデーション、紙の背景が無い）
5. スコアを計算する:
   - `energy` = f(inkCoverage, colorCount, 大きさ, lineThickness)。点1つや線1本だけの絵は energy が低くなる（手抜きを防ぐ）
   - `skill` = f(strokeSmoothness, symmetry, shadingLevel, detailDensity, photoLikelihood)
6. ステータスを生成する（§3.2）

### 3.2 ステータス予算（Lv1）
```
budget = (200 + 2 * energy) * skillMultiplier(skill)

skillMultiplier(s):
  s <= 30        : 1.00          // のびのび
  30 < s <= 60   : 1.00 -> 0.90  (線形)
  60 < s <= 75   : 0.90 -> 0.70  (線形)
  s > 75         : 0.35          // しょぼキャラ (isShobo = true)
```
- 予算を hp / atk / def / spd の重みで配分する。各重みは最低 0.15
  - hp ← roundness, inkCoverage
  - atk ← spikiness, 赤の割合
  - def ← lineThickness, 暗さ, 塊っぽさ
  - spd ← aspectRatio（細長い）, 細い線
- 実際の HP 表示値 = hp × 3（バトル側の定義を正とする）
- **同じ画像からは必ず同じ結果が出る（決定的であること）**。乱数を使う場合は画像ハッシュを seed にする

### 3.3 クラウド判定（保護者が許可した場合だけ）
- Cloud Function `judgeDrawing` に PNG（切り抜き後、512px）を送る → Claude vision が次を返す:
  `{ subject: "ねこ", suggestedNames: [...3], moveNames: {element, special}, skillEstimate: 0-100, appropriate: bool, reasons: [] }`
- 最終的な skill = 0.6 × 端末の値 + 0.4 × クラウドの値
- 画像はサーバーに**保存しない**（処理が終わったら破棄する）
- 失敗したり時間切れになったりしても、端末の判定だけで続行する

## 4. バトル（Battle チーム） — `app/lib/domain/battle/` と `shared/battle_spec/`

### 4.1 ルール
- 1対1、ターン制。お互いにわざを1つ選び、spd の高い方から行動する（同じなら seed 付きの乱数で決める）
- わざは4つ:
  1. たいあたり（無属性。威力 40）
  2. ぞくせいわざ（自分のぞくせい。威力 60、命中 90%）
  3. まもる（そのターンに受けるダメージを 50% 減らす。連続で使うと効果が下がる）
  4. ひっさつ（ゲージが 100 のときだけ使える。威力 120。ゲージは攻撃したり受けたりすると溜まる）
- 相性（子ども向けに穏やかにする）: 有利 ×1.5、不利 ×0.75。倍率は**わざの威力に**かける（最終ダメージにかけると有利な側の勝率が 95% になり、強すぎたため）。全ての攻撃に一律の威力 +50 を足す。ひっさつは無属性。実際のダメージでは、有利なぞくせいわざは等倍の約 1.27 倍になる
  - fire > leaf > thunder > water > fire（4すくみ）
  - shadow と rainbow はお互いに有利。それ以外の相手には等倍
- ダメージの式・会心・乱数幅は battle_spec.json で定義する（Battle チームが決める）
- **エンジンは純粋関数にする**: `BattleState next(BattleState, Action a, Action b, Rng rng)`。乱数は seed で決まる
- `shared/battle_spec/battle_spec.json`（定数・相性表・わざ）と `golden_vectors.json`（入力→出力の正解例）を共有する。Dart と TypeScript の両方の実装が同じゴールデンテストを通ること

### 4.2 成長
- 経験値: 勝ち 100 / 負け 40 / CPU のステージ倍率あり。しょぼキャラは経験値 +50%（逆転の楽しみ）
- 次のレベルまでの必要経験値 = 50 + 25 × L。最大 Lv30
- レベルが上がると全ステータスが +4%（Lv1 の値を基準）。さらに「パワーのたね」1個を、子どもが好きなステータスに振れる（+3%）
- 進化: Lv10「かがやき」（オーラのエフェクト）、Lv20「でんせつ」（金のフレーム。ひっさつの威力 +20）
- Lv5 でオンライン対戦が解放される

### 4.3 CPU
- ステージ 1–30。CPU のキャラは同梱のサンプル絵から作り、ステージに応じてレベルを決める
- 思考の強さは3段階: よわい（ランダム）/ ふつう（相性を見る）/ つよい（HP・ゲージ・相手の行動を読む）

## 5. オンライン対戦（Backend チーム） — `firebase/`

- 認証: Firebase Anonymous Auth と App Check（Play Integrity）
- **自由に入力した文字を他の人に見せることは一切しない**（チャットも無い）
- オンラインの表示名: プリセットの語彙からの組み合わせ（例「あおい ドラゴン」）。自由入力はさせない
- キャラ名: オンラインに出すときは、サーバーの審査（NG ワード辞書 + 正規化 + AI 判定）を通ったものだけ使える。不合格ならプリセットの名前に置き換えるよう促す
- キャラの登録（`registerCharacter`）: 画像・名前・特徴量・レベル・経験値を送る → サーバーで審査する:
  1. 画像のモデレーション（Claude vision）: 暴力・性的・差別・ロゴ/著作権キャラの丸写し・**実在の人物の写真や顔**・個人情報（名前や住所の文字）・写真（絵ではない）→ 不合格
  2. 名前の NG ワードチェック
  3. ステータスがレベルごとの上限を超えていないかを検証する（改ざん対策）
  4. 合格したら不変のスナップショットとして保存する（Storage の画像と Firestore のドキュメント）
- マッチング: `joinQueue(characterId)` → レベル帯 ±3 で組む。60秒待っても相手がいなければ「ゴースト」（他の人の登録キャラを AI が操作する）と戦う。待たせないため
- バトルの進行: サーバーが勝敗を決める。Firestore の `matches/{id}` に双方が行動を書き込む → Function `resolveTurn` が TS エンジンで解決する。1ターンの制限は 20 秒。時間切れなら自動で「たいあたり」
- 通報: 相手キャラを通報するボタン（理由は選択式）→ 一定数たまったら非公開にし、運営が確認する
- AI 判定・モデレーションに使うモデル: 安価な Haiku 系の最新版（claude-api skill で確認する）。API キーは Secret Manager に置き、クライアントには一切渡さない

## 6. AR（AR チーム） — `app/lib/features/ar/` と Android ネイティブ

- ARCore で平面を検出 → タップでキャラを置く。キャラは切り抜いた画像を貼った「紙の立て札」風の glb を端末内で作る（厚みを少し付ける。ぴょこぴょこ跳ねる）
- ピンチで拡大縮小、ひねりで回転。撮影したら端末のギャラリーに保存する
- ARCore に対応していない端末: カメラのプレビューにキャラを重ねる「かんたん AR」にフォールバックする
- 進化の段階に応じたエフェクト（オーラ・きらきら）

## 7. 保護者機能・収益化（Compliance チーム）

- 保護者ゲート: 3秒長押し + 2桁×1桁の掛け算（ひらがなではなく数字・漢字で表示する）
- 保護者の設定項目: クラウド判定 / オンライン対戦 / 広告の視聴 / 課金 の許可、プレイ時間の目安、全データの削除（サーバー側も含む）
- 広告（AdMob、ファミリー向けに認定された SDK）:
  - `tagForChildDirectedTreatment=true`、`maxAdContentRating=G`、パーソナライズしない、広告 ID を集めない（AD_ID 権限を外す）
  - リワード広告だけを使う（例: 「どうがを みて けいけんち 2ばい」）。保護者が許可しているときだけ出す
  - 見る前に必ず注意書きを出す: 「おうちのひとに きいてから みてね」「こうこくが ながれるよ」
- 課金（Google Play Billing）:
  - ずかんの保存枠 +24、カードのフレームパック、「おうえんパス」（広告なしで経験値ブースト）
  - 購入の前に必ず保護者ゲートを出す。注意書き「おかねが かかるよ。おうちのひとと いっしょに かってね」
  - ガチャ（ランダム型アイテム）は**入れない**
- Firebase Analytics は使わない（広告 ID が絡むため）。Crashlytics だけ使う
- プライバシーポリシーとデータセーフティ: 収集するもの（匿名 ID、許可された場合の絵の画像、クラッシュログ）を明記する

## 8. リポジトリの構成

```
app/                     Flutter アプリ (package: doodle_battle, applicationId は仮)
  lib/core/              テーマ・ルーター・共通ウィジェット
  lib/domain/            モデル（character, stats, element, move）と battle/
  lib/data/              ローカル保存（JSON + PNG を path_provider に置く）
  lib/features/<name>/   drawing_analysis, battle_ui, ar, collection, parent, monetization, online, onboarding
  test/
shared/battle_spec/      バトルの定数と正解例（Dart と TS で共有）
firebase/                functions/(TypeScript), firestore.rules, storage.rules, firebase.json
docs/                    SPEC, TEAM, PRIVACY_POLICY, STORE_LISTING, RELEASE
.github/workflows/       CI（analyze, test, functions のテスト、AAB のビルド）
```

## 9. 品質の基準
- `flutter analyze` で警告ゼロ、`flutter test` がすべて通ること
- 純粋なロジック（解析・バトル・成長・NG ワード）のカバレッジは 80% 以上
- Functions は emulator 上のテストと Firestore ルールのテストを通すこと
- Pixel 系の中位機種で、解析が3秒以内に終わること
