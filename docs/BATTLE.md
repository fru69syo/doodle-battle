# バトル仕様（Battle チーム） v2（specVersion 2）

SPEC §4 の実装仕様。**数値はすべて `shared/battle_spec/battle_spec.json` が正**（このドキュメントの数値はその時点の値の説明）。
Dart（端末: CPU 戦）と TypeScript（サーバー: オンライン戦）の 2 実装が `shared/battle_spec/golden_vectors.json` でビット単位に一致することをテストで保証する。

## 1. ファイル構成

| パス | 内容 |
|---|---|
| `shared/battle_spec/battle_spec.json` | 定数・相性表・わざ・ゲージ・成長・経験値・AI・文言・CPU ステージ表（唯一の正） |
| `shared/battle_spec/golden_vectors.json` | 正解例 109 件（battle 66 / ai 10 / xp 11 / stats 7 / damage 6 / rng 5 / fnv 4） |
| `app/lib/domain/battle/` | Dart エンジン（`battle.dart` が公開 API。Flutter 非依存） |
| `app/lib/domain/battle/battle_spec_asset.dart` | アプリ用ローダー `loadBattleSpec()` / `loadCpuRoster()`（rootBundle） |
| `app/lib/domain/battle/cpu_roster.dart` | CPU の絵（`app/assets/cpu/manifest.json`）のモデルと `cpuFighterSetup(spec, stage, roster)` |
| `app/lib/domain/battle/balance_sim.dart` | バランス用モンテカルロ（開発用。`battle.dart` からは export しない） |
| `app/assets/battle/battle_spec.json` | 上記 JSON の**バイト単位のコピー**（Flutter はパッケージ外のファイルをアセットにできないため） |
| `app/tool/sync_battle_spec.dart` | JSON をアセットへコピー |
| `app/tool/gen_golden_vectors.dart` | Dart エンジンから正解例を生成 |
| `app/tool/balance_sim.dart` | バランス表を出力 |
| `shared/battle_engine_ts/` | TS エンジン（npm パッケージ `@doodle-battle/battle-engine`） |
| `firebase/functions/src/battle/engine.ts` | サーバーのアダプタ `SharedEngine`（ビルド時に `src/` を vendor して使う。§9） |

### 仕様を変えるときの手順
1. `shared/battle_spec/battle_spec.json` を編集
2. `cd app && dart run tool/sync_battle_spec.dart`（アセットのコピー。ずれると `battle_spec_test` が落ちる）
3. `cd shared/battle_engine_ts && npm run gen`（TS に埋め込む `src/generated/specData.ts`。ずれると `spec.test.ts` が落ちる）
4. `cd app && dart run tool/gen_golden_vectors.dart`（各ベクトルは「何を確かめるか」の条件付きで seed を探索するので、意図が崩れたら生成が失敗する）
5. `dart run tool/balance_sim.dart` で §7 の目標を確認 → `flutter test` / `npm test`

## 2. 乱数（正規仕様）

**mulberry32**。状態は uint32 ひとつ（`rng.state`）。`Mulberry32(state)` で同じ列を再開できる。

```
next():
  s = (s + 0x6D2B79F5) mod 2^32
  t = s
  t = imul(t XOR (t >>> 15), t OR 1)
  t = t XOR ((t + imul(t XOR (t >>> 7), t OR 61)) mod 2^32)
  return (t XOR (t >>> 14)) as uint32
imul(a, b) = (a * b) mod 2^32           // JS Math.imul。Dart は 16bit に分割して計算
nextInt(n) = next() mod n               // 1 <= n < 2^31。剰余の偏りは許容
```

- 補助: `fnv1a32(string)`（UTF-8 バイト列の FNV-1a）、`deriveSeed(seed, stream) = mulberry32(seed XOR imul(stream+1, 0x9E3779B1)).next()`
- **ストリームの約束**: 試合 seed（uint32）から `deriveSeed(seed, 0)` = バトル、`1` = side a の AI、`2` = side b の AI。AI の乱数がバトルの乱数をずらさないよう必ず分ける
- 浮動小数点は一切使わない。割り算はすべて非負整数の切り捨て（JS は `Math.floor(a/b)`、値は常に 2^53 未満）

