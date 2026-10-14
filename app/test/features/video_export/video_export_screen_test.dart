import 'dart:io';
import 'dart:typed_data';

import 'package:doodle_battle/core/router/app_router.dart';
import 'package:doodle_battle/core/router/routes.dart';
import 'package:doodle_battle/core/widgets/character_picture.dart';
import 'package:doodle_battle/data/before_photo.dart';
import 'package:doodle_battle/features/battle_ui/battle_outcome.dart';
import 'package:doodle_battle/features/draw/drawing_services.dart';
import 'package:doodle_battle/features/video_export/video_encoder.dart';
import 'package:doodle_battle/features/video_export/video_export_providers.dart';
import 'package:doodle_battle/features/video_export/video_export_screen.dart';
import 'package:doodle_battle/features/video_export/video_exporter.dart';
import 'package:doodle_battle/features/video_export/video_sharer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';
import 'video_encoder_test.dart' show FakeEncoder, FakeFrames;
import 'video_fixtures.dart';

class FakeSharer implements VideoSharer {
  final saved = <String>[];
  final shared = <String>[];

  @override
  Future<VideoSaveResult> saveToGallery(String path) async {
    saved.add(path);
    return VideoSaveResult.saved;
  }

  @override
  Future<bool> share(String path) async {
    shared.add(path);
    return true;
  }
}

/// Analyzer fake that also hands over a paper photo, like the real one.
class _AnalyzerWithPhoto extends FakeAnalyzer {
  _AnalyzerWithPhoto(this.photo);
  final BeforePhoto photo;

  @override
  Future<AnalysisOutcome> analyze(Uint8List imageBytes) async {
    calls++;
    return AnalysisOutcome(result, beforePhoto: Future.value(photo));
  }
}

class _Video {
  final encoder = FakeEncoder();
  final sharer = FakeSharer();
  late final Directory dir = Directory.systemTemp.createTempSync('video_x');

  Widget wrap(Widget app) => ProviderScope(
    overrides: [
      videoExporterProvider.overrideWithValue(
        VideoExporter(encoder, frames: (c, w, h) => FakeFrames(w, h, 6)),
      ),
      videoSharerProvider.overrideWithValue(sharer),
      videoExportDirProvider.overrideWithValue(() async => dir),
      videoAssetLoaderProvider.overrideWithValue(readAssetFile),
      videoPreviewAutoplayProvider.overrideWithValue(false),
    ],
    child: app,
  );
}

/// Lets real async work (image decoding, file IO) finish.
Future<void> settleAsync(WidgetTester tester, Finder until) async {
  for (var i = 0; i < 50 && until.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(until, findsWidgets);
}

Future<void> openFromDetail(WidgetTester tester, TestApp app) async {
  app.container.read(routerProvider).go(Routes.character('c_1'));
  await tester.pumpAndSettle();
  final open = find.byKey(const Key('video-open'));
  await tester.scrollUntilVisible(
    open,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(open);
  // The preview spinner never settles while loading: pump instead.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await settleAsync(tester, find.byKey(const Key('video-make')));
}

Future<void> makeVideo(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('video-make')));
  await tester.pump();
  await settleAsync(tester, find.byKey(const Key('video-done')));
}

