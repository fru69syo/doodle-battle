import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backend/backend_models.dart';
import '../../data/before_photo.dart';
import '../../domain/drawing_analysis_result.dart';

/// A freshly analysed drawing waiting to be named (draw → たんじょう → なまえ).
class PendingBirth {
  const PendingBirth({required this.result, this.cloud, this.beforePhoto});

  /// Final analysis (skill already blended with the cloud estimate).
  final DrawingAnalysisResult result;

  /// Cloud judgement (only kept when the drawing was judged appropriate).
  final CloudJudgement? cloud;

  /// Paper photo for the Before/After video (docs/VIDEO.md); completes
  /// with null when none was kept. Never throws.
  final Future<BeforePhoto?>? beforePhoto;
}

class PendingBirthController extends Notifier<PendingBirth?> {
  @override
  PendingBirth? build() => null;

  void set(PendingBirth birth) => state = birth;
  void clear() => state = null;
}

final pendingBirthProvider =
    NotifierProvider<PendingBirthController, PendingBirth?>(
      PendingBirthController.new,
    );
