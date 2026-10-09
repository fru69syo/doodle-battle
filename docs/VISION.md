# Vision: 絵の解析（設計・根拠・キャリブレーション）

担当: Vision チーム / ブランチ `feat/vision` / コード `app/lib/features/drawing_analysis/`

SPEC §3 の実装メモ。**「上手いほど弱い・元気な落書きほど強い・ほぼ空っぽは弱い」**を、
端末内の純 Dart（`package:image` でデコード／エンコードのみ、残りは型付き配列の自前処理）で実現する。

---

## 1. 公開 API

`import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';`

| シグネチャ | 内容 |
|---|---|
| `Future<DrawingAnalysisResult> analyzeDrawing(Uint8List imageBytes)` | `Isolate.run` で UI スレッド外で解析。デコード不能なら `UndecodableImageException` |
| `Future<DrawingAnalysisReport> analyzeDrawingDetailed(Uint8List imageBytes)` | 上と同じ＋診断（`rejectReason`, `features`(型付き), `paperQuad`, `silhouette`, 段階別 `timingsMs`） |
| `DrawingAnalysisReport analyzeDrawingSync(Uint8List)` | 同期版（テスト・ツール用。アプリでは使わない） |
| `DrawingRejectReason? rejectReasonOf(DrawingAnalysisResult)` | `features` マップから「描き直してね」判定を再計算 |
| `DrawingAnalysisResult applyCloudSkill(DrawingAnalysisResult, double cloudSkill)` | §3.3 のブレンド後、同じ features / energy から Lv1 ステータスを再計算 |
| `double blendCloudSkill(double device, double cloud)` | `0.6*device + 0.4*cloud`（0–100 にクランプ） |
| `Stats computeBaseStats(DrawingFeatures f, double energy, double skill)` | §3.2 のステータス生成（純関数） |
| `Stats computeBaseStatsFromMap(Map<String, num> features, double energy, double skill)` | `Character.features` からの再計算用 |
| `double computeEnergy(DrawingFeatures)` / `double computeSkill(DrawingFeatures)` / `ElementType computeElement(DrawingFeatures)` | スコア関数（純関数。サーバーでの再検証にも使える） |
| `double skillMultiplier(double)` / `double statBudget(double energy, double skill)` / `List<double> statWeights(DrawingFeatures)` | §3.2 の部品 |
| `DrawingRejectReason.nearlyEmpty.message` | `'もうすこし かいてみよう'` |

UI からの使い方:

```dart
final report = await analyzeDrawingDetailed(bytes);
if (report.rejectReason != null) {
  showHint(report.rejectReason!.message); // もうすこし かいてみよう
  return;
}
final result = report.result; // DrawingAnalysisResult（共有モデル）
```

## 2. パイプライン

| 段階 | ファイル | 処理 |
|---|---|---|
| 正規化 | `src/normalize.dart` | デコード → EXIF の向き(1–8)を適用 → アルファは白に合成 → 面積平均で縮小: 高解像度コピー（長辺 ≤1024, 透視変換のサンプリング用）と作業画像（長辺 **512**）。`imageHash = sha256(幅,高さ,作業画像の RGB)` |
| 紙の検出 | `src/paper_detection.dart` | 輝度をぼかして Otsu で明部 → opening → 最大連結成分 → 穴埋め → 輪郭追跡 → 凸包 → 凸包上の「面積最大の四角形」（対角の極値から貪欲に改善）。採用条件: 面積 ≥15%、四角形/領域 0.85–1.2、内角 35–145°、外側との輝度差 ≥25、紙らしさ ≥0.5、画像の 3 辺以上に接していない。見つからなければ全体を使う。採用時は Heckbert の射影変換で長辺 512 の正面画像に（各辺 1.5% 内側に寄せて紙の縁を除く） |
| 白バランス | `src/white_balance.dart` | 32px セルごとに明るい上位 20% を紙とみなし、彩度が高い／暗すぎるセルは隣から補間 → 平滑化したゲイン場で割り算（照明ムラも補正）、紙の色の中央値で RGB を白に |
| 前景 | `src/segmentation.dart` | インクスコア = max(暗さ, 彩度×1.1)（黄色いクレヨンも拾う）。しきい値 = max(紙ノイズ中央値+6·MAD, clamp(Otsu, .13, .32))、0.6 倍で弱いエッジをヒステリシス接続 → closing(1px) → 連結成分（8 近傍）→ 小さいゴミ（<0.02%）と縁に張り付いた成分を除去 → シルエット = closing(3px)+穴埋め → 2px 膨らませてアルファ（外周 1px は半透明） |
| 切り抜き | `src/cutout.dart` | 白バランス後の色 + アルファの RGBA PNG、シルエットの外接矩形+4px に切り詰め（長辺 ≤512） |
| 特徴量 | `src/feature_extraction.dart`, `src/edge_field.dart`, `src/morphology.dart` | §3 参照 |
| スコア | `scoring.dart` | energy / skill / element / reject |
| ステータス | `stat_generator.dart` | §3.2 |

