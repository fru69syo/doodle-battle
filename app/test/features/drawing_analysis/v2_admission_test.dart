import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:doodle_battle/features/drawing_analysis/v2_admission.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const photo = DrawingSource.photo;
  test('ordinary drawings are accepted without a verdict', () {
    final a = admitV2(source: photo);
    expect(a.accepted, isTrue);
    expect(a.verdict, isNull);
  });

  test('digital / printed / screen become hidden verdicts, not rejects', () {
    for (final r in [
      DrawingRejectReason.digital,
      DrawingRejectReason.printed,
      DrawingRejectReason.screen,
    ]) {
      final a = admitV2(source: photo, authenticity: r);
      expect(a.accepted, isTrue);
      expect(a.verdict, r.name);
      expect(kTrustVerdicts, contains(a.verdict));
    }
    expect(
      admitV2(source: photo, cloudOrigin: 'ai_generated').verdict,
      'ai_generated',
    );
  });

  test('photos, empty pictures and cloud photo/print/screen are refused', () {
    expect(
      admitV2(source: photo, authenticity: DrawingRejectReason.photo).reject,
      DrawingRejectReason.photo,
    );
    expect(
      admitV2(source: photo, empty: DrawingRejectReason.nearlyEmpty).reject,
      DrawingRejectReason.nearlyEmpty,
    );
    expect(
      admitV2(source: photo, cloudOrigin: 'photo_print_or_screen').accepted,
      isFalse,
    );
  });

  test('the in-app canvas is never judged digital', () {
    final a = admitV2(
      source: DrawingSource.canvas,
      authenticity: DrawingRejectReason.digital,
      cloudOrigin: 'ai_generated',
    );
    expect(a.accepted, isTrue);
    expect(a.verdict, isNull);
  });
}
