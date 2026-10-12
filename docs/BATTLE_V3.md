# Battle engine v3（おえかきファイターズ v2.0）— Engine v3 チーム

`docs/GAME_DESIGN_V2.md`（設計・数式の正）を製品のコードにしたもの。このドキュメントは**コードの地図・API・設計から変えた点・バランスの再計測**をまとめる。隠し要素（大器晩成）の名前・数値は社内用（GAME_DESIGN_V2 冒頭の注意を参照）。

## 1. どこに何があるか

| 場所 | 内容 |
|---|---|
| `app/lib/domain/battle_v3/` | **Dart エンジン v3**（純 Dart、Flutter の import なし）。`battle_v3.dart` が入口 |
| `shared/battle_engine_v3_ts/` | **TS エンジン v3**（strict TS、vitest）。Dart とビット単位で一致。サーバー（`server/realtime`、Cloud Functions）が使う |
| `shared/battle_spec_v3/battle_spec_v3.json` | 全定数（Dart から生成。TS はテストで照合） |
| `shared/battle_spec_v3/golden_vectors.json` | **128 件**のゴールデンベクトル（Dart と TS の両方で、JSON の入力だけから再現） |
| `app/lib/domain/character_v2.dart` | Character v2 モデル（v1 からの移行つき） |
| `app/lib/domain/rig_blob.dart` | 2.5D リグ JSON の検証（中身は Puppet チームのもの。ここでは大きさと形だけ見る） |
| `app/lib/domain/cpu_roster_v2.dart`, `app/assets/cpu/manifest_v2.json` | CPU の絵 37 体（v1 の 12 体 + 新しい 25 体） |
| `app/lib/features/drawing_analysis/v2_admission.dart` | 受け付け／隠し要素の判定（Trust の結果 → verdict） |
| `app/tool/v3_sim.dart` | バランスのシミュレーター、spec / golden の生成、ステージの調整 |
| `firebase/functions/src/callables/registerCharacterV2.ts` | v2 キャラの登録（サーバーで能力を計算し直す） |

再生成: `cd app && dart run tool/v3_sim.dart spec`、`… golden`、`… tune-stages 400`（その後 spec と golden をもう一度）、CPU の絵は `dart run tool/gen_cpu_doodles.dart`。

## 2. エンジンの API

### Dart（`package:doodle_battle/domain/battle_v3/battle_v3.dart`）

```dart
final g = Genome.derive(spec, features: fv, energy10: e, skill10: s, imageHash: h, origin: verdict);
final a = setupAt(spec, g, level, aiProposals: proposals);   // ratedSetup / familySetup も同じ形
final b = Battle(spec, a, cpuSetup, seed: seed);              // autoPick = ふつう、recordEvents = true
b.queueInput(0, slot);                    // タップ／さきどり（いつでも。満タンになった tick に使う）
final events = b.step(b: aiController(tier: AiTier.strong));   // 1 tick = 100 ms
b.snapshot(); b.restore(json); b.stateHash();                  // サーバーの保存・再接続・ずれ検出
```

- `Battle.step({Controller? a, Controller? b})`: 1 tick の正規の順番（GAME_DESIGN_V2 §6.1）。決定の段階では「キューの入力 → コントローラー → 5 秒のおまかせ」の順。使えない入力は `inputIgnored` を出して捨てる
- `Fighter`: hp / maxHp / sp（1/100）/ gauge / phase（charging・ready・casting）/ cooldowns / stages / 状態異常 / `decisionTicksLeft`（残り時間の表示用）
- AI: `chooseMove(b, side, rng, tier:)`、`aiController(thinkTicks:, tier:)`、`AiTier.weak/normal/strong`
- キャラ: `Genome`（kid・属性・能力・成長。**`isBloomer` / `rebornAt` は内部用**）、`generateOfflineMoves`、`validateAiMove` / `validateAiMoveSet` / `resolveWithOffline`、`moveCost`
- 成長: `xpToNext`、`xpSinglePlayer`、`xpOnline`、`onlineXpEligible`、`applyXp`（技の解放・進化・内部の作り直しフラグ）、`adBoostAvailable`（Android だけ・保護者の許可・1 日 3 回）、`familyBattleLevel`（経験値は 0）、`ratedSync` / `ratedSetup`、Elo・バッジ・マッチの幅
- 一人用: `stageTable()` / `stageAt(n)`（ワールド・位置・おすすめ Lv・CPU の Lv・AI の強さ・CPU の絵の id・ボス・能力 %）、`kWorldRosters`

