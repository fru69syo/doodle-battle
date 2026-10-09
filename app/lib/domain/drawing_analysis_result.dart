import 'dart:typed_data';

import 'element_type.dart';
import 'stats.dart';

/// Output of the on-device drawing analysis pipeline (see docs/SPEC.md §3).
///
/// This is the contract between the Vision team (producer) and the rest of the
/// app (consumers). `features` is an opaque, JSON-serialisable map so the
/// Vision team can evolve the feature set without breaking consumers; the
/// server re-validates stats from it.
class DrawingAnalysisResult {
  const DrawingAnalysisResult({
    required this.cutoutPng,
    required this.imageHash,
    required this.features,
    required this.energy,
    required this.skill,
    required this.element,
    required this.baseStats,
  });

  /// Cut-out drawing with transparent background, longest side <= 512px.
  final Uint8List cutoutPng;

  /// SHA-256 (hex) of the normalised input image; used as deterministic seed.
  final String imageHash;

  /// Extracted features (inkCoverage, colorCount, symmetry, ...).
  final Map<String, num> features;

  /// のびのび度 0-100.
  final double energy;

  /// じょうずさ 0-100. Higher means weaker.
  final double skill;

  final ElementType element;

  /// Level-1 stats.
  final Stats baseStats;

  /// しょぼキャラ: skill above 75 (SPEC §3.2).
  bool get isShobo => skill > 75;
}
