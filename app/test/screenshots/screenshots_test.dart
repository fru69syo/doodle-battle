// Renders the main screens to PNG for the store / QA (phone portrait,
// 1080×1920 px at 2.625 dpr, real Zen Maru Gothic + Material icons, real CPU
// doodles, real on-device analysis of synthetic kid drawings). The hero
// character comes from a synthetic photo of a kid drawing on paper
// (`00_paper_photo.jpg`), so Before (paper) and After (character) match.
// store/tools/compose_screenshots.py turns a selection into the listing.
//
// Not part of the normal test run (tag `screenshots` is skipped by
// dart_test.yaml). Regenerate with `tool/screenshots.sh`.
@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/before_photo.dart';
import 'package:doodle_battle/data/drawing_loop_storage.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/character.dart';
import 'package:doodle_battle/domain/drawing_analysis_result.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:doodle_battle/features/card_print/card_output.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:doodle_battle/features/drawing_loop/odai/daily_odai.dart';
import 'package:doodle_battle/features/drawing_loop/odai/stamp_card.dart';
import 'package:doodle_battle/features/video_export/before_photo_extractor.dart';
import 'package:doodle_battle/features/video_export/video_export_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/doodle_painter.dart';
import '../features/card_print/card_pdf_test.dart' show testCardFonts;
import '../features/drawing_analysis/synthetic_drawings.dart';
import '../features/video_export/video_fixtures.dart';
import '../support/fakes.dart';
import '../support/harness.dart';

const _physical = Size(1080, 1920);
const _dpr = 2.625; // 411.4 × 731.4 dp
final _outDir =
    Platform.environment['SCREENSHOT_DIR'] ?? '../store/screenshots/raw';
final _boundary = GlobalKey();

late DrawingAnalysisResult _scribble; // the hero: kid drawing photographed
late Uint8List _paperPhoto; // ... on a table (Before)
late BeforePhoto _before;
late DrawingAnalysisResult _blob;
late DrawingAnalysisResult _marker;
late DrawingAnalysisResult _artist; // polished line art (internally weak)

