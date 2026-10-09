/// Features extracted from a drawing (SPEC §3.1-4).
///
/// All ratios are in 0..1 unless noted. Pixel measures refer to the
/// normalised paper image whose longest side is 512 px. The map form
/// ([toMap]) is what gets persisted in `Character.features` and sent to the
/// server, so keys are a stable contract (see docs/VISION.md).
class DrawingFeatures {
  const DrawingFeatures({
    required this.inkCoverage,
    required this.silhouetteCoverage,
    required this.bboxCoverage,
    required this.colorCount,
    required this.achromaticCount,
    required this.dominantHue,
    required this.dominantHueShare,
    required this.balancedHueCount,
    required this.chromaticShare,
    required this.redShare,
    required this.darkness,
    required this.strokeSmoothness,
    required this.edgeCoherence,
    required this.contourRoughness,
    required this.wobble,
    required this.symmetry,
    required this.shadingLevel,
    required this.gradientShare,
    required this.detailDensity,
    required this.coherentEdgeDensity,
    required this.fineLineRatio,
    required this.spikiness,
    required this.convexityDefects,
    required this.roundness,
    required this.solidity,
    required this.aspectRatio,
    required this.elongation,
    required this.lineThickness,
    required this.uniqueColors,
    required this.huePeakedness,
    required this.paperLikeness,
    required this.photoLikelihood,
    required this.paperDetected,
  });

  /// Share of paper pixels that carry ink.
  final double inkCoverage;

  /// Share of paper covered by the filled character shape.
  final double silhouetteCoverage;

  /// Share of paper covered by the character's bounding box ("size").
  final double bboxCoverage;

  /// Number of significant chromatic hue clusters.
  final int colorCount;

  /// Number of significant achromatic classes (black, grey): 0..2.
  final int achromaticCount;

  /// Hue (degrees 0..360) of the largest chromatic cluster, -1 if none.
  final double dominantHue;

  /// Share of chromatic ink in the dominant hue cluster.
  final double dominantHueShare;

  /// Hue clusters holding at least 12% of the chromatic ink each.
  final int balancedHueCount;

  /// Share of ink that is chromatic (not black/grey).
  final double chromaticShare;

  /// Share of ink that is red (hue within ±20° of 0).
  final double redShare;

  /// Mean darkness (1 - V) of ink.
  final double darkness;

  /// 1 = perfectly smooth contours, 0 = very jittery.
  final double strokeSmoothness;

  /// Mean structure-tensor coherence on edges (clean lines → ~1).
  final double edgeCoherence;

  /// Mean outline jitter in pixels (hand tremor, crayon edges).
  final double contourRoughness;

  /// Curvature inflections per 100 px of outline (shaky hand → high).
  final double wobble;

  /// Left-right mirror IoU of the shape and strokes.
  final double symmetry;

  /// Tonal gradation inside colour areas (gradients / shading).
  final double shadingLevel;

  /// Share of smooth-interior ink pixels that lie on gentle gradients.
  final double gradientShare;

  /// Edge density and number of small parts inside the character.
  final double detailDensity;

  /// Coherent edge pixels per silhouette pixel.
  final double coherentEdgeDensity;

  /// Length of thin (<= ~3 px) dark lines divided by the character size
  /// (sqrt of its bounding box area).
  final double fineLineRatio;

  /// 1 - (hull perimeter / contour perimeter) of the main shape.
  final double spikiness;

  /// Number of deep concavities of the main shape.
  final int convexityDefects;

  /// Circularity 4πA/P² of the main shape.
  final double roundness;

  /// Area / convex hull area of the main shape ("blockiness").
  final double solidity;

  /// Bounding box width / height.
  final double aspectRatio;

  /// Principal axis ratio (>= 1). 1 = compact, larger = long and thin.
  final double elongation;

  /// Median stroke width in pixels (on the 512 px image).
  final double lineThickness;

