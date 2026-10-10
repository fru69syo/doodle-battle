import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';
import '../../domain/drawing_analysis_result.dart';
import '../birth/pending_birth.dart';
import 'drawing_services.dart';
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
    if (judged != null && judged.rejectCode != null) {
      return const DrawRetake(kPaperDrawingMessage, notPaperDrawing: true);
    }
    final cloud = judged != null && judged.appropriate ? judged : null;
    return DrawReady(
      PendingBirth(
        result: cloud == null
            ? result
            : applyCloudSkill(result, cloud.skillEstimate.toDouble()),
        cloud: cloud,
      ),
    );
  }

  /// Cloud judgement, or null when not allowed / unavailable / failed (the
  /// local result is used silently). An inappropriate judgement is returned
  /// so that a "not hand-drawn" verdict ([CloudJudgement.rejectCode]) can
  /// ask for a new photo; otherwise it is ignored.
  Future<CloudJudgement?> _judge(DrawingAnalysisResult result) async {
    final settings = await _ref.read(settingsProvider.future);
    final backend = _ref.read(backendApiProvider);
    if (!settings.consents.cloudJudge || !backend.isAvailable) return null;
    if (result.cutoutPng.length > _maxCloudPngBytes) return null;
    try {
      await _ref.read(settingsProvider.notifier).ensureConsentSynced();
      final judgement = await backend
          .judgeDrawing(result.cutoutPng)
          .timeout(cloudJudgeTimeout);
      return judgement;
    } on Object {
      return null;
    }
  }
}

final drawFlowProvider = Provider<DrawFlow>(DrawFlow.new);
