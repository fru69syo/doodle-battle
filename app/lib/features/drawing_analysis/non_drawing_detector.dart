/// "Is this a photo of a hand drawing on paper?" (SPEC §11.1, docs/TRUST.md).
///
/// AI-generated pictures, digital illustrations, photographs, printed
/// pictures and photos of screens are *not accepted* (rather than being
/// turned into weak characters). Wrongly rejecting a real child's drawing is
/// the worst possible outcome, so every rule needs strong evidence and the
/// thresholds sit well outside the range measured on kids' drawings
/// (docs/TRUST.md §3 has the calibration).
library;

import 'drawing_features.dart';
import 'scoring.dart';
import 'src/authenticity.dart';
import 'src/raster.dart';

export 'src/authenticity.dart' show AuthenticityMeasurements;

/// Everything the authenticity decision looks at.
class AuthenticitySignals {
  const AuthenticitySignals({
    required this.paperLikeness,
    required this.paperDetected,
    required this.photoLikelihood,
    required this.polish,
    required this.backgroundShare,
    required this.backgroundFlatness,
    required this.noiseLevel,
    required this.exactFlatShare,
    required this.lumaPeriodicity,
    required this.chromaPeriodicity,
    required this.periodicPatches,
    required this.patchCount,
  });

  factory AuthenticitySignals.from(
    DrawingFeatures f,
    AuthenticityMeasurements m,
  ) => AuthenticitySignals(
    paperLikeness: f.paperLikeness,
    paperDetected: f.paperDetected,
    photoLikelihood: f.photoLikelihood,
    polish: digitalPolish(f),
    backgroundShare: m.backgroundShare,
    backgroundFlatness: m.backgroundFlatness,
    noiseLevel: m.noiseLevel,
    exactFlatShare: m.exactFlatShare,
    lumaPeriodicity: m.lumaPeriodicity,
    chromaPeriodicity: m.chromaPeriodicity,
    periodicPatches: m.periodicPatches,
    patchCount: m.patchCount,
  );

  /// Bright, neutral, flat background dominates (0..1).
  final double paperLikeness;

  /// A paper sheet was found and perspective-corrected.
  final bool paperDetected;

  /// Photo evidence from the features (0..1).
  final double photoLikelihood;

  /// Digital-illustration "finish" of the drawing itself (0..1): smooth
  /// gradients, many distinct colours, perfectly clean edges, mirror
  /// symmetry with shading. See [digitalPolish].
  final double polish;

  /// Share of the image that is background (not the drawing), and how flat
  /// that background is (paper is flat even when tinted or dim).
  final double backgroundShare;
  final double backgroundFlatness;

  /// Camera/paper noise σ (8-bit levels) on native-resolution patches;
  /// -1 = could not be measured.
  final double noiseLevel;

  /// Share of pixels in exactly uniform 3×3 neighbourhoods (digital flat
  /// fills); -1 = could not be measured.
  final double exactFlatShare;

  /// Isolated periodic peak strength in luminance / colour difference.
  final double lumaPeriodicity;
  final double chromaPeriodicity;

  /// Ink patches with a periodic peak, and how many were examined.
  final int periodicPatches;
  final int patchCount;

  /// Noise was measured and is essentially zero (no camera involved).
  bool get noiseless => noiseLevel >= 0 && noiseLevel < kNoiselessBelow;

  Map<String, num> toMap() => {
    'paperLikeness': paperLikeness,
    'paperDetected': paperDetected ? 1 : 0,
    'photoLikelihood': photoLikelihood,
    'polish': polish,
    'backgroundShare': backgroundShare,
    'backgroundFlatness': backgroundFlatness,
    'noiseLevel': noiseLevel,
    'exactFlatShare': exactFlatShare,
    'lumaPeriodicity': lumaPeriodicity,
    'chromaPeriodicity': chromaPeriodicity,
    'periodicPatches': periodicPatches,
    'patchCount': patchCount,
  };
}

// ---- Thresholds (docs/TRUST.md §3) ----------------------------------------

/// Below this paper evidence there is no sheet of paper in the picture.
const double kMinPaperLikeness = 0.12;

/// Photo rule: photo evidence at least this high *and* paper below
/// [kPhotoMaxPaper].
const double kPhotoLikelihoodAbove = 0.62;
const double kPhotoMaxPaper = 0.5;

/// Noise σ below this means the pixels never went through a camera.
const double kNoiselessBelow = 0.35;

/// Digital rule: noiseless *and* polish at least this high.
const double kDigitalPolishAbove = 0.5;

/// Print/screen rule: a periodic peak at least this strong, repeated in at
/// least [kMinPeriodicPatches] ink patches (or in every patch when fewer
/// were examined).
const double kPeriodicAbove = 12;
const int kMinPeriodicPatches = 2;

/// Chroma peaks this much stronger than luma peaks point to a screen's RGB
/// sub-pixels rather than printed dots.
const double kScreenChromaRatio = 1.25;

/// "Finish" of a digital illustration (0..1).
///
/// Kids' paper drawings sit near 0 on every term: crayon and pencil fills
/// are grainy, outlines wobble and colours are few and flat.
double digitalPolish(DrawingFeatures f) {
  final gradient = ramp(f.gradientShare, 0.12, 0.35);
  final colours = ramp(f.uniqueColors.toDouble(), 150, 450);
  final clean = ramp(f.strokeSmoothness, 0.55, 0.85);
  final symShade =
      ramp(f.symmetry, 0.75, 0.92) * ramp(f.shadingLevel, 0.3, 0.6);
  return clamp01(0.3 * gradient + 0.2 * colours + 0.3 * clean + 0.2 * symShade);
}

/// The reason to refuse the picture, or null when it looks like a photo of
/// a drawing on paper (or when the evidence is not strong enough).
DrawingRejectReason? classifyAuthenticity(AuthenticitySignals s) {
  // 1. Printed picture / photographed screen: periodic dot or pixel grid.
  final periodic =
      s.lumaPeriodicity >= kPeriodicAbove ||
      s.chromaPeriodicity >= kPeriodicAbove;
  final repeated =
      s.periodicPatches >=
      (s.patchCount < kMinPeriodicPatches ? s.patchCount : kMinPeriodicPatches);
  if (periodic && repeated && s.patchCount > 0) {
    return s.chromaPeriodicity >= kScreenChromaRatio * s.lumaPeriodicity
        ? DrawingRejectReason.screen
        : DrawingRejectReason.printed;
  }
  // 2. Digital illustration / AI-generated: no camera noise and a polished,
  //    gradient-shaded, many-coloured finish.
  if (s.noiseless && s.polish >= kDigitalPolishAbove) {
    return DrawingRejectReason.digital;
  }
  // 3. A photograph of the world rather than of a sheet of paper.
  if (s.photoLikelihood >= kPhotoLikelihoodAbove &&
      s.paperLikeness < kPhotoMaxPaper) {
    return DrawingRejectReason.photo;
  }
  // 4. No paper at all.
  if (s.paperLikeness < kMinPaperLikeness) return DrawingRejectReason.noPaper;
  return null;
}