void main() {
  testWidgets('make → gate → privacy notice → save and share', (tester) async {
    final v = _Video();
    final gate = FakeGate();
    final app = await pumpApp(
      tester,
      characters: [testCharacter()],
      gate: gate,
      wrap: v.wrap,
    );
    await openFromDetail(tester, app);
    expect(find.byKey(const Key('video-preview')), findsOneWidget);
    // Nothing can be saved or shared before a parent unlocks it.
    expect(find.byKey(const Key('video-save')), findsNothing);
    expect(find.byKey(const Key('video-share')), findsNothing);

    await makeVideo(tester);
    expect(v.encoder.starts.single.path, startsWith(v.dir.path));
    expect(v.encoder.starts.single.path, endsWith('.mp4'));
    expect(v.encoder.starts.single.path, isNot(contains('ねこまる')));
    expect(v.encoder.finished, isTrue);
    expect(find.byKey(const Key('video-save')), findsNothing);
    expect(gate.calls, 0);

    await tapVisible(tester, find.byKey(const Key('video-parent')));
    expect(gate.calls, 1);
    expect(find.byKey(const Key('video-notice')), findsOneWidget);
    expect(find.text('えに なまえや がっこうめいが かいていないか かくにんしてね'), findsOneWidget);
    expect(find.textContaining('顔や声'), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-notice-ok')));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byKey(const Key('video-save')));
    expect(v.sharer.saved, [v.encoder.starts.single.path]);
    await tester.tap(find.byKey(const Key('kid-message-ok')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('video-share')));
    expect(v.sharer.shared, [v.encoder.starts.single.path]);
    // The gate is asked once per screen.
    expect(gate.calls, 1);
    await unmount(tester);
  });

  testWidgets('a refused gate shows no notice and no save/share', (
    tester,
  ) async {
    final v = _Video();
    final gate = FakeGate(pass: false);
    final app = await pumpApp(
      tester,
      characters: [testCharacter()],
      gate: gate,
      wrap: v.wrap,
    );
    await openFromDetail(tester, app);
    await makeVideo(tester);
    await tapVisible(tester, find.byKey(const Key('video-parent')));
    expect(gate.calls, 1);
    expect(find.byKey(const Key('video-notice')), findsNothing);
    expect(find.byKey(const Key('video-save')), findsNothing);
    expect(find.byKey(const Key('video-share')), findsNothing);
    expect(v.sharer.saved, isEmpty);
    await unmount(tester);
  });

  testWidgets('cancelling the privacy notice keeps sharing locked', (
    tester,
  ) async {
    final v = _Video();
    final app = await pumpApp(
      tester,
      characters: [testCharacter()],
      wrap: v.wrap,
    );
    await openFromDetail(tester, app);
    await makeVideo(tester);
    await tapVisible(tester, find.byKey(const Key('video-parent')));
    await tester.tap(find.byKey(const Key('video-notice-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('video-save')), findsNothing);
    expect(find.byKey(const Key('video-parent')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('encoder failure shows a gentle message', (tester) async {
    final v = _Video();
    final failing = FakeEncoder(rejectSizes: {(720, 1280), (576, 1024)});
    final app = await pumpApp(
      tester,
      characters: [testCharacter()],
      wrap: (a) => ProviderScope(
        overrides: [
          videoExporterProvider.overrideWithValue(
            VideoExporter(failing, frames: (c, w, h) => FakeFrames(w, h, 3)),
          ),
          videoExportDirProvider.overrideWithValue(() async => v.dir),
          videoAssetLoaderProvider.overrideWithValue(readAssetFile),
          videoPreviewAutoplayProvider.overrideWithValue(false),
        ],
        child: a,
      ),
    );
    await openFromDetail(tester, app);
    await tester.tap(find.byKey(const Key('video-make')));
    await tester.pump();
    await settleAsync(tester, find.byKey(const Key('video-error')));
    expect(find.text('この きかいでは どうがを つくれないみたい…'), findsOneWidget);
    expect(failing.starts.length, 2);
    await unmount(tester);
  });

  testWidgets('birth: the paper photo is kept and the detail page offers the '
      'video', (tester) async {
    final v = _Video();
    final photo = BeforePhoto(
      jpeg: Uint8List.fromList([0xff, 0xd8, 0xff]),
      inkRect: const NormRect(0.2, 0.2, 0.5, 0.4),
    );
    final app = await pumpApp(
      tester,
      analyzer: _AnalyzerWithPhoto(photo),
      wrap: v.wrap,
    );
    // Children capture with the camera only (SPEC §11.1): guide → shoot.
    await tapVisible(tester, find.byKey(const Key('home-draw')));
    await tapVisible(tester, find.byKey(const Key('draw-camera')));
    await tapVisible(tester, find.byKey(const Key('guide-shoot')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('birth-name')));
    await tester.enterText(find.byKey(const Key('name-field')), 'ほのおまる');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('name-save')));
    final id = (await app.characters.loadAll()).single.id;
    final kept = await app.characters.readBeforePhoto(id);
    expect(kept?.jpeg, photo.jpeg);
    expect(kept?.inkRect, photo.inkRect);
    expect(find.byKey(const Key('video-open-card')), findsOneWidget);
    // The prompt sits below the drawing and never covers it.
    final picture = tester.getRect(find.byType(CharacterPicture).first);
    final prompt = tester.getRect(find.byKey(const Key('video-open-card')));
    expect(prompt.top, greaterThanOrEqualTo(picture.bottom));
    await tester.scrollUntilVisible(
      find.byKey(const Key('video-open')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('video-open')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('battle result offers the video', (tester) async {
    final v = _Video();
    final app = await pumpApp(
      tester,
      characters: [testCharacter()],
      wrap: v.wrap,
    );
    app.container
        .read(routerProvider)
        .go(
          Routes.battleResult,
          extra: const BattleOutcome(
            characterId: 'c_1',
            won: true,
            xpGained: 10,
            levelBefore: 1,
            levelAfter: 1,
            stage: 1,
          ),
        );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('video-open')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('video-open')), findsOneWidget);
    expect(find.byKey(const Key('video-open-card')), findsNothing);
    await unmount(tester);
  });

  test('privacy notice texts', () {
    expect(videoPrivacyNoticeKid, 'えに なまえや がっこうめいが かいていないか かくにんしてね');
    expect(videoPrivacyNoticeParent, contains('名前'));
    expect(videoPrivacyNoticeParent, contains('学校名'));
  });

  test('video file names carry no personal data', () {
    expect(
      videoFileName(DateTime(2026, 10, 10, 9, 5, 7)),
      'oekaki_fighters_20261010_090507.mp4',
    );
    expect(VideoEncoderErrors.sizeUnsupported, 'size_unsupported');
  });
}