Future<void> _loadFonts() async {
  Future<ByteData> asset(String key) => rootBundle.load(key);
  final zen = FontLoader('ZenMaruGothic')
    ..addFont(asset('assets/fonts/ZenMaruGothic-Regular.ttf'))
    ..addFont(asset('assets/fonts/ZenMaruGothic-Bold.ttf'));
  await zen.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(asset('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

DrawingAnalysisResult _analyse(DoodleCanvas c) =>
    analyzeDrawingSync(c.encodePng()).result;

Character _char(
  String id,
  String name,
  DrawingAnalysisResult r, {
  required int level,
  int xp = 0,
  Map<StatKind, int> seeds = const {},
  String? frame,
  String? elementMove,
  String? specialMove,
  String? subject,
}) => Character(
  id: id,
  name: name,
  imagePath: 'memory://$id.png',
  imageHash: r.imageHash,
  element: r.element,
  baseStats: r.baseStats,
  energy: r.energy,
  skill: r.skill,
  features: r.features,
  createdAt: DateTime(2026, 10, int.parse(id.substring(2))),
  level: level,
  xp: xp,
  seedAllocations: seeds,
  cardFrame: frame,
  elementMoveName: elementMove,
  specialMoveName: specialMove,
  subject: subject,
);

/// The child's collection: levels 12 / 7 / 3 (polished line art) / 1.
List<Character> _collection() => [
  _char(
    'c_1',
    'ぐるぐるドラゴン',
    _scribble,
    level: 12,
    xp: xpToNext(testSpec, 12) - 20,
    seeds: const {StatKind.atk: 5, StatKind.hp: 4},
    frame: 'hoshi',
    elementMove: 'ぐるぐるファイヤー',
    specialMove: 'ドラゴンだいばくはつ',
    subject: 'ドラゴン',
  ),
  _char('c_2', 'ぷにまる', _blob, level: 7, xp: 40, seeds: const {StatKind.spd: 3}),
  _char('c_3', 'ふくろうくん', _artist, level: 3, xp: 30),
  _char('c_4', 'にこにこ', _marker, level: 1),
];

Map<String, Uint8List> _images() => {
  'c_1': _scribble.cutoutPng,
  'c_2': _blob.cutoutPng,
  'c_3': _artist.cutoutPng,
  'c_4': _marker.cutoutPng,
};

const _progress = GameProgress(
  clearedStage: 9,
  displayName: ChosenDisplayName(
    adjectiveId: 'a05',
    nounId: 'n01',
    text: 'げんきな ドラゴン',
  ),
);

AppSettings _settings({
  bool online = true,
  bool ads = true,
  bool purchases = true,
  bool cloud = true,
}) => setupDone.copyWith(
  consents: ParentConsents(
    cloudJudge: cloud,
    online: online,
    ads: ads,
    purchases: purchases,
  ),
  entitlements: {'frame_pack_1'}, // shows the card frame on ぐるぐるドラゴン
);

Future<TestApp> _pump(
  WidgetTester tester, {
  AppSettings? settings,
  List<Character>? characters,
  FakeAnalyzer? analyzer,
  Duration battleStep = const Duration(milliseconds: 900),
  List<Override> overrides = const [],
}) => pumpApp(
  tester,
  settings: settings ?? _settings(),
  progress: _progress,
  characters: characters ?? _collection(),
  images: _images(),
  backend: FakeBackend()..uid = 'a1b2c3d4e5',
  analyzer: analyzer,
  physicalSize: _physical,
  devicePixelRatio: _dpr,
  battleStep: battleStep,
  overrides: overrides,
  wrap: (app) => RepaintBoundary(key: _boundary, child: app),
);

/// Decodes every image on screen for real (fake async would leave them
/// blank), then writes the frame to `<out>/<name>.png`.
Future<void> _shot(
  WidgetTester tester,
  String name, {
  bool settle = true,
}) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Like [testWidgets] but with real elevation shadows (flutter_test paints
/// them as solid black outlines); the flag is restored before the binding's
/// invariant check.
void _shotTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

Future<void> _tap(WidgetTester tester, Finder f) => tapVisible(tester, f);

/// Scrolls [f] to the middle of its scrollable.
Future<void> _centre(
  WidgetTester tester,
  Finder f, {
  double alignment = 0.5,
}) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  Scrollable.ensureVisible(tester.element(f), alignment: alignment);
  await tester.pumpAndSettle();
}

/// Highest unlocked stage where [c]'s element move is super effective.
int _advantageStage(Character c) {
  for (final s in testSpec.cpu.stages.reversed) {
    if (s.stage > _progress.clearedStage + 1) continue;
    final cpu = testRoster[s.cpuId];
    if (testSpec.typeChart.multiplierPct(c.element, cpu.element) >
        testSpec.typeChart.neutralPct) {
      return s.stage;
    }
  }
  return 1;
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    final shot = photographedKidDrawing(seed: 1);
    _paperPhoto = shot.jpeg;
    _scribble = shot.report.result;
    _before = extractBeforePhotoSync(
      shot.jpeg,
      BeforePhotoInput.fromReport(shot.report),
    )!;
    File('$_outDir/00_paper_photo.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_paperPhoto);
    _blob = _analyse(colourBlob(Crayon.sky, seed: 5));
    _marker = _analyse(kidMarker(seed: 4));
    _artist = _analyse(skilledLineArt());
    expect(_artist.isShobo, isTrue, reason: 'line art is internally weak');
    expect(_scribble.isShobo, isFalse);
  });

  _shotTest('01 parent setup / consent', (tester) async {
    await _pump(tester, settings: const AppSettings());
    await _tap(tester, find.byKey(const Key('setup-start')));
    await _tap(tester, find.byKey(const Key('consent-cloudJudge')));
    await _tap(tester, find.byKey(const Key('consent-ads')));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await _shot(tester, '01_setup_consent');
  });

  _shotTest('02 home / 03 draw / 04 capture guide', (tester) async {
    await _pump(tester);
    await _shot(tester, '02_home');
    await _tap(tester, find.byKey(const Key('home-draw')));
    await _shot(tester, '03_draw');
    await _tap(tester, find.byKey(const Key('draw-camera')));
    expect(find.byKey(const Key('capture-guide')), findsOneWidget);
    await _shot(tester, '04_capture_guide');
  });

  _shotTest('05 birth: the paper drawing becomes a character', (tester) async {
    await _pump(
      tester,
      characters: _collection().skip(1).take(2).toList(),
      analyzer: FakeAnalyzer(result: _scribble),
    );
    await _tap(tester, find.byKey(const Key('home-draw')));
    await _tap(tester, find.byKey(const Key('draw-camera')));
    await _tap(tester, find.byKey(const Key('guide-shoot')));
    expect(find.byKey(const Key('birth-traits')), findsOneWidget);
    await _shot(tester, '05_birth_traits');
  });

  _shotTest('06 naming with an NG word', (tester) async {
    await _pump(
      tester,
      characters: _collection().take(2).toList(),
      analyzer: FakeAnalyzer(result: _marker),
    );
    await _tap(tester, find.byKey(const Key('home-draw')));
    await _tap(tester, find.byKey(const Key('draw-camera')));
    await _tap(tester, find.byKey(const Key('guide-shoot')));
    await _tap(tester, find.byKey(const Key('birth-name')));
    await tester.enterText(find.byKey(const Key('name-field')), 'ばか');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('name-problem')), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await _shot(tester, '06_naming_ng');
  });

  _shotTest('07 ずかん / 08 detail', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('home-zukan')));
    await _shot(tester, '07_zukan');
    await _tap(tester, find.byKey(const Key('zukan-card-c_1')));
    await _shot(tester, '08_character_detail');
    await _centre(tester, find.byKey(const Key('detail-ar')), alignment: 0.8);
    await _shot(tester, '08b_character_detail_loop');
  });

  _shotTest('09 stages / 10 battle / 11 result / 12 ad notice', (tester) async {
    final hero = _collection().first;
    final stage = _advantageStage(hero);
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('home-battle')));
    await _tap(tester, find.byKey(const Key('select-c_1')));
    await _centre(
      tester,
      find.byKey(Key('stage-${_progress.clearedStage + 1}')),
      alignment: 0.7,
    );
    await _shot(tester, '09_stage_select');

    await _tap(tester, find.byKey(Key('stage-$stage')));
    // Mid-fight: a tackle first, then the element move until it is
    // 「こうかは ばつぐんだ！」 and its damage number is on screen.
    await tester.tap(find.byKey(const Key('move-tackle')));
    await tester.pumpAndSettle();
    var captured = false;
    for (var turn = 0; turn < 6 && !captured; turn++) {
      await tester.tap(find.byKey(const Key('move-element')));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final banner = find.byKey(const Key('battle-banner'));
        if (banner.evaluate().isNotEmpty) {
          await tester.pump(const Duration(milliseconds: 950)); // damage pops
          await tester.pump(const Duration(milliseconds: 150));
          if (banner.evaluate().isNotEmpty) {
            await _shot(tester, '10_battle', settle: false);
            captured = true;
          }
          break;
        }
      }
      await tester.pumpAndSettle();
      if (find.byKey(const Key('result-title')).evaluate().isNotEmpty) break;
    }
    expect(captured, isTrue, reason: 'no super-effective hit captured');

    await fightUntilResult(tester);
    expect(find.byKey(const Key('result-levelup')), findsOneWidget);
    await _shot(tester, '11_result_levelup');

    await _tap(tester, find.byKey(const Key('ad-double-xp')));
    await _shot(tester, '12_ad_notice');
  });

  _shotTest('13 online lobby / 14 display-name picker', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('home-online')));
    await _shot(tester, '13_online_lobby');
    await _tap(tester, find.byKey(const Key('display-name-change')));
    await _shot(tester, '14_display_name_picker');
  });

  _shotTest('15 おうちのひと / 16 purchase notice', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('home-parent')));
    await _shot(tester, '15_parent_settings');
    await _tap(tester, find.byKey(const Key('buy-no_ads_pass')));
    expect(find.byKey(const Key('purchase-notice')), findsOneWidget);
    await _shot(tester, '16_purchase_notice');
  });

  _shotTest('17 family setup / 18 cover / 19 family battle', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('home-family')));
    await _tap(tester, find.byKey(const Key('family-pick-a')));
    await tester.tap(find.byKey(const Key('family-option-c_1')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('family-pick-b')));
    await tester.tap(find.byKey(const Key('family-option-c_2')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('family-name-a')));
    await tester.tap(find.byKey(const Key('family-label-option-おかあさん')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('family-name-b')));
    await tester.tap(find.byKey(const Key('family-label-option-ぼく')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await _shot(tester, '17_family_setup');
    await _tap(tester, find.byKey(const Key('family-start')));
    expect(find.byKey(const Key('family-cover')), findsOneWidget);
    await _shot(tester, '18_family_cover');
    // One full turn, then the next player's move choice.
    await tester.tap(find.byKey(const Key('family-cover-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-element')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('family-cover-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-tackle')));
    // The turn plays out step by step (battleStep timers), then the next
    // cover appears.
    final cover = find.byKey(const Key('family-cover-continue'));
    for (var i = 0; i < 40 && cover.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.tap(cover);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('move-element')), findsOneWidget);
    await _shot(tester, '19_family_battle');
  });

  _shotTest('20 card print', (tester) async {
    await _pump(
      tester,
      overrides: [
        cardFontsProvider.overrideWithValue(AsyncData(testCardFonts)),
      ],
    );
    await _tap(tester, find.byKey(const Key('home-zukan')));
    await _tap(tester, find.byKey(const Key('zukan-card-c_1')));
    await _tap(tester, find.byKey(const Key('detail-card')));
    expect(find.byKey(const Key('card-preview-0')), findsOneWidget);
    await _shot(tester, '20_card_print');
  });

  _shotTest('21 おだい calendar', (tester) async {
    final store = InMemoryDrawingLoopStorage();
    var card = OdaiStampCard.empty;
    for (final day in [1, 2, 4, 5, 6, 8, 9]) {
      final t = odaiFor(DateTime(2026, 10, day));
      card = card.withStamp(
        OdaiStamp(
          date: '2026-10-${day.toString().padLeft(2, '0')}',
          themeId: t.id,
          text: t.text,
          kind: StampKind.character,
          characterId: 'c_1',
        ),
      );
    }
    store.stampCard = card.toJson();
    await _pump(
      tester,
      overrides: [drawingLoopStorageProvider.overrideWithValue(store)],
    );
    await _tap(tester, find.byKey(const Key('odai-calendar')));
    await _shot(tester, '21_odai_calendar');
  });

  _shotTest('22 Before/After video', (tester) async {
    final app = await _pump(
      tester,
      overrides: [videoAssetLoaderProvider.overrideWithValue(readAssetFile)],
    );
    await tester.runAsync(() => app.characters.saveBeforePhoto('c_1', _before));
    await _tap(tester, find.byKey(const Key('home-zukan')));
    await _tap(tester, find.byKey(const Key('zukan-card-c_1')));
    final open = find.byKey(const Key('video-open'));
    await tester.scrollUntilVisible(
      open,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pump();
    // The preview loops forever: pump real async work instead of settling.
    for (var i = 0; i < 100; i++) {
      if (find.byKey(const Key('video-make')).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byKey(const Key('video-make')), findsOneWidget);
    // Into the end card: paper photo → character, name and logo.
    await tester.pump(Duration(milliseconds: _videoEndCardMs));
    await _shot(tester, '22_video_export', settle: false);
  });
}

/// A moment inside the video's end card (docs/VIDEO.md: the last 2.8 s).
const _videoEndCardMs = 12600;
