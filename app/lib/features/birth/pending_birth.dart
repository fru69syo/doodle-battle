import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backend/backend_models.dart';
import '../../data/before_photo.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../../domain/drawing_analysis_result.dart';

/// A freshly analysed drawing waiting to be named (draw → たんじょう → なまえ).
class PendingBirth {
  const PendingBirth({
    required this.result,
    this.cloud,
    this.beforePhoto,
    this.strokesJson,
    this.verdict,
  });

  /// Drawn with the in-app tool (canvas) or photographed on paper.
  DrawingSource get source =>
      strokesJson != null ? DrawingSource.canvas : DrawingSource.photo;

  /// INTERNAL trust verdict (photo pictures only); never shown.
  final String? verdict;

  /// The character this birth makes. [skipMoveSlots]: AI move proposals
  /// the child reported (those slots use the offline move).
  CharacterV2 character({
    String id = 'new',
    String name = '',
    String imagePath = '',
    DateTime? createdAt,
    Set<int> skipMoveSlots = const {},
    bool Function(String)? ngCheck,
  }) {
    final moves = cloud?.moves;
    return newCharacterV2(
      id: id,
      name: name,
      imagePath: imagePath,
      // The seed: SHA-256 of the stored / uploaded cut-out (TRUST §8.1).
      imageHash: cutoutHash(result.cutoutPng),
      rawFeatures: result.features,
      energy: result.energy,
      skill: result.skill,
      createdAt: createdAt ?? DateTime.utc(2026),
      source: source,
      verdict: verdict,
      cloudMoves: moves == null
          ? null
          : [
              for (var i = 0; i < moves.length; i++)
                skipMoveSlots.contains(i) ? null : moves[i],
            ],
      subject: cloud?.subject,
      legacyElement: result.element,
      ngCheck: ngCheck,
    );
  }

  /// Final analysis (skill already blended with the cloud estimate).
  final DrawingAnalysisResult result;

  /// Cloud judgement (only kept when the drawing was judged appropriate).
  final CloudJudgement? cloud;

  /// Paper photo for the Before/After video (docs/VIDEO.md); completes
  /// with null when none was kept. Never throws.
  final Future<BeforePhoto?>? beforePhoto;

  /// Drawn with the in-app tool: the stroke list mapped to the cut-out
  /// (`strokesRecordJson`), kept on the phone for the auto-rigger. Null for
  /// a photographed paper drawing.
  final String? strokesJson;
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
