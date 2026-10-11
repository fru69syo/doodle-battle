# Trust: 紙に手で描いた絵だけを受け付ける (SPEC §11.1, §11.3)

Owner: Trust チーム. Code: `app/lib/features/drawing_analysis/non_drawing_detector.dart`,
`src/authenticity.dart`, `feature_words.dart`, `app/lib/features/draw/`, `app/lib/features/birth/ai_report.dart`,
`firebase/functions/src/ai/` (origin judgement), `firebase/functions/src/callables/reportAiSuggestion.ts`.

## 1. Principles

1. **Kids draw for fun, not for a score.** The words 「しょぼキャラ」「げいじゅつか」, skill / のびのび度 and
   "grows N× faster" are never shown (screens, dialogs, store copy, site). Internal values
   (`skill`, `isShobo`, the 12 % growth rate, battle numbers, the server's `isShobo`) are unchanged.
   The birth screen shows 「この えの とくちょう」: 2–3 positive trait words (§5) instead of stat bars.
2. **Not-a-paper-drawing is refused, not weakened.** AI-generated / digital illustrations, printed
   pictures, photos of screens and photographs → 「かみに かいた えを とってね」 and a retake prompt.
3. **False rejects of real children's drawings are the worst outcome.** Every on-device rule is a
   conjunction of independent signals with thresholds outside the range measured on kids' drawings;
   the cloud judge only rejects on a confident verdict (`unsure` never rejects). When in doubt we
   accept: a polished picture that slips through still becomes an internally weak character.
4. **Never blame the child.** Messages only say what to do next (「もうすこし かいてみよう」,
   「かみに かいた えを とってね」, 「しゃしんが よめなかったよ。もういちど とってみてね」).

## 2. Capture flow (app)

- **Camera only for children.** The draw screen has one button (`draw-camera`) and the capture tips
  row (しろい かみ・ふとい せん・あかるい ばしょ, `CaptureTips`).
- **Capture guide** (`showCaptureGuide`, key `capture-guide`) before the camera opens; shown once per
  app session and again after a "not paper" / unreadable retake (`captureGuideSeenProvider`).
- **Retake flow** (`showRetake`, keys `retake-drawMore|notPaper|unreadable`): the message, the tips
  (for notPaper/unreadable) and 「もういちど とる」/「かきたして とる」 or 「あとで」.
- **In-app drawing tool** (「アプリで かく」, `draw-in-app`, SPEC §12.2 input ②): drawn with a finger on our
  canvas, no import / paste. Its picture skips paper detection and the authenticity checks (§3) — it is
  digital by construction — and a cloud "not hand-drawn" verdict is ignored for it; everything else
  (empty check, features, stats, cloud appropriateness) is the same. Details: docs/PUPPET.md §4.2.
- **Album import only via おうちのひと** (behind the parental gate): 「アルバムから とりこむ」 arms a
  one-shot flag (`albumImportArmProvider`) and goes to the draw screen, which consumes it and opens
  the gallery once. The picture goes through exactly the same checks.
- `DrawFlow` returns `DrawRetake(message, notPaperDrawing)` for both on-device rejects and a cloud
  `rejectCode` (§4). Parts / effects of the drawing loop use the same analyzer (`captureLoopDrawing`).

## 3. On-device detector (`classifyAuthenticity`)

Signals (`AuthenticitySignals`): paper likeness / detection, photo likelihood, digital polish,
symmetry, gradient share, fine-line ratio, edge coherence, background share / flatness, camera noise σ
on native-resolution patches, exact-flat share (3×3 uniform neighbourhoods), luma / chroma 2D lattice
strength and number of drawing patches with a lattice. Rules, in order:

| # | Verdict | Rule (all must hold) |
|---|---|---|
| 1 | `printed` / `screen` | lattice ≥ 10 (luma or chroma) in ≥ 2 patches; screen when chroma ≥ 1.25 × luma |
| 2a | `digital` (sticker / AI mascot / shaded line art) | exact-flat ≥ 0.05, noise < 1.2, polish ≥ 0.55, symmetry ≥ 0.9 |
| 2b | `digital` (full-frame painting) | paper ≤ 0.4, background ≤ 0.5, exact-flat ≥ 0.15, noise < 0.6, gradient ≥ 0.4 |
| 3 | `photo` | photo ≥ 0.62, paper ≤ 0.05, fine lines < 0.2, coherence ≥ 0.8, gradient ≥ 0.3 |

`paperLikeness` alone is **not** required: tinted paper, dim rooms and close-ups give ≈ 0 for real
drawings (SPEC asked for it as mandatory; measured, that would refuse ~5 % of real drawings, so it
is only used inside conjunctions).

### Calibration (`dart run tool/trust_calibration.dart [--kids dir]`)

Synthetic cases (`app/tool/src/trust_cases.dart`, also asserted in
`test/features/drawing_analysis/authenticity_test.dart`): 45 kids' drawings (crayon / felt-tip /
pencil / watercolour, photographed on white, yellow, pink, crumpled paper, dim room, close-up,
low-quality JPEG, phone noise reduction, 512 px gallery, 4000 px original) and 19 non-drawings.

