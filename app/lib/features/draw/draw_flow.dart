import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';
import '../../data/before_photo.dart';
import '../../domain/drawing_analysis_result.dart';
import '../birth/pending_birth.dart';
import '../drawing_analysis/drawing_analyzer.dart'
    show UndecodableImageException, applyCloudSkill;

sealed class DrawOutcome {
  const DrawOutcome();
}

class DrawReady extends DrawOutcome {
  const DrawReady(this.birth);
  final PendingBirth birth;
}

/// The drawing is too empty (「もうすこし かいてみよう」).
class DrawTooEmpty extends DrawOutcome {
  const DrawTooEmpty(this.message);
  final String message;
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
    final AnalysisOutcomeLike outcome;
    final Future<BeforePhoto?>? beforePhoto;
    try {
      final o = await _ref.read(drawingAnalyzerProvider).analyze(imageBytes);
      outcome = (o.result, o.rejectReason?.message);
      beforePhoto = o.beforePhoto;
    } on UndecodableImageException {
      return const DrawUnreadable();
    }
    final (result, reject) = outcome;
    if (reject != null) return DrawTooEmpty(reject);
    final cloud = await _judge(result);
    return DrawReady(
      PendingBirth(
        result: cloud == null
            ? result
            : applyCloudSkill(result, cloud.skillEstimate.toDouble()),
        cloud: cloud,
        beforePhoto: beforePhoto,
      ),
    );
  }

  /// Cloud judgement, or null when not allowed / unavailable / failed /
  /// inappropriate (the local result is used silently).
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
      return judgement.appropriate ? judgement : null;
    } on Object {
      return null;
    }
  }
}

typedef AnalysisOutcomeLike = (DrawingAnalysisResult, String?);

final drawFlowProvider = Provider<DrawFlow>(DrawFlow.new);