## 3. バトルの状態と1ターンの解決

`BattleState { turn, a, b, winner, endReason }`、`FighterState { element, level, maxHp, hp, atk, def, spd, specialPower, gauge, guardStreak, usage{tackle,element,guard,special}, lastAction }`。JSON 形は Dart / TS 共通。

`initBattle(spec, setupA, setupB)`: `maxHp = stats.hp × hpMultiplier(3)`、各ステータスは最低 1、`specialPower = 120 + 進化ボーナス`（Lv20 でんせつ +20）。

`resolveTurn(spec, state, actionA, actionB, rng) -> { state, events }`（終了済みの state を渡すと例外）:

1. `turnStart` を出す。a, b の順に行動を正規化:
   - `timeout` → `timeout` イベント、`spec.timeoutAction`（たいあたり）にする
   - `special` でゲージ < 100 → `specialNotReady` イベント、たいあたりにする
   - `usage` と `lastAction` を更新。`guardStreak` は guard なら +1、それ以外は 0
2. 行動順: spd が高い方が先。同じなら **`nextInt(2)`（0 → a が先）**。spd が同じなら行動に関係なく必ず 1 回引く
3. まもる: 行動順に、guard を選んだ側は `guard` イベント（`damageTakenPct` = 連続回数で 50 / 75 / 100%、2 回目以降 `weakened: true`）、ゲージ +20。**まもるは素早さに関係なくそのターンの攻撃より先に効く**
4. 攻撃: 行動順に。**HP 0 の側は行動しない**（倒れた後攻は動かない）
   1. `move` イベント（ぞくせいわざのときだけ `element` に自分の属性）
   2. ひっさつならゲージを 0 に（`gauge` イベント delta = −ゲージ）
   3. 命中: 命中率 < 100 のときだけ `nextInt(100)` を引き、`>= 命中率` なら `miss`（たいあたり/ぞくせいわざはゲージ +10）。終わり
   4. 会心: `nextInt(100) < 10` で会心
   5. 乱数幅: `75 + nextInt(26)`（75〜100%）
   6. ダメージ計算（§4）。`crit` → `effectiveness`（等倍でないとき、文言付き）→ `damage { target, amount(実際に減った HP), hp, guarded }`
   7. 攻撃側ゲージ +20（ひっさつ以外）。受けた側が生きていれば `5 + floor(減った HP × 50 / maxHp)` 溜まる。HP 0 なら `faint`
5. 終了判定: どちらかが倒れていれば KO（勝者は生きている方）。そうでなく `turn >= turnCap(30)` なら HP 割合を整数で比較（`hpA×maxB` vs `hpB×maxA`）、完全に同じなら `nextInt(2)`（0 → a）。`battleEnd { winner, reason: ko | turnCap }`。引き分けは無い

ゲージは 0〜100 に丸め、実際に変化したときだけ `gauge` イベントを出す（delta は丸めた後の差）。

## 4. ダメージ式

```
eff = floor(atk × (atk + k×def) / ((k+1) × def))        k = defenseWeight = 3
pow = floor(power × typePct / 100) + basePower           basePower = 50
d   = floor(pow × eff × scalePct / 10000)                scalePct = 55
d   = floor(d × 150 / 100)          （会心のときだけ）
d   = floor(d × variancePct / 100)  （75〜100）
d   = floor(d × guardTakenPct / 100)（まもる: 50 / 75 / 100）
d   = max(1, d)
```

| わざ | 威力 | 命中 | 相性 |
|---|---|---|---|
| たいあたり | 40 | 100 | なし（等倍） |
| ぞくせいわざ | 60 | 90 | 自分のぞくせい |
| ひっさつ | 120（でんせつ 140） | 100 | **なし**（§8 参照） |

相性表（攻撃側→防御側、%）: fire→leaf / leaf→thunder / thunder→water / water→fire が 150、その逆向きが 75、shadow⇄rainbow は双方 150、それ以外 100。

目安（Lv1・のびのび絵・各ステータス 90、maxHp 270、乱数 100%・会心なし）: たいあたり 44、ぞくせいわざ 54（有利 69 / 不利 47）、ひっさつ 84。乱数で 75% まで下がる。

## 5. イベント（UI 用、JSON 形は共通）