| Set | Result |
|---|---|
| kids' drawings, synthetic | 0 / 45 rejected (0 %) |
| kids' drawings, Meta Amateur Drawings sample (300, tuning) | 0 / 300 rejected (0 %) |
| kids' drawings, Meta Amateur Drawings hold-out (150, never tuned on) | 0 / 150 rejected (0 %) |
| digital / AI (sticker, painting, shaded line art; PNG + JPEG) | 8 / 8 detected |
| printed (halftone 5–7 px) | 4 / 4 detected |
| photo of a screen | 3 / 3 detected |
| photograph (still life, landscape) | 4 / 4 detected |

The Amateur Drawings dataset (MIT, facebookresearch/AnimatedDrawings) is only used locally and is
never committed. An early iteration that required detected paper refused 12.7 % of that sample
(photo 6.3 %, no paper 5.0 %, printed 1.0 %, digital 0.3 %), which is why paper is not mandatory.

Known limits: a screen photo with a weak lattice (8–14) and a very clean AI picture printed and
photographed on paper can pass; they then become internally weak characters, and the cloud judge (§4)
catches them when the parent allowed it.

### 3.1 Hold-out

Final run (2026-10-10, thresholds above): 0 / 150 hold-out images rejected, 0 / 150 of the local
tuning subset, 0 / 45 synthetic kids' drawings; every synthetic non-drawing detected. The hold-out
is small (150): the true false-reject rate on real photos is only bounded (≈ < 2 % at 95 %
confidence); keep monitoring after release (retake rate per reason is not collected — check support
mail and Play reviews).

## 4. Cloud origin judgement (`judgeDrawing`, `registerCharacter`)

Both Claude prompts ask for `origin: hand_drawn | unsure | ai_generated | photo_print_or_screen`,
explain that the picture is a cut-out (background removed, colours normalised — not a digital sign)
and that refusing a real child's drawing is the worst mistake. `originRejectCode` maps only the
confident values: `ai_generated` → `IMAGE_AI_GENERATED`, `photo_print_or_screen` →
`IMAGE_NOT_DRAWING`. `judgeDrawing` returns `rejectCode` (+ `reasons` `ai_generated` /
`not_drawing`, `appropriate: false`); the app shows the retake flow. `registerCharacter` rejects
with the same codes; both map to 「かみに かいた えを とってね」. Contracts: docs/BACKEND.md.

## 5. Positive trait words (`positiveTraits`)

Deterministic from the feature map: せんの いきおい, いろの にぎやかさ, かたちの ユニークさ, まんまる パワー,
とげとげ パワー, かみ いっぱいの おおきさ, ぬりぬり パワー, もようの たのしさ, すらっと ながい かたち,
くろの かっこよさ. Up to 3 (score ≥ 0.3), at least 2 (fallbacks). They describe what is special, never
how good; they do not depend on skill.

## 6. Reporting AI suggestions (Google Play AI-generated content policy)

Naming screen → 「いやな ことばを おしえる」 (`ai-report`, only when the cloud suggested something):
pick the name / move name, pick a preset reason (いやな / こわい / へんな ことば, そのほか). The word is
removed from the suggestions and not used for the character. Every report is logged on the device
(`ai_reports.json`, newest 100) and sent with `reportAiSuggestion` when consented and online
(unsent ones are retried with the next report). Opponent pictures/names keep the existing
`reportCharacter` button.

## 7. 「えは AIの がくしゅうに つかいません」

Shown on the first-run consent screen and in おうちのひと (`NoAiTrainingNotice`), in the cloud-judge
consent text, the store description (■ データの取り扱い, short description), the support page and
the privacy policy (`#no-ai-training`).