決定性: 乱数は一切使っていない（同じバイト列 → 同じデコード → 同じ整数／倍精度演算の順序）。
テストで同期版 2 回・isolate 版 1 回の結果（切り抜き PNG のバイト列まで）が一致することを確認している。
乱数が必要になったら `imageHash` を seed にすること。

## 3. 特徴量（`DrawingFeatures.toMap()` のキー＝永続化・サーバー送信の契約）

ピクセル量はすべて「紙を長辺 512px にした画像」上の値。

| キー | 定義 |
|---|---|
| `inkCoverage` | インク画素 / 紙の画素 |
| `silhouetteCoverage`, `bboxCoverage` | キャラの塗りつぶし形状 / 外接矩形 が紙に占める割合（「大きさ」） |
| `colorCount` | 有意な色相クラスタ数（15°×24 ビンを平滑化して山登り、インクの 3% 以上かつ有彩色の 4% 以上） |
| `achromaticCount` | 黒 (V<.45)・灰 がそれぞれインクの 5% 以上あるか（0–2）。SPEC の「白黒灰は別に数える」 |
| `dominantHue`, `dominantHueShare`, `balancedHueCount`, `chromaticShare`, `redShare` | 最大クラスタの平均色相、その割合、12% 以上を持つクラスタ数、有彩色の割合、赤（±20°）の割合 |
| `darkness` | インクの平均 (1−V) |
| `strokeSmoothness` | 0.5·ramp(edgeCoherence,.55,.85) + 0.2/(1+(contourRoughness/0.45)²) + 0.3·(1−ramp(wobble,.4,2.5)) |
| `edgeCoherence` | エッジ上の構造テンソル coherence の平均（きれいな線 ≈0.9、クレヨンの粒状感 ≈0.45） |
| `contourRoughness` | 輪郭を 5px 平滑と 17px 平滑したものの平均ずれ（上位 15% は角として除外） |
| `wobble` | 輪郭の曲率の符号反転（ヒステリシス付き）数 / 100px。開いた線の両端の 2 回は除く。手のふるえ |
| `symmetry` | シルエットと（2px 太らせた）インクそれぞれの左右反転 IoU（重心まわり ±3px で最良）の平均 |
| `shadingLevel` | 0.5·ramp(同色内の明度段数,2,6) + 0.5·ramp(gradientShare,.05,.35) |
| `gradientShare` | 塗りの内部で「なだらかで局所的に平面的」な画素の割合（グラデーション・ぼかし陰影）。クレヨンの粒は二階差分で弾く |
| `detailDensity` | 0.75·ramp(fineLineRatio,4,14) + 0.25·ramp(小さな部品数,3,15) |
| `fineLineRatio` | 細線（幅≲3px の暗い谷、coherent、12px 以上連結）の長さ / √(外接矩形面積) |
| `coherentEdgeDensity` | 参考値: coherent なエッジ画素 / シルエット面積 |
| `spikiness`, `convexityDefects` | 1 − 凸包周長/輪郭周長、深いくぼみの数 |
| `roundness`, `solidity` | 4πA/P²、面積/凸包面積（塊っぽさ） |
| `aspectRatio`, `elongation` | 外接矩形の幅/高さ、主軸比 √(λ1/λ2)（≥1, 最大 10） |
| `lineThickness` | 距離変換の尾根の中央値から求めた線幅（px, 最大 60 = ベタ塗り） |
| `uniqueColors`, `huePeakedness`, `paperLikeness` | 4bit 量子化の色数、色相が山の近くに集まっている割合、紙らしさ（明るく無彩色で平坦な背景が支配的か） |
| `photoLikelihood` | 0.35·(1−paperLikeness) + 0.2·ramp(silhouetteCoverage,.5,.9) + 0.2·ramp(gradientShare,.1,.4) + 0.1·ramp(uniqueColors,150,500) + 0.15·ramp(1−huePeakedness,.1,.4) |
| `paperDetected` | 紙を検出して透視補正したか (0/1) |

## 4. スコア

### energy（のびのび度） — `computeEnergy`

```
ink    = ramp(inkCoverage, 0, 0.25) ^ 0.7
size   = ramp(sqrt(bboxCoverage), 0.10, 0.65)
colour = ramp(colorCount + 0.5*achromaticCount, 0.5, 5)
stroke = ramp(lineThickness, 1.5, 9)
gate   = smoothstep(inkCoverage, 0.002, 0.03)
energy = 100 * (0.35 ink + 0.25 size + 0.25 colour + 0.15 stroke) * gate
```