| type | フィールド | 表示例（`spec.texts`） |
|---|---|---|
| `turnStart` | turn | |
| `timeout` | side | じかんぎれ！ たいあたり！ |
| `specialNotReady` | side | ゲージが たりない！ たいあたりに した |
| `guard` | side, damageTakenPct, weakened | まもりの たいせい！ / まもりが よわく なっている… |
| `move` | side, move, element\|null | 「○○の たいあたり！」 |
| `miss` | side | でも はずれた！ |
| `crit` | side | きゅうしょに あたった！ |
| `effectiveness` | side, multiplierPct, text | こうかは ばつぐんだ！ / こうかは いまひとつの ようだ… |
| `damage` | target, amount, hp, guarded | |
| `gauge` | side, delta, value | value = 100 で「ひっさつ OK」表示 |
| `faint` | side | たおれた！ |
| `battleEnd` | winner, reason | |

## 6. 成長・経験値（SPEC §4.2）

- 現在のステータス: `floor(Lv1値 × (100 + g×(L−1) + 3×たねの数) / 100)`（最低 1）。**g = 4（普通）/ 12（しょぼキャラ: skill > 75）**（`growth.levelUpStatPct` / `growth.shoboLevelUpStatPct` / `growth.shoboSkillAbove`）。`currentStats(spec, character)`、`statsAtLevel(spec, base, L, seeds, isShobo:)`
  - しょぼキャラ（予算 0.35 倍）は Lv30 で Lv1 の 4.48 倍、普通のキャラは 2.16 倍。**Lv30 のしょぼ ≒ Lv15 の普通のキャラ**（ユーザー決定「育てれば戦える」、§8）
- 次のレベルまで: `50 + 25×L`。最大 Lv30（到達時の余りは捨て、xp = 0）
- 1 戦の経験値: `floor(基本(勝ち100/負け40) × ステージ倍率% × (しょぼなら150 それ以外100) × (広告なら2 それ以外1) / 10000)`。オンラインはステージ倍率 100・広告なし（サーバーも同じ `xpForBattle` を使う）
- `applyXp` は複数レベルアップをまとめて処理し、`levelsGained / seedsGained / evolutions / reachedMaxLevel` を返す
- パワーのたね: 1 レベルにつき 1 個。**未使用数 = (L−1) − 振った数**（`Character.seedAllocations` だけで表せるのでモデル変更は不要）。`allocateSeed` で 1 個使う
- 進化: Lv10 かがやき、Lv20 でんせつ（ひっさつ +20）
- 改ざん検出（サーバー）: `maxStatsAtLevel(base, L, isShobo)`（全部のたねを 1 ステータスに振った上限。しょぼの成長率込み）。サーバーの `validateStatClaim` / `statCapsAtLevel` がこれを使う

## 7. CPU AI とステージ

AI は `chooseCpuAction(spec, state, side, tier, rng)`。決定的（専用ストリームの rng を使う）。

- **よわい**: 重み付きランダム（たいあたり 40 / ぞくせいわざ 40 / まもる 20 / ひっさつ 40（溜まっているときだけ））。`nextInt(合計)` を 1 回
- **ふつう**: ひっさつが溜まっていれば使う。でなければ（直前にまもっていなければ）`nextInt(100) < 10` でまもる。相性が不利ならたいあたり、それ以外はぞくせいわざ
- **つよい**:
  1. 最低乱数・会心なしでも倒せるわざがあれば使う（たいあたり → ひっさつ → ぞくせいわざ の順、rng なし）
  2. 相手のひっさつが溜まっていて、それで倒されうる（最大乱数）がまもれば耐えられるなら、`nextInt(100) < 80` でまもる
  3. ひっさつが溜まっていれば使う。ただし相手が「まもり癖」（2 ターン以上・まもる率 40% 以上）で、直前にまもっていない（＝今まもりそう）なら温存
  4. 期待値 `(floor(威力×相性/100) + basePower) × 命中` が高い方（同値ならたいあたり）

