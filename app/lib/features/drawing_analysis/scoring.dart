import 'dart:math' as math;

import '../../domain/element_type.dart';
import 'drawing_features.dart';
import 'src/raster.dart';

/// Thresholds below which a drawing is considered (nearly) empty.
const double kMinInkCoverage = 0.002;
const double kMinBboxCoverage = 0.004;

/// のびのび度 (energy) 0..100 — SPEC §3.1-5.
///
/// A weighted sum of four "vigour" terms, multiplied by a gate that crushes
/// near-empty drawings (one dot / one short line):
///
/// * ink    (35%) — how much pigment is on the paper (saturates at 25%)
/// * size   (25%) — how much of the paper the character spans (bbox)
/// * colour (25%) — number of distinct colours, black/grey count half
/// * stroke (15%) — line thickness (thick crayon > fine pen)
///
/// gate = smoothstep(inkCoverage, 0.002, 0.03) — less than ~3% ink can not
/// reach full energy no matter how big or colourful it is.
double computeEnergy(DrawingFeatures f) {
  final ink = math.pow(ramp(f.inkCoverage, 0, 0.25), 0.7).toDouble();
  final size = ramp(math.sqrt(f.bboxCoverage), 0.1, 0.65);
  final colours = f.colorCount + 0.5 * f.achromaticCount;
  final colour = ramp(colours, 0.5, 5);
  final stroke = ramp(f.lineThickness, 1.5, 9);
  final gate = smoothstep(f.inkCoverage, kMinInkCoverage, 0.03);
  final raw = 0.35 * ink + 0.25 * size + 0.25 * colour + 0.15 * stroke;
  return _round1(100 * raw * gate);
}

/// じょうずさ (skill) 0..100 — SPEC §3.1-5. Higher = weaker character.
///
/// craft = 0.30 smoothness + 0.20 symmetry + 0.20 shading + 0.30 detail,
/// each term first remapped from its observed range on kids' drawings
/// (where it is ~0) to that of polished art (~1). Photo-likeness is then
/// combined as a soft OR, so a photo/digital image lands above 75
/// (しょぼキャラ) even when its "craft" terms are ambiguous:
///
///   skill = 100 * (1 - (1 - craft) * (1 - photo'))
///   photo' = smoothstep(photoLikelihood, 0.45, 0.75)
double computeSkill(DrawingFeatures f) {
  final smooth = ramp(f.strokeSmoothness, 0.35, 0.85);
  final sym = ramp(f.symmetry, 0.45, 0.85);
  final shade = ramp(f.shadingLevel, 0.1, 0.6);
  final detail = ramp(f.detailDensity, 0.15, 0.6);
  final craft = 0.30 * smooth + 0.20 * sym + 0.20 * shade + 0.30 * detail;
  final photo = smoothstep(f.photoLikelihood, 0.45, 0.75);
  return _round1(100 * (1 - (1 - craft) * (1 - photo)));
}

/// ぞくせい from colour (SPEC §1).
///
/// * < 25% of the ink is chromatic → shadow (black/grey drawing)
/// * >= 4 hue clusters each holding >= 12% of the colour and the largest
///   holding <= 45% → rainbow
/// * otherwise by the dominant hue: red/orange/pink → fire,
///   yellow → thunder, green → leaf, cyan/blue → water, purple → shadow.
ElementType computeElement(DrawingFeatures f) {
  if (f.chromaticShare < 0.25 || f.dominantHue < 0) return ElementType.shadow;
  if (f.balancedHueCount >= 4 && f.dominantHueShare <= 0.45) {
    return ElementType.rainbow;
  }
  final h = f.dominantHue;
  if (h < 42 || h >= 320) return ElementType.fire;
  if (h < 72) return ElementType.thunder;
  if (h < 165) return ElementType.leaf;
  if (h < 265) return ElementType.water;
  return ElementType.shadow;
}

/// Gentle message for every picture that is not a drawing on paper
/// (SPEC §11.1). It never blames the child.
const String kPaperDrawingMessage = 'かみに かいた えを とってね';

/// Why a picture should be redrawn / retaken rather than turned into a
/// character. All "not a drawing on paper" reasons share
/// [kPaperDrawingMessage]; the distinct values exist for diagnostics and
/// calibration (docs/TRUST.md).
enum DrawingRejectReason {
  /// Almost no ink (blank paper, a single dot or a tiny line).
  nearlyEmpty('もうすこし かいてみよう'),

  /// A photograph (of things, people or places) rather than a drawing.
  photo(kPaperDrawingMessage),

  /// A digital or AI-generated illustration (no camera noise, polished
  /// digital finish).
  digital(kPaperDrawingMessage),

  /// A printed picture (halftone dot pattern).
  printed(kPaperDrawingMessage),

  /// A photo of a screen (pixel grid / sub-pixel moiré).
  screen(kPaperDrawingMessage);

  const DrawingRejectReason(this.message);

  /// Hiragana message for children.
  final String message;

  /// True for every reason except [nearlyEmpty]: the picture is not a
  /// drawing on paper, so the child should take a photo of their paper.
  bool get isNotPaperDrawing => this != nearlyEmpty;
}

/// Returns a reason when the drawing is too empty to play with.
DrawingRejectReason? rejectReasonFor(DrawingFeatures f) {
  if (f.inkCoverage < kMinInkCoverage || f.bboxCoverage < kMinBboxCoverage) {
    return DrawingRejectReason.nearlyEmpty;
  }
  return null;
}

double _round1(double v) => (v.clamp(0, 100) * 10).round() / 10;