根拠: SPEC の f(インク量, 色数, 大きさ, 線の太さ)。インク量は子どもの塗り絵で 15–35% 程度なので 25% で頭打ち、
0.7 乗で少量の塗りにも報いる。大きさは面積の平方根（＝長さのスケール）で評価。
**gate** が「点 1 つ・線 1 本」対策の要。インクが紙の 3% 未満だと、大きさや色数をいくら稼いでも満点にならず、
0.2% 未満なら 0。大きな対角線 1 本（外接矩形は大きい）でも gate で潰れる。

### skill（じょうずさ） — `computeSkill`

```
craft = 0.30·ramp(strokeSmoothness,.35,.85) + 0.20·ramp(symmetry,.45,.85)
      + 0.20·ramp(shadingLevel,.10,.60)     + 0.30·ramp(detailDensity,.15,.60)
photo = smoothstep(photoLikelihood, 0.45, 0.75)
skill = 100 · (1 − (1 − craft)(1 − photo))      // soft OR
```

根拠:
- 各項は「子どもの絵でほぼ 0、整った絵でほぼ 1」になる範囲に写像してから重み付け。1 つだけ高くても（例: 丸い塊は対称性が高い）上手判定にはならない。
- **なめらかさ**は、輪郭の幾何だけでは細い線のピクセル段差と手ブレの区別がつかなかった（両方 roughness≈0.4）。そこで
  ①エッジ方向の一貫性（構造テンソル coherence: クレヨンの粒状感で下がる）と ②曲率の符号反転頻度（手のふるえ）を主にした。
- **描き込み**は「細い線がキャラの大きさに対して何本分あるか」。シルエット面積で割ると棒人間（線しかない）が過大評価されたので √(外接矩形面積) で割る。クレヨンの粒による偽の細線は coherence と 12px 連結で除去。
- **写真らしさ**は soft OR で合成し、写真・デジタル画像は工芸点に関係なく 75 を超える（しょぼキャラ）。

### ぞくせい — `computeElement`

- 有彩色がインクの 25% 未満 → `shadow`（黒・灰の絵）
- 12% 以上のクラスタが 4 つ以上かつ最大が 45% 以下 → `rainbow`
- それ以外は最大クラスタの色相: 赤・橙・ピンク・茶 [320°, 42°) → `fire`、黄 [42°, 72°) → `thunder`、緑 [72°, 165°) → `leaf`、水色・青 [165°, 265°) → `water`、**紫 [265°, 320°) → `shadow`**（SPEC 未定義のため決定。要 PM 確認）

### 描き直し判定 — `rejectReasonFor`

`inkCoverage < 0.002` または `bboxCoverage < 0.004` → `DrawingRejectReason.nearlyEmpty`（「もうすこし かいてみよう」）。
結果自体は返す（energy はほぼ 0）ので、UI 側で止めるかどうか選べる。

## 5. ステータス（SPEC §3.2 どおり）

```
budget = (200 + 2·energy) · skillMultiplier(skill)      // 0–30:1.0, 30–60:1.0→0.9, 60–75:0.9→0.7, >75:0.35
affinity_hp  = 0.6·roundness + 0.4·ramp(inkCoverage, 0, .3)
affinity_atk = 0.6·ramp(spikiness, 0, .3) + 0.4·redShare
affinity_def = 0.4·ramp(lineThickness, 1, 12) + 0.3·darkness + 0.3·solidity
affinity_spd = 0.6·ramp(elongation, 1, 3) + 0.4·(1 − ramp(lineThickness, 1, 12))
weight_k     = 0.15 + 0.40 · affinity_k / Σ affinity        // 各 ≥0.15、合計 1
stats        = 最大剰余法で整数化（合計 = round(budget)、同点は hp→atk→def→spd の順）
```

HP の表示倍率（×3）はバトル側の定義に従う。クラウド判定後は `applyCloudSkill` で skill をブレンドし、
同じ features / energy から再計算する（ぞくせいは変えない）。

## 6. キャリブレーション結果（合成画像、`flutter test` のログ）

テストは `test/features/drawing_analysis/`、合成画像は `synthetic_drawings.dart`（描画器は `tool/src/doodle_painter.dart`、すべて seed 固定）。