### TS（`shared/battle_engine_v3_ts`）

同じ名前・同じ意味（`new Genome(spec, {...})`、`new Battle(spec, a, b, seed)`、`battle.step(ca, cb)`、`setupAt` / `ratedSetup` / `familySetup`、`validateAiMove(s, json, {slot, own, moveFactorPct, ngCheck})` …）。加えてサーバー用:

- `validateCharacterClaimV2(claim, {ngCheck, serverOrigin, maxLevel})`: features（量子化した整数）・energy10 / skill10・画像ハッシュ・レベル・XP から**能力を計算し直す**。端末が送った能力は照合だけ（違えば `STATS_MISMATCH`）。技の提案は枠の予算で検証し直し（不採用ならその枠は端末のテンプレート技）、リグは大きさと形を確認（不正なら捨てる）。返す `snapshot` に隠し要素の情報は入らない
- `moveContextOf(...)`: AI に技を作らせるときの属性と枠ごとの予算
- `RealtimeBattle`（`realtime.ts`）: `server/realtime/src/engine.ts` の形に合わせたラッパー。`decisionTicks` を無効にし（5 秒の時間切れはサーバーが持つ）、`step([slotA, slotB])` → `{events, acted}`、`isReady` / `canUse` / `chooseMove(side, tier)` / `view(side)` / `stateHash()`（16 進 8 桁）。`ratedFighterFromSnapshot(snapshot.engine, level)` で Firestore の v2 スナップショットから Lv50 にそろえた選手を作る。GCP チームの `engines/v3Engine.ts` はこれをつなぐだけでよい
- ゴールデンのバトルには `expected.inputLog`（`[tick, side, slot]`）が入っている。これを入力として時間切れ無しで流すと同じ結果（勝者・tick・HP・状態のハッシュ）になる（TS のテストで確認済み。REALTIME_PROTOCOL §9 の手順 3）

### イベント（描画用。tick 付き）

| type | data |
|---|---|
| `ready` | side |
| `inputIgnored` | side, slot（キューの技が使えなかった） |
| `select` | side, slot, cast, auto（1 = 時間切れのおまかせ） |
| `moveStart` | side, slot, template, attr（技の演出の開始） |
| `effective` | side, target, pct（150 = こうかばつぐん / 75。技ごとに 1 回） |
| `hit` | side, target, n（何発目）, amount, hp, crit（0/1）, pct |
| `miss` | side, target, n |
| `dot` | target, amount, hp（ねばねばのダメージ） |
| `heal` | side, amount, hp, source（move / drain） |
| `stage` | side, stat, stage, ticks |
| `status` / `statusFail` | target, status（poison / paralyze）[, ticks] |
| `shield` | side, pct, ticks |
| `expire` | side, kind（poison / paralyze / shield / STR …） |
| `heatUp` | （60 秒を過ぎた最初の tick） |
| `faint` | side（HP 0） |
| `end` | winner, reason（ko / timeUp。引き分けは無い） |

照合用の行は `"<tick> <type> k=v,..."`（キーは ASCII 順）、列全体の FNV-1a をゴールデンに入れている。

## 3. 設計（GAME_DESIGN_V2）からの変更点

