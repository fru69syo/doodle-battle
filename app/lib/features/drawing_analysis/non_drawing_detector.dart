/// "Is this a photo of a hand drawing on paper?" (SPEC §11.1, docs/TRUST.md).
///
/// AI-generated pictures, digital illustrations, photographs, printed
/// pictures and photos of screens are *not accepted* (rather than being
/// turned into weak characters). Wrongly rejecting a real child's drawing is
/// the worst possible outcome, so every rule is a conjunction of several
/// independent signals and each threshold sits outside the range measured on
/// kids' drawings (docs/TRUST.md §3 has the calibration). When in doubt the
/// picture is accepted; a polished picture that slips through still becomes
/// an internally weak character (skill scoring is unchanged).
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
    required this.symmetry,
    required this.gradientShare,
    required this.fineLineRatio,
    required this.edgeCoherence,
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
    symmetry: f.symmetry,
    gradientShare: f.gradientShare,
    fineLineRatio: f.fineLineRatio,
    edgeCoherence: f.edgeCoherence,
    backgroundShare: m.backgroundShare,
    backgroundFlatness: m.backgroundFlatness,
    noiseLevel: m.noiseLevel,
    exactFlatShare: m.exactFlatShare,
    lumaPeriodicity: m.lumaPeriodicity,
    chromaPeriodicity: m.chromaPeriodicity,
    periodicPatches: m.periodicPatches,
    patchCount: m.patchCount,
  );

  /// Bright, neutral, flat background dominates (0..1). Unreliable on its
  /// own: tinted paper and dim rooms give ≈0 for real drawings.
  final double paperLikeness;

  /// A paper sheet was found and perspective-corrected.
  final bool paperDetected;

  /// Photo evidence from the features (0..1).
  final double photoLikelihood;

  /// Digital-illustration "finish" (0..1), see [digitalPolish].
  final double polish;

  /// Copied from [DrawingFeatures] (see docs/VISION.md §3).
  final double symmetry;
  final double gradientShare;
  final double fineLineRatio;
  final double edgeCoherence;

  /// Share of the image that is background (not the drawing), and how flat
  /// that background is.
  final double backgroundShare;
  final double backgroundFlatness;

  /// Camera/paper noise σ (8-bit levels) on native-resolution patches;
  /// -1 = could not be measured.
  final double noiseLevel;

  /// Share of pixels in exactly uniform 3×3 neighbourhoods (digital flat
  /// fills); -1 = could not be measured.
  final double exactFlatShare;

  /// 2D lattice strength in luminance / colour difference.
  final double lumaPeriodicity;
  final double chromaPeriodicity;

  /// Drawing patches with a lattice, and how many were examined.
  final int periodicPatches;
  final int patchCount;

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

/// Print/screen: a 2D lattice at least this strong in at least
/// [kMinPeriodicPatches] drawing patches.
const double kPeriodicAbove = 10;
const int kMinPeriodicPatches = 2;

/// Chroma lattices this much stronger than luma ones point to a screen's
/// RGB sub-pixels rather than printed dots (diagnostic only).
const double kScreenChromaRatio = 1.25;

/// Digital "sticker" (AI mascot, shaded line art): polished, mirror
/// symmetric, with exactly flat digital fills and little camera noise.
const double kStickerPolish = 0.55;
const double kStickerSymmetry = 0.9;
const double kDigitalExactFlat = 0.05;
const double kDigitalMaxNoise = 1.2;

/// Full-frame digital painting: no paper, smooth gradients, exactly flat
/// areas and almost no noise.
const double kPaintingMaxPaper = 0.4;
const double kPaintingMaxBackground = 0.5;
const double kPaintingExactFlat = 0.15;
const double kPaintingGradient = 0.4;
const double kPaintingMaxNoise = 0.6;

/// Photograph: photo-like, no paper, no line work at all, clean (non-crayon)
/// edges and smooth gradients.
const double kPhotoLikelihoodAbove = 0.62;
const double kPhotoMaxPaper = 0.05;
const double kPhotoMaxFineLines = 0.2;
const double kPhotoMinCoherence = 0.8;
const double kPhotoMinGradient = 0.3;

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
  // 1. Printed picture / photographed screen: a dot or pixel lattice that
  //    repeats across the drawing.
  final lattice =
      s.lumaPeriodicity >= kPeriodicAbove ||
      s.chromaPeriodicity >= kPeriodicAbove;
  if (lattice && s.periodicPatches >= kMinPeriodicPatches) {
    return s.chromaPeriodicity >= kScreenChromaRatio * s.lumaPeriodicity
        ? DrawingRejectReason.screen
        : DrawingRejectReason.printed;
  }
  final digitalPixels =
      s.exactFlatShare >= kDigitalExactFlat && s.noiseLevel < kDigitalMaxNoise;
  // 2a. Digital / AI "sticker" illustration.
  if (digitalPixels &&
      s.polish >= kStickerPolish &&
      s.symmetry >= kStickerSymmetry) {
    return DrawingRejectReason.digital;
  }
  // 2b. Full-frame digital / AI painting.
  if (s.paperLikeness <= kPaintingMaxPaper &&
      s.backgroundShare <= kPaintingMaxBackground &&
      s.exactFlatShare >= kPaintingExactFlat &&
      s.noiseLevel < kPaintingMaxNoise &&
      s.gradientShare >= kPaintingGradient) {
    return DrawingRejectReason.digital;
  }
  // 3. A photograph of the world rather than of a sheet with a drawing.
  if (s.photoLikelihood >= kPhotoLikelihoodAbove &&
      s.paperLikeness <= kPhotoMaxPaper &&
      s.fineLineRatio < kPhotoMaxFineLines &&
      s.edgeCoherence >= kPhotoMinCoherence &&
      s.gradientShare >= kPhotoMinGradient) {
    return DrawingRejectReason.photo;
  }
  return null;
}
