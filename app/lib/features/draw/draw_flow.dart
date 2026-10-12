import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';
import '../../domain/battle_v3/battle_v3.dart' show FeatureVector;
import '../../domain/character_v2.dart';
import '../../domain/drawing_analysis_result.dart';
import '../birth/pending_birth.dart';
import 'drawing_services.dart';
import '../draw_canvas/canvas_analysis.dart';
import '../draw_canvas/stroke_drawing.dart';
import '../draw_canvas/stroke_painter.dart';
import '../drawing_analysis/drawing_analyzer.dart'
    show UndecodableImageException, applyCloudSkill, kPaperDrawingMessage;

sealed class DrawOutcome {
  const DrawOutcome();
}

class DrawReady extends DrawOutcome {
  const DrawReady(this.birth);
  final PendingBirth birth;
}

/// The picture can not become a character; the child is gently asked to
/// take a new photo: the drawing is too empty (「もうすこし かいてみよう」) or
/// it is not a drawing on paper ([notPaperDrawing], 「かみに かいた えを
/// とってね」 — AI / digital / printed / screen / photo, on device or by the
/// cloud judge).
class DrawRetake extends DrawOutcome {
  const DrawRetake(this.message, {this.notPaperDrawing = false});
  final String message;
  final bool notPaperDrawing;
}

/// The file could not be decoded.
class DrawUnreadable extends DrawOutcome {
  const DrawUnreadable();
}

/// Max size the server accepts for judgeDrawing.
const _maxCloudPngBytes = 600 * 1024;
const cloudJudgeTimeout = Duration(seconds: 20);

/// Photo → on-device analysis → (optional) cloud judging (SPEC §3).
class DrawFlow {
  DrawFlow(this._ref);
  final Ref _ref;

  Future<DrawOutcome> process(Uint8List imageBytes) async {
    final AnalysisOutcome outcome;
    try {
      outcome = await _ref.read(drawingAnalyzerProvider).analyze(imageBytes);
    } on UndecodableImageException {
      return const DrawUnreadable();
    }
    final result = outcome.result;
    final reject = outcome.rejectReason;
    if (reject != null) {
      return DrawRetake(
        reject.message,
        notPaperDrawing: reject.isNotPaperDrawing,
      );
    }
    final judged = await _judge(result);
    // v2 judge: only a confident photo / print / screen verdict refuses
    // (an AI picture is accepted; the server makes it weaker, unseen).
    if (judged != null && judged.rejectCode == CloudJudgement.notDrawing) {
      return const DrawRetake(kPaperDrawingMessage, notPaperDrawing: true);
    }
    final cloud = judged != null && judged.appropriate ? judged : null;
    return DrawReady(
      PendingBirth(
        result: cloud == null
            ? result
            : applyCloudSkill(result, cloud.skillEstimate.toDouble()),
        cloud: cloud,
        beforePhoto: outcome.beforePhoto,
        verdict: outcome.verdict,
      ),
    );
  }

  /// A drawing made with the in-app tool (docs/PUPPET.md §4): rendered,
  /// then the same analysis minus the paper / authenticity checks, the same
  /// cloud judgement (a "not hand-drawn" verdict is ignored — it was drawn
  /// with a finger in the app), and the stroke list is kept for rigging.
  Future<DrawOutcome> processCanvas(StrokeDrawing drawing) async {
    final png = await renderDrawingPng(drawing);
    final CanvasAnalysis a;
    try {
      a = await _ref.read(canvasAnalyzerProvider)(png);
    } on UndecodableImageException {
      return const DrawUnreadable();
    }
    final reject = a.rejectReason;
    if (reject != null) return DrawRetake(reject.message);
    final judged = await _judge(a.result);
    final cloud = judged != null && judged.appropriate ? judged : null;
    return DrawReady(
      PendingBirth(
        result: cloud == null
            ? a.result
            : applyCloudSkill(a.result, cloud.skillEstimate.toDouble()),
        cloud: cloud,
        strokesJson: strokesRecordJson(drawing, a.mapping),
      ),
    );
  }

  /// Cloud judgement, or null when not allowed / unavailable / failed /
  /// switched off by the cost mode (the on-device result is used silently,
  /// moves then come from `generateOfflineMoves`). With the `v2` input the
  /// same call proposes AI moves. An inappropriate judgement is returned so
  /// that a "not a drawing" verdict ([CloudJudgement.rejectCode]) can ask
  /// for a new photo; otherwise it is ignored.
  Future<CloudJudgement?> _judge(DrawingAnalysisResult result) async {
    final settings = await _ref.read(settingsProvider.future);
    final backend = _ref.read(backendApiProvider);
    if (!settings.consents.cloudJudge || !backend.isAvailable) return null;
    if (result.cutoutPng.length > _maxCloudPngBytes) return null;
    try {
      // Budget switch (config/costMode): saving / minimal → on device only.
      final mode = await backend.costMode().timeout(cloudJudgeTimeout);
      if (!mode.cloudJudge) return null;
      await _ref.read(settingsProvider.notifier).ensureConsentSynced();
      final judgement = await backend
          .judgeDrawing(
            result.cutoutPng,
            v2: mode.cloudMoveGen ? v2InputOf(result) : null,
          )
          .timeout(cloudJudgeTimeout);
      return judgement;
    } on Object {
      return null;
    }
  }
}

/// The analyser's quantised output for `judgeDrawing` (`v2`).
V2DrawingInput v2InputOf(DrawingAnalysisResult r) => V2DrawingInput(
  features: FeatureVector.quantize(r.features).toJson(),
  energy10: CharacterV2.tenths(r.energy),
  skill10: CharacterV2.tenths(r.skill),
  imageHash: r.imageHash,
);

final drawFlowProvider = Provider<DrawFlow>(DrawFlow.new);

/// Seam over the in-app drawing analysis (tests use a synchronous one).
final canvasAnalyzerProvider =
    Provider<Future<CanvasAnalysis> Function(Uint8List)>(
      (ref) => analyzeCanvasDrawing,
    );