1. **さきどりはエンジンのキュー**（`queueInput`）。プロトタイプはコントローラーだけだった。新しい入力は古い入力を上書きし、使えないときは `inputIgnored` を出して捨てる
2. **作り直し後の技（stream 14）は作り直し後の能力で形を決める**（プロトタイプは作り直し前の能力を使っていた）。設計チームのゴールデンは、この 2 件以外すべて同じ結果を再現した（ゲノム 12、技 6、検証 10、バトル 6 件の勝者・tick・HP、XP、Elo）
3. **`imageSeed` は先頭がちょうど 16 進 8 桁のときだけ数値にする**（符号や空白の扱いが言語で違うため）。それ以外は FNV-1a
4. AI の検証: JSON の数が 1e9 を超える小数は 1e9 に寄せてから切り捨て（言語で整数化の挙動が違うため。範囲外なので結果は同じ）。`atkFormula` が文字列でなくても落ちない。答え全体の検証（`validateAiMoveSet`）では**同じ名前の 2 つ目を不採用**（V2_INFRA §2.3）
5. 技を選んだら `readyTicks` を 0 に戻す（サーバー方式で再生しても状態のハッシュが一致するように）
6. **つよい AI**: 採点を変えた（本当の命中率・会心率、時間あたりの価値、確実に倒せる技、相手が溜めているときのまもり、回復量の見積もり、強化・弱体の効き目）うえで、**考える時間を 0.4 秒**（ふつう・よわいは 1 秒）にした。採点だけでは +2 % しか上がらず（先読みのシミュレーションも試したが 47 % で悪化）、考える速さが強さの大部分。CPU だけが使い、おまかせ・ゴースト・サーバーの時間切れはふつう
7. **ステージの CPU の能力 %** は「位置で 88–98 %」ではなく、**ステージごとの表**（`stage_power_table.dart` / `stagePowerTable.ts`）。実際の CPU の絵・レベル・AI の強さで、設計の勝率の曲線に合うよう二分探索した（`tune-stages`）。同梱の絵は個性が強く、同じ % だと 8–95 % とばらついたため
8. **オンラインの経験値**: 隠し要素のボーナスはプロトタイプどおり ×1.5（一人用は ×2）
9. 家族対戦: Lv50 未満の隠し要素のキャラは、ハンデで Lv50 を超えても作り直し前の形のまま（隠し要素がばれないように）

## 4. Character v2

保存するのは**入力だけ**: 量子化した features、energy10 / skill10、画像ハッシュ、絵の入手方法（photo / canvas）、Trust の verdict（`digital` / `printed` / `screen` / `ai_generated`、内部用）、レベル（≤100）、XP、技の枠ごとの AI 提案（正規化した JSON）と名前の上書き、`moveSet`（0 = 生まれたときの技、1 = Lv50 で作り直した技、内部用）、リグ JSON（検証済み）、v1 の色の属性（見た目のヒント）、subject、onlineId、カードの枠、コスメ。

- 能力・属性・kid・隠し要素は毎回 `Genome` から計算する（GAME_DESIGN_V2 §11）。JSON に `bloomer` などの言葉は出ない（テストあり）。`lib/features` の UI が隠し要素を読まないことも `hidden_state_guard_test.dart` で確かめる
- 技の数値は**毎回**検証器でそのレベルの予算に合わせる（AI の提案は数値を決めない。Lv50 の +5 % は端末のテンプレート技に効く）
- `gainXp` で Lv10 / Lv50 の技の解放と進化を返す。隠し要素のキャラが Lv50 になると AI の提案を捨てて作り直しの技（stream 14）にする（新しい名前を AI に頼むのは `withAiMoves`）
- お絵かきツールで描いた絵は verdict を持たない（デジタル判定をしない）

### v1 からの移行（`CharacterV2.fromJson` が自動で行う）

`schema` が無い JSON は v1 とみなし、保存されている解析の features（`DrawingFeatures.toMap()`）を量子化し、energy / skill を 1/10 単位にして**能力と技を作り直す**。