  /// Number of distinct 4-bit-per-channel colours in the ink.
  final int uniqueColors;

  /// Share of colour within ±15° of a hue-cluster peak (crayons → ~1,
  /// photos with continuous hues → lower).
  final double huePeakedness;

  /// Evidence of a flat, bright, neutral paper background.
  final double paperLikeness;

  /// 0..1 how much the image looks like a photograph / digital art.
  final double photoLikelihood;

  /// Whether a sheet of paper was found and perspective-corrected.
  final bool paperDetected;

  Map<String, num> toMap() => {
        'inkCoverage': inkCoverage,
        'silhouetteCoverage': silhouetteCoverage,
        'bboxCoverage': bboxCoverage,
        'colorCount': colorCount,
        'achromaticCount': achromaticCount,
        'dominantHue': dominantHue,
        'dominantHueShare': dominantHueShare,
        'balancedHueCount': balancedHueCount,
        'chromaticShare': chromaticShare,
        'redShare': redShare,
        'darkness': darkness,
        'strokeSmoothness': strokeSmoothness,
        'edgeCoherence': edgeCoherence,
        'contourRoughness': contourRoughness,
        'wobble': wobble,
        'symmetry': symmetry,
        'shadingLevel': shadingLevel,
        'gradientShare': gradientShare,
        'detailDensity': detailDensity,
        'coherentEdgeDensity': coherentEdgeDensity,
        'fineLineRatio': fineLineRatio,
        'spikiness': spikiness,
        'convexityDefects': convexityDefects,
        'roundness': roundness,
        'solidity': solidity,
        'aspectRatio': aspectRatio,
        'elongation': elongation,
        'lineThickness': lineThickness,
        'uniqueColors': uniqueColors,
        'huePeakedness': huePeakedness,
        'paperLikeness': paperLikeness,
        'photoLikelihood': photoLikelihood,
        'paperDetected': paperDetected ? 1 : 0,
      };

  /// Inverse of [toMap]; missing keys default to neutral values so older
  /// persisted characters stay loadable.
  factory DrawingFeatures.fromMap(Map<String, num> m) {
    double d(String k, [double def = 0]) => (m[k] ?? def).toDouble();
    int i(String k, [int def = 0]) => (m[k] ?? def).round();
    return DrawingFeatures(
      inkCoverage: d('inkCoverage'),
      silhouetteCoverage: d('silhouetteCoverage'),
      bboxCoverage: d('bboxCoverage'),
      colorCount: i('colorCount'),
      achromaticCount: i('achromaticCount'),
      dominantHue: d('dominantHue', -1),
      dominantHueShare: d('dominantHueShare'),
      balancedHueCount: i('balancedHueCount'),
      chromaticShare: d('chromaticShare'),
      redShare: d('redShare'),
      darkness: d('darkness'),
      strokeSmoothness: d('strokeSmoothness'),
      edgeCoherence: d('edgeCoherence'),
      contourRoughness: d('contourRoughness'),
      wobble: d('wobble'),
      symmetry: d('symmetry'),
      shadingLevel: d('shadingLevel'),
      gradientShare: d('gradientShare'),
      detailDensity: d('detailDensity'),
      coherentEdgeDensity: d('coherentEdgeDensity'),
      fineLineRatio: d('fineLineRatio'),
      spikiness: d('spikiness'),
      convexityDefects: i('convexityDefects'),
      roundness: d('roundness'),
      solidity: d('solidity', 1),
      aspectRatio: d('aspectRatio', 1),
      elongation: d('elongation', 1),
      lineThickness: d('lineThickness'),
      uniqueColors: i('uniqueColors'),
      huePeakedness: d('huePeakedness', 1),
      paperLikeness: d('paperLikeness', 1),
      photoLikelihood: d('photoLikelihood'),
      paperDetected: i('paperDetected') == 1,
    );
  }

  @override
  String toString() => 'DrawingFeatures(${toMap()})';
}