**ステージ表**（`cpu.stages`）: 各行 `{stage, cpuId, level, recommendedLevel, aiTier, xpMultiplierPct}`。
- `cpuId` は Vision の `app/assets/cpu/manifest.json` の 12 体（各ぞくせい 2 体）。CPU は manifest の Lv1 ステータスを `statsAtLevel`（たね無し）で `level` まで育てる（`cpuFighterSetup`）
- 10 ステージずつの 3 章。各章は弱い絵 → 強い絵の順で、最後（10/20/30）は予算の大きい にじ（rainbow_cat / rainbow_robot）がボス。となり合うステージは必ず違うぞくせい（fire 5 / water 5 / leaf 6 / thunder 5 / shadow 5 / rainbow 4）
- `recommendedLevel`（「おすすめ Lv」）: 1,1,2,2,3,3,4,5,5,6,7,8,9,10,10,11,12,13,14,15,16,17,18,20,21,22,24,25,27,30
- `level`（CPU の Lv）: 絵の強さの差が大きいので、**おすすめ Lv ののびのびキャラ（たね使用済み・ふつう AI）の勝率が 85% → 60% に下がっていく曲線**（ボスは 50 / 45 / 40%）になるよう、シミュレーションでステージごとに決めた。そのため弱い絵は CPU の Lv がおすすめ Lv より低いことがある
- AI は 1–7 よわい / 8–18 ふつう / 19–30 つよい、経験値倍率 `100 + 5×(stage−1)`%（ステージ30で 245%）

## 8. バランス（モンテカルロ）

`cd app && dart run tool/balance_sim.dart 20000`。各シナリオ 20,000 戦、AI はふつう同士（記載があるものを除く）。のびのび絵 = skill 15 / energy 80、しょぼ = skill 90 / energy 80。Lv1 ステータスは SPEC §3.2 の予算をランダムな重み（各 ≥ 0.15）で配分（Vision の生成の近似）。`balance_sim_test.dart` が同じ目標を 2,000 戦で毎回検証する。

| シナリオ | a の勝率 | 平均ターン | 4–8 ターン | 最長 |
|---|---|---|---|---|
| 同じキャラ同士（ミラー） | **49.8%** | 6.8 | 69% | 24 |
| のびのび同士（配分ランダム） | 49.8% | 5.9 | 83% | 18 |
| 相性有利（fire vs leaf、配分ランダム） | **74.0%** | 5.6 | 82% | 17 |
| 相性有利（thunder vs water、配分均等） | 87.4% | 5.6 | 99% | 10 |
| shadow vs rainbow（相互有利） | 50.1% | 5.1 | 80% | 17 |
| Lv6 vs Lv1 | **87.2%** | 5.6 | 81% | 16 |
| Lv15 vs Lv10 | 81.3% | 5.7 | 82% | 16 |
| Lv30 vs Lv25 | 74.5% | 5.6 | 84% | 16 |
| つよい vs ふつう | 53.5% | 5.7 | 85% | 16 |
| つよい vs よわい | 67.2% | 6.3 | 80% | 20 |
| ふつう vs よわい | 65.8% | 6.6 | 77% | 19 |
| よわい同士（まもる多め） | 49.8% | 7.5 | 68% | 22 |

**しょぼキャラの成長**（a = しょぼ skill 90 / energy 80、b = のびのび skill 15 / energy 80。目標: 同じ Lv では < 20%、Lv30 しょぼ vs Lv15 のびのびは 40–60%）

| シナリオ | しょぼの勝率 | 平均ターン |
|---|---|---|
| 同じ Lv1 | **0.0%** | 2.4 |
| 同じ Lv10（たね無し / たね使用） | **0.0% / 0.0%** | 3.7 |
| 同じ Lv20（たね無し / たね使用） | **0.6% / 0.3%** | 4.4 |
| 同じ Lv30（たね無し / たね使用） | **2.3% / 1.3%** | 4.9 |
| しょぼ Lv30 vs のびのび Lv15 | **53.8%** | 5.8 |
| 同上、両方たね使用（しょぼ 29 個 / のびのび 14 個を均等に） | **48.0%** | 5.8 |
| しょぼ Lv30 vs のびのび Lv13 / Lv17 | 67.8% / 40.4% | 5.8 |
| しょぼ同士 | 49.5% | 6.1 |

成長率 11% だと Lv30 vs Lv15 が 37%（たね使用 31%）、13% だと 69%（64%）で、12% だけが両方 40–60% に入った。