- 残すもの: id、名前、画像、画像ハッシュ、作成日時、レベル（1–100 に収める）、XP（次のレベルの必要量未満に収める）、subject、カードの枠、コスメ
- v1 の技の名前: 正しいかな（1–10 文字）なら、属性の技 → 枠 1、ひっさつ → 枠 4 の名前に使う（数値はテンプレート）
- 捨てるもの: v1 の Lv1 能力、パワーのたね（廃止、§4.3）、**onlineId**（v1 のスナップショットは v2 で使えないので、オンラインはもう一度登録）
- v1 のしょぼキャラ（skill > 75）は、そのまま隠し要素のキャラになる。features が欠けていても中立の値で作れる（テストあり）
- 実ユーザーはまだいないが、アプリが保存形式を切り替えるとき（統合チーム）にこの読み込みを使えば安全に移れる

## 5. 一人用と CPU

- 10 ワールド × 10 ステージ、ステージ n のおすすめ Lv = CPU の Lv = n。AI: 1–20 よわい、21–60 ふつう、61–100 つよい。各ワールドの CPU は 3 体が順番に出て、10 番目がボス（`kWorldRosters`）
- CPU の絵 37 体: 属性はグー 16・チョキ 11・パー 10、形は手足あり・まるい塊・乗り物（`manifest_v2.json` の `shape`。Puppet チームの確認用）。v1 の 12 体の PNG と `manifest.json` は変えていない（v1 エンジンがまだ使う）
- 経験値・広告・家族対戦・レート戦の規則は §2 の関数（純粋関数）

## 6. バランスの再計測（製品のエンジン、`dart run tool/v3_sim.dart 4000`）

| 目標 | シナリオ | A の勝率 | 平均の長さ |
|---|---|---|---|
| 同じ能力 ≈ 50 % | ミラー Lv1 / Lv50 / Lv100 | 49.3 / 50.2 / 49.2 % | 80 / 61 / 59 秒 |
| 違う絵同士 | Lv20 | 50.2 % | **48.8 秒**（p10 32・p90 69） |
| 相性 65–75 % | 同じ能力 Lv1 / 10 / 50 | 67.5 / 70.1 / 69.7 % | 58 / 47 / 44 秒 |
| | 違う絵 Lv20 | 65.2 % | 44 秒 |
| AGI は効くが強すぎない | AGI ×1.5 / ×2（合計は同じ） | 49.0 / 36.6 % | 64 秒 |
| 子どもの絵らしさ | kid 95 vs kid 60 | 75.0 % | 47 秒 |
| 隠し要素は Lv49 まで勝てない | Lv1 / 10 / 30 / 49 | 子どもの絵が 100 % | 18–25 秒 |
| 隠し要素は最大 Lv で 60–65 % | Lv50 / 75 / 100 | 50.0 / 59.0 / **65.2 %** | 46 秒 |
| | Lv100 vs kid 95 | 52.3 % | 45 秒 |
| **つよい AI ≥ 60 %** | つよい vs ふつう Lv20 | **64.0 %**（Lv5 65.0、Lv50 63.6） | 44 秒 |
| | ふつう vs よわい | 55.0 % | 50 秒 |
| 操作 | さきどり（0 秒）vs おまかせ（1 秒） / 3 秒 vs 1 秒 | 68.2 / 20.1 % | — |
| 終わらない試合が無い | 全シナリオ | 3 分の上限はミラー Lv1 で 0.2 %、ほかは 0–0.15 % | — |

1 つの能力だけ +50 %（Lv20）: HP 91 / SP 70 / STR 83 / VIT 88 / DEF 80 / INT 76 / RES 76 / DEX 71 / AGI 92 / LUK 74 %。レベル差: Lv6 vs 1 89 %、Lv15 vs 10 88 %、Lv55 vs 50 72 %、Lv60 vs 50 85 %、Lv100 vs 95 62 %。設計チームの表とほぼ同じ（エンジンの結果は同じ乱数の使い方なので、違いはつよい AI の項目だけ）。

