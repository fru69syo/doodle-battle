# App/UI（v2.0 統合: Integration チーム）

SPEC §2 の体験を 1 本のアプリにまとめる層。画面・ナビゲーション・ローカル保存・保護者機能・各チームのモジュールの統合を担当する。
数値やルールは持たない（バトル・成長・ステージは `domain/battle_v3`、キャラは `domain/character_v2.dart`、解析は `features/drawing_analysis`、2.5D は `features/puppet` と `features/battle_stage`、NG ワードは `shared/ng_words` が正）。

v1 のターン制の画面（`battle_arena` など）は v2.0 で削除した。v1 のエンジン `domain/battle/` はテストとツールのために残している（アプリからは使わない）。

## 1. 構成

```
lib/
  main.dart                 起動: 縦固定、ライセンス登録、Firebase 初期化（未設定なら offline）、ProviderScope
  app.dart                  MaterialApp.router（テーマ、ja ロケール、文字倍率は最大 1.3）
  core/                     テーマ、router、共通ウィジェット（AttrBadge・StatBarsV2 など）、サービス provider、config/app_config.dart（フラグ）
  data/                     リポジトリ（CharacterV2・設定・進み具合）、app_state（Riverpod notifier）、backend/
  domain/                   battle_v3（エンジン）、character_v2.dart、character_v2_view.dart（UI が読んでよい答え）、cost_mode.dart …
  features/
    onboarding/ home/ draw/ draw_canvas/ birth/ collection/ battle_ui/ battle_stage/ puppet/
    online/（realtime/）family_battle/ video_export/ card_print/ drawing_loop/ ar/
    parent/ parental_gate/ monetization/ ng_filter/ drawing_analysis/
```

- 状態管理は Riverpod 3、画面遷移は go_router。テストで差し替える seam は `core/providers.dart` ほかの provider（リポジトリ、`BackendApi`、`MonetizationService`、`ParentalGate`、解析、画像入力、時計、乱数、CPU の絵、`adsSupportedProvider`、`battleTimeScaleProvider`、`realtimeConnectorProvider`、`realtimeUrlProvider`）。
- **隠し要素（SPEC §3.5）**: `lib/features`・`lib/core`・`lib/data` は `isBloomer` などを読まない。必要な答え（見た目 `drawsSimpleLook`、一人用の経験値 `singlePlayerXpFor`、新しいキャラ `newCharacterV2`）は domain 層の関数が返す。`test/domain/hidden_state_guard_test.dart` が、コード・文字列・保存 JSON・送信 JSON・キャラのページで確かめる。

## 2. ルート

| パス | 画面 |
|---|---|
| `/splash` | 設定の読み込み中 |
| `/setup` | 初回の保護者セットアップ（ゲート → 説明と同意 → 完了） |
| `/` | ホーム（かく / ずかん / バトル / かぞくで たいせん / オンライン※ / おうちのひと） |
| `/draw` | 撮影（主）か「アプリで かく」→ 端末内解析 →（許可時）クラウド判定 |
| `/birth` → `/birth/name` | 誕生演出（グー/チョキ/パー・Lv1 の技 2 つ）→ 名前 |
| `/zukan`, `/zukan/:id`, `/zukan/:id/ar` | 一覧、詳細（Lv・XP・しんか・10 の能力・技 4 枠（未解放は Lv10/Lv50 の鍵））、AR |
| `/zukan/:id/joints` (`?first=1`) | うごく ところを なおそう（保存した骨は `CharacterV2.rig` に入る） |
| `/battle` | キャラ選択 |
| `/battle/:id/stages` | ワールド選択（10 ワールド、星の数、ボスを倒すと次が開く） |
| `/battle/:id/world/:w` | ステージ選択（10 ステージ、星 0–3、10 番目はボス） |
| `/battle/:id/stage/:n` | 一人用の ATB バトル（2.5D ステージ） |
| `/battle/result` | 結果（`extra`: `BattleOutcome`） |
| `/online`, `/online/queue/:id` | ロビー（Lv5+、バッジ、オンラインの なまえ）、審査 → マッチング → 対戦（1 画面） |
| `/family`, `/family/battle` | かぞくで たいせん（1 台、ATB、2 人がそれぞれ操作） |
| `/parent` | おうちのひと（ゲートを通ったときだけ） |
| `/zukan/cards`, `/zukan/cards/print?ids=` | キャラカード |
| `/debug/25d` | 2.5D のデバッグ（**debug ビルドだけ**。release のルート表には入らない） |

