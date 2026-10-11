/// v2.0 admission of an analysed picture (docs/GAME_DESIGN_V2.md §1, §4.4).
///
/// v1 refused digital / AI / printed / screen pictures. v2 accepts them as
/// characters whose *trust verdict* makes them the hidden late bloomer
/// (internal; never shown). Still refused: nearly empty drawings, photos
/// (a real person can not be told apart on device), and a cloud
/// `photo_print_or_screen` verdict (it can not tell a photo from a print, so
/// the safe reading wins). Pictures drawn with the in-app canvas are never
/// judged "digital" (flat fills are expected there).
library;

import '../../domain/character_v2.dart';
import 'drawing_analyzer.dart';

/// Outcome: either a reject reason for the child, or the (possibly null)
/// trust verdict stored with the character.
class V2Admission {
  const V2Admission.reject(DrawingRejectReason this.reject) : verdict = null;
  const V2Admission.accept(this.verdict) : reject = null;

  final DrawingRejectReason? reject;

  /// INTERNAL trust verdict (`digital` / `printed` / `screen` /
  /// `ai_generated`), or null for an ordinary drawing.
  final String? verdict;

  bool get accepted => reject == null;
}

/// Pure rule. [authenticity] is `classifyAuthenticity(...)` (photo only),
/// [empty] is `rejectReasonFor(features)`, [cloudOrigin] the judge's
/// `origin` when cloud features are allowed.
V2Admission admitV2({
  required DrawingSource source,
  DrawingRejectReason? authenticity,
  DrawingRejectReason? empty,
  String? cloudOrigin,
}) {
  if (empty != null) return V2Admission.reject(empty);
  if (cloudOrigin == 'photo_print_or_screen') {
    return const V2Admission.reject(DrawingRejectReason.photo);
  }
  String? verdict;
  if (source == DrawingSource.photo && authenticity != null) {
    if (authenticity == DrawingRejectReason.photo) {
      return const V2Admission.reject(DrawingRejectReason.photo);
    }
    if (authenticity != DrawingRejectReason.nearlyEmpty) {
      verdict = authenticity.name; // digital / printed / screen
    }
  }
  if (verdict == null &&
      source == DrawingSource.photo &&
      cloudOrigin == 'ai_generated') {
    verdict = 'ai_generated';
  }
  return V2Admission.accept(verdict);
}

/// [admitV2] for an analyser report.
V2Admission admitReportV2(
  DrawingAnalysisReport report, {
  DrawingSource source = DrawingSource.photo,
  String? cloudOrigin,
}) => admitV2(
  source: source,
  authenticity: source == DrawingSource.photo
      ? classifyAuthenticity(report.authenticity)
      : null,
  empty: rejectReasonFor(report.features),
  cloudOrigin: cloudOrigin,
);