### 一人用ステージ（`dart run tool/v3_sim.dart stages 1000`、実際の CPU の絵、調整とは別の乱数）

プレイヤー = おすすめ Lv のランダムな子どもの絵（おまかせ、1 秒）。

| 位置 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10（ボス） |
|---|---|---|---|---|---|---|---|---|---|---|
| 目標（GAME_DESIGN_V2 §7） | 85 | 82 | 80 | 77 | 75 | 71 | 68 | 65 | 63 | 56 |
| **結果（10 ワールドの平均）** | **87** | **83** | **81** | **80** | **78** | **73** | **71** | **66** | **65** | **59** |

ワールドごとの結果は 54–92 %（`stages` コマンドの表）。目標より 1–3 ポイントやさしい（二分探索で「目標より勝てる側」の % を選ぶため）。ステージ戦の平均の長さは 45 秒。

## 7. サーバー（Cloud Functions）

- `registerCharacter` に `schema: 2` を送ると v2 の登録（`registerCharacterV2.ts`）。features / energy10 / skill10 / imageHash / level / xp /（任意で）stats / 技の提案 / リグ。能力はサーバーが計算し直し、AI の判定（`moderateCharacter`）で `ai_generated` なら隠し要素の形で保存する（**拒否しない**。写真・印刷・画面は今までどおり拒否）。技の名前も AI の審査にかけ、だめならその枠はテンプレート技。応答には能力を入れない（隠し要素がばれないように）
- スナップショットは同じ `snapshots` に `schema: 2`（`SnapshotDocV2`: 表示用の情報 + `engine`（エンジンの入力、サーバー専用））。v1 のターン制のマッチングは `schema: 2` を使わない。リアルタイムサーバーは `ratedFighterFromSnapshot(doc.engine, doc.level)`
- `judgeDrawing` に `v2`（量子化した features など）を付けると、同じ Claude の呼び出しで**技を 4 つ提案**させ、`validateAiMoveSet` + NG フィルターで検証した提案を `moves` で返す（不採用の枠は null → 端末のテンプレート技）。v2 では `ai_generated` を拒否しない。v1 の応答は変えていない
- Claude へのすべてのプロンプトに子ども向けの安全の規則（`CHILD_SAFETY_RULES`）を入れた。モデル id はリポジトリに無い（`CLAUDE_MODEL` パラメーター）

## 8. 未決定・お願い

1. **整合（Integration）**: UI はまだ v1 エンジン。v3 に切り替えるときは `CharacterV2.fromJson`（v1 の移行）と `admitReportV2`、`judgeDrawing` の `v2` 入力、`registerCharacter` の `schema: 2` を使う
2. **GCP**: `engines/v3Engine.ts` は `RealtimeBattle` と `ratedFighterFromSnapshot` をつなぐだけ。`snapshots` の `engine.trust` は隠し要素の材料なので、クライアントに送らないこと → **対応済み**（Server チーム。REALTIME_PROTOCOL §9。v2 のスナップショットは Firestore のルールで持ち主にも読ませない）
3. 技の名前を後から AI に作らせる `generateMove`（Lv10・Lv50、隠し要素の作り直し後の名前）→ **対応済み**（BACKEND.md §5 `generateMove`。失敗したらテンプレートの技）
4. 画像ハッシュは端末が送る値を信じている → **対応済み**: サーバーがアップロードされた PNG の SHA-256 から作り直す（TRUST.md §8。アプリも `imageHash = sha256(切り抜き PNG)` にそろえると、端末とオンラインの能力が一致する）
5. 実際の子どもの絵での属性の割合・kid の分布は未確認（GAME_DESIGN_V2 Q1）。CPU の絵は合成なので、ステージ表は実機の絵が増えたら `tune-stages` をやり直す