## 3. ローカル保存（`lib/data/`）

- `CharacterRepository` は **`CharacterV2`** を保存する（`<documents>/characters/<id>.json` + `<id>.png`）。v1 のファイル（`schema` なし）は読み込み時に `CharacterV2.fromJson` で移行し、v2 の形で 1 回だけ書き直す。v1 の `onlineId` は捨てる（オンラインに出るときに schema 2 で黙って登録し直す）。
- `PuppetStore` にだけあった骨（v2 以前に手直ししたもの）は、起動時に `CharacterV2.rig` へ写す（`CharactersController`）。
- `progress.json`: クリア済みステージ、**ステージごとの星**、**おまかせ**、**オンラインのバッジ**、適用済みオンライン対戦 ID、今日のプレイ秒数、オンライン登録時の Lv、今日の広告ブースト、オンラインの表示名。
- ずかんの上限: 12 体（課金がオフのため 36 体の枠は出ない）。

## 4. 画面ごとの決定事項

- **キャラの作り方**: 写真は `admitReportV2`（デジタル・印刷・画面の絵も受け付け、内部の verdict だけを保存）、アプリの絵は `DrawingSource.canvas`。画像ハッシュは **切り抜き PNG の SHA-256**（サーバーと同じ）。クラウド判定は保護者の許可 + コストモード（`config/costMode` の `cloudJudge`）のときだけ。`judgeDrawing` に `v2`（量子化した特徴）を付けて技の提案を受け取り、端末で検証し直す（不採用の枠は `generateOfflineMoves` の技）。子どもが通報した AI の技の名前は使わない。
- **一人用（SPEC §7.1）**: ワールド → ステージ → バトル。`stageTable()` と CPU の絵 37 体（`manifest_v2.json`）。CPU の強さ（よわい/ふつう/つよい）は表示しない。星: 勝ち・HP 50 % 以上・60 秒以内。
- **バトル（SPEC §6、ゲージを複数ためる）**: `BattleStage` の上に `FighterStatusPanel` ×2 と `BattleControls`。パネルのゲージ（`AtbGauge`）はキャラの最大本数（2〜5）ぶんの区切りで、たまりかけの分も見える。全部たまると光り、キャラが跳ねる。技のボタンは使う本数を小さな四角（`BarPips`）で見せる。本数が足りない・クールダウン中の技は薄くなるが、**押しておける**（さきどり: 本数がたまった瞬間に出る。押した技に「つぎ！」）。最大本数より多い本数の技は押せない（検証器が作らない）。**残り時間の輪は無い**（時間切れは廃止。何もしないとゲージが最大で止まるだけ）。おまかせはランダムに技を選んで本数を待つ（一人用で覚えておく）。選んでいる間も相手は止まらず、遅くもならない。子どもがするのは技を選ぶことだけ。描いた わざの え は `drawnEffects` で飛ぶ。ボタンは 48dp 以上、文字は縮小して収める。区切りは長方形だけで描く（古い Android でも軽い）。
- **結果**: 経験値（`singlePlayerXpFor`）、星、レベルアップ、**あたらしい わざ！**（Lv10・Lv50）、**しんか！**（Lv10 かがやき / 25 きらきら / 50 でんせつ（全部の技がパワーアップ）/ 75 にじ / 100 おうかん）。Lv50 の でんせつ は全員同じ演出（隠し要素の作り直しもこの中で起き、見分けられない）。新しい技は、保護者がクラウド判定を許可していてコストモードが許せば `generateMove` で名前を作り（結果画面のあとから名前が変わる）、だめなら黙ってテンプレートの技のまま。「どうがを みて けいけんち 2ばい」は **Android のビルドだけ**（`adsSupportedProvider`）。
- **オンライン（SPEC §7.2・§9）**: Lv5 から。ボタンは保護者の許可があり、サーバー（Firebase と `REALTIME_URL`）があるときだけ。未登録・Lv が上がった・サーバーが知らない（v1 の）キャラは `registerCharacter`（`schema: 2`、`source`、アプリの絵は `canvas` の線の要約）で審査し直し、返ってきた `imageHash` を正とする。WebSocket（`features/online/realtime/`）: `hello`（ID トークン + App Check）→ `queue` → `match` → `select`（いつでも、さきどり。サーバーが持っていて本数がたまった tick に使う）／`omakase`（おまかせはサーバーがランダムに選んで本数を待つ）→ `end`。プロトコル rev 3: ゲージは `snap` の本数（`gauge`・`bars`・`maxBars`）を 2 Hz の間で補間して出す。時間切れ・`deadline` は無い。相手の旗のボタン（`FighterInfo.snapshotId` → `reportCharacter`。対戦中の通報は `end` のあとに送る。かがみには出さない）。サーバーのイベントを約 200 ms 遅らせて `translate()` で 2.5D ステージに流す。切断は `lastSeq` 付きで黙って再接続し、だめなら「ひとりで あそぶ」を出す。ゴーストでも同じ「あいてを さがしているよ」。バッジは結果とロビーに出す（レートの数字は出さない）。チャットはない。表示名はプリセットの言葉だけ。
- **かぞくで たいせん**: あか（下）とあお（上、ボタンは向かい側の人に向けて上下逆）がそれぞれ技を選ぶ（さきどり・おまかせも各自。時間切れは無い）。戦うレベルは `familyBattleLevel`、経験値は 0。
- **Before/After 動画**: 絵が浮き上がって着地すると 2.5D パペットとして跳ね、バトルでは自分の骨で技を出し、CPU は当たって倒れる。台本はエンジン v3 で決まる。
- **おうちのひと**: 同意（クラウド判定・オンライン・広告（Android のビルドだけ）・ふぐあいの情報。課金は `kIapEnabled` のときだけ）、プレイ時間、絵の取り込み、AR、（課金がオンのときだけショップ）、データ削除、ポリシー、ライセンス。保護者ゲートと注意書きは v1 のまま。
- **コストモード（SPEC §11.3）**: `config/costMode` を読む（1 分キャッシュ、読めなければ normal）。saving / minimal ではクラウド判定と技の名前づくりを呼ばない。対人戦をゴーストにするのはサーバー。子どもには何も表示しない。