**CPU ステージ**（プレイヤー = おすすめ Lv ののびのびキャラ（配分ランダム、たね使用済み）、ふつう AI。各 5,000 戦）

| ステージ | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | **10** |
|---|---|---|---|---|---|---|---|---|---|---|
| 勝率 | 88% | 85% | 81% | 79% | 83% | 82% | 81% | 78% | 81% | **53%** |
| ステージ | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | **20** |
| 勝率 | 77% | 71% | 74% | 72% | 73% | 73% | 72% | 71% | 67% | **41%** |
| ステージ | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | **30** |
| 勝率 | 66% | 63% | 62% | 66% | 65% | 61% | 64% | 59% | 60% | **40%** |

ターン上限（30）に達した試合はどのシナリオでも 0 件。ランダム行動のファズテストでも必ず 30 ターン以内に終わる（`turnCap` があるので無限には続かない）。

**調整の経緯**:
- 最初の案（相性倍率を最終ダメージに掛ける、ひっさつも属性あり）では相性有利の勝率が 95%（配分均等だと 99.9%）。ぞくせいわざの 1 ターンあたりの差が約 2 倍になるため、乱数幅・会心・ゲージの追い上げをどう調整しても 85% を切れなかった
- そこで (1) **相性はわざの威力に掛け、全わざ共通の基礎威力 50 を足す**、(2) **ひっさつは無属性**、にして 74% に下げた
- 防御の効き（`defenseWeight` 3）・乱数幅 75–100%・会心 10% で Lv 差の影響をやや緩めた（Lv+5 は低レベルほど差が大きい: +4%/Lv が Lv1 基準の加算なので）
- まもるはそのターンの攻撃を捨てるので、ひっさつ以外に対しては損。まもる時にゲージ +20 を与えて「ためる」選択肢にした。つよい AI は「まもれば耐えられるひっさつ」のときだけまもる

## 9. 連携メモ

- **Backend（配線済み）**: `firebase/functions/scripts/sync-shared.mjs` がビルド/リント/テストの前に `shared/battle_engine_ts/src` と `shared/battle_spec/*.json` を `src/vendor/` へコピーする。`src/battle/engine.ts` の `SharedEngine`（id `shared-<specVersion>`、今は `shared-2`）が共通エンジンに処理を任せる
  - **乱数**: Mulberry32 の状態（uint32）を**エンジンの状態の中**に持つ（`{engine, seed, turn, rngState, inner: BattleState}`、`rngState` の初期値は `deriveSeed(seed, 0)`）。1 ターンの解決は保存された状態だけで決まり、Firestore のトランザクションで状態と一緒に更新されるので、seed と行動ログから試合全体を再現できる。BACKEND.md の案（`turnSeed(seed, turn)` でターンごとに乱数を作る）ではなくこちらにした理由: アプリの CPU 戦と同じ「1 試合 1 本の乱数列」になり、**ゴールデンベクトルの battle 66 件をアダプタにそのまま通して検証できる**（`test/unit/engine.test.ts`）
  - 時間切れは `resolveTurn(state, a, b, { a: true })` で共通エンジンに `'timeout'` として渡す（ターンログに `timeout` イベントが残る）
  - ターン上限は共通エンジンが処理する（`view.endReason = "turn_limit"`、HP 割合が完全に同じなら乱数で決めるので引き分けは無い）
  - ゴースト AI: 共通の `chooseCpuAction`（ふつう）。乱数は `turnSeed(seed, turn, "ghost-<side>")` で、バトルの乱数とは別
  - ステータス: `effectiveStats` = 共通の `statsAtLevel`（しょぼの成長込み）、上限チェックは `maxStatsAtLevel`。経験値は `xpForBattle`
  - spec を変えて specVersion を上げると engine id が変わり、進行中の試合は（設計どおり）中止になる
- **App/UI**: `loadBattleSpec()` / `loadCpuRoster()` で読み込み、`cpuFighterSetup(spec, spec.cpu.stage(n), roster)` で CPU を作る。`events` を順にアニメーション。文言は `spec.texts` / イベントの `text`。ステージ選択では `recommendedLevel` を「おすすめ Lv」として出せる