| ケース | energy | skill | element | Lv1 stats (hp/atk/def/spd) | 期待 |
|---|---:|---:|---|---|---|
| クレヨンの落書き（ふるえ・非対称・4 色） | 91.4 | 8.3 | fire | 96/114/102/71 | skill ≤35, energy 高 ✓ |
| 同 seed 2 | 91.6 | 8.5 | fire | 95/116/101/71 | ✓ |
| マーカーの棒人間（細いがふるえる線） | 39.8 | 20.3 | fire | 51/89/67/73 | 上手判定されない ✓ |
| きれいな対称線画＋グラデ陰影＋細部（フクロウ） | 68.2 | 78.3 | water | 30/32/26/30 | skill >60 ✓（しょぼ） |
| 写真（静物、ノイズ・グラデ・全面） | 77.8 | 99.7 | fire | 44/19/40/21 | skill >75 ✓ |
| 写真（風景） | 88.9 | 89.1 | leaf | 39/21/39/33 | skill >75 ✓ |
| 点 1 つ | 0.0 | – | – | – | reject ✓ |
| 短い線 1 本 | 0.0 | – | – | – | reject ✓ |
| 白紙 | 0.0 | – | – | – | reject ✓ |
| 単色の塊 赤/橙/青/水色/緑/黄 | 71–74 | 20–32 | fire/fire/water/water/leaf/thunder | – | ✓ |
| 黒・灰 | 68.2 | 23.9 | shadow | – | ✓ |
| 5 色の縞 | 97.1 | 20.0 | rainbow | – | ✓ |
| 机の上の紙（透視・照明ムラ・ノイズ, 1600×1200 JPEG） | 93.4 | 8.3 | fire | 98/116/106/67 | マスク IoU **0.961**（≥0.8 ✓） |

主要特徴量の分離（クレヨン / マーカー / 線画 / 写真）:
edgeCoherence 0.45 / 0.88 / 0.89 / 0.85、wobble 5.0 / 4.4 / 1.7 / 0、fineLineRatio 1.2 / 4.9 / 8.3 / 0.05、
gradientShare 0.06 / 0.00 / 0.44 / 0.37、photoLikelihood 0.02 / 0.00 / 0.20 / 0.73。

**性能**（この開発機、JIT の `flutter test`）: 800×600 PNG で 250–450ms、1600×1200 JPEG で約 650ms。
**4000×3000 JPEG で合計 約 1.7 秒**（うち正規化 1.35 秒の大半が JPEG デコード約 0.9–1.1 秒、残りの解析は約 0.35 秒）。
端末では AOT なのでさらに速い見込みだが、純 Dart の JPEG デコードが支配的なので、
UI 側で `ImagePicker.pickImage(maxWidth: 2048, maxHeight: 2048, imageQuality: 92)` を推奨（デコードが約 1/4）。

> 注意: 現状のしきい値は合成画像だけで決めた。実際の子どもの絵（クレヨン・色鉛筆・マーカー・鉛筆、照明条件いろいろ）で
> `dart run tool/analyze_dir.dart <フォルダ> --csv out.csv --cutouts out/` を回して再調整すること。調整箇所は `ramp(...)` の両端だけで済む設計。

## 7. CPU キャラ（`app/assets/cpu/`）

`dart run tool/gen_cpu_doodles.dart` で再生成（決定的）。子どものクレヨン風の 12 体を描画 → **本物の解析器に通し**、
切り抜き PNG を素材に、ぞくせい・energy・skill・Lv1 ステータスを `manifest.json` に書く（Battle チームは `id` で参照）。
各ぞくせい 2 体: `cpu_fire_blob`, `cpu_fire_spiky`, `cpu_water_snake`, `cpu_water_fish`, `cpu_leaf_frog`,
`cpu_leaf_caterpillar`, `cpu_thunder_bird`, `cpu_thunder_star`, `cpu_shadow_ghost`, `cpu_shadow_bat`,
`cpu_rainbow_cat`, `cpu_rainbow_robot`。狙いのぞくせいにならなければスクリプトが非 0 で終了する。

## 8. 決めたこと・PM に確認したいこと

1. **rejectReason の置き場所**: 共有モデル `DrawingAnalysisResult` にフィールドが無いので、`features` マップから `rejectReasonOf()` で再計算する方式にした。`DrawingAnalysisResult` に `DrawingRejectReason? rejectReason` を足すなら Vision 側はすぐ対応できる。
2. **紫 → shadow**、ピンク・橙・茶 → fire（SPEC に無い色の割り当て）。
3. きれいな陰影付き線画は skill ≈78 で**しょぼキャラ**になる（SPEC の「>60」より強め）。「大人が本気で描いた絵は強くならない」の趣旨どおりと判断。
4. サーバーでの改ざん検証: `computeEnergy` / `computeSkill` / `computeBaseStats` は features マップだけの純関数なので、Backend が TS に移植すれば features からステータスを再計算して照合できる（式は本書 §4–5）。features 自体の改ざんは画像の再解析かクラウド判定で別途検証が必要。
5. 解析 3 秒の基準は 12MP でも満たすが、デコード時間短縮のため UI の撮影時縮小（上記）を推奨。