## 5. Firebase

- 匿名認証、Functions（`asia-northeast1`: `judgeDrawing`、`registerCharacter`、`generateMove`、`setDisplayName`、`reportCharacter`、`reportAiSuggestion`、`deleteMyData`）、Firestore（同意の書き込み、`config/costMode` の読み取り）、Storage（相手の絵）、App Check。v1 のターン制のマッチング（`joinQueue` など）はアプリから外した。
- `lib/firebase_options.dart` はプレースホルダー（未設定なら全部オフラインで動く）。設定手順は docs/BACKEND.md §14、docs/LEARN_GCP.md。

## 6. ビルド時のフラグ（`core/config/app_config.dart`）

| `--dart-define` | 初期値 | 意味 |
|---|---|---|
| `IAP_ENABLED` | false | 課金（商品・ショップ・購入の同意・復元）。オフのあいだストアには一切つながらない（SPEC §10.2） |
| `ADS_ENABLED` | true | Android のリワード広告。iPhone 版はいつも広告なし |
| `REALTIME_URL` | 空 | 対戦サーバー（`wss://…/v2`）。空ならオンラインは「じゅんびちゅう」 |

## 7. テスト

`flutter test --concurrency=2`。ウィジェットテストは `test/support/harness.dart` の `pumpApp()` でアプリ全体をフェイク付きで起動する。バトルは `battleTimeScaleProvider`（テストは 40 倍）と `playBattle()` で最後まで流す。オンラインは `test/support/fake_realtime.dart` のフェイクサーバー。
