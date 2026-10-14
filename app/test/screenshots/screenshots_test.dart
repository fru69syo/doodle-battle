// Renders the main screens to PNG for the store / QA (phone portrait,
// 1080×1920 px at 2.625 dpr, real Zen Maru Gothic + Material icons, real CPU
// doodles, real on-device analysis of synthetic kid drawings). The hero
// character comes from a synthetic photo of a kid drawing on paper
// (`00_paper_photo.jpg`), so Before (paper) and After (character) match.
// store/tools/compose_screenshots.py turns a selection into the listing.
//
// Store rule (SPEC §3.5, docs/STORE_LISTING.md §3): no screenshot shows a
// character in the hidden form, nor anything that rates a drawing — every
// character below is a kid drawing (checked in setUpAll).
//
// Not part of the normal test run (tag `screenshots` is skipped by
// dart_test.yaml). Regenerate with `tool/screenshots.sh`.
@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/before_photo.dart';
import 'package:doodle_battle/data/drawing_loop_storage.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/domain/character_v2_view.dart';
import 'package:doodle_battle/domain/drawing_analysis_result.dart';
import 'package:doodle_battle/features/card_print/card_output.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:doodle_battle/features/drawing_loop/odai/daily_odai.dart';
import 'package:doodle_battle/features/drawing_loop/odai/stamp_card.dart';
import 'package:doodle_battle/features/draw_canvas/draw_canvas_screen.dart';
import 'package:doodle_battle/features/draw_canvas/stroke_drawing.dart';
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
late DrawingAnalysisResult _green;

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

CharacterV2 _char(
  String id,
  String name,
  DrawingAnalysisResult r, {
  required int level,
  int xp = 0,
  String? frame,
  String? elementMove,
  String? specialMove,
  String? subject,
}) =>
    CharacterV2.create(
      id: id,
      name: name,
      imagePath: 'memory://$id.png',
      imageHash: cutoutHash(r.cutoutPng),
      rawFeatures: r.features,
      energy: r.energy,
      skill: r.skill,
      createdAt: DateTime(2026, 10, int.parse(id.substring(2))),
      subject: subject,
      legacyElement: r.element,
    ).copyWith(
      level: level,
      xp: xp,
      cardFrame: () => frame,
      moves: [
        CharacterMove(name: elementMove),
        CharacterMove.empty,
        CharacterMove.empty,
        CharacterMove(name: specialMove),
      ],
    );

/// The child's collection: levels 12 / 7 / 6 / 1, all kid drawings.
List<CharacterV2> _collection() => [
  _char(
    'c_1',
    'ぐるぐるドラゴン',
    _scribble,
    level: 12,
    xp: xpToNext(const V3Spec(), 12) - 20,
    frame: 'hoshi',
    elementMove: 'ぐるぐるファイヤー',
    specialMove: 'ドラゴンだいばくはつ',
    subject: 'ドラゴン',
  ),
  _char('c_2', 'ぷにまる', _blob, level: 7, xp: 40),
  _char('c_3', 'もりもり', _green, level: 6, xp: 30),
  _char('c_4', 'にこにこ', _marker, level: 1),
];

Map<String, Uint8List> _images() => {
  'c_1': _scribble.cutoutPng,
  'c_2': _blob.cutoutPng,
  'c_3': _green.cutoutPng,
  'c_4': _marker.cutoutPng,
};

const _progress = GameProgress(
  clearedStage: 23, // worlds 1–3 open (stage select: 100 stages in 10 worlds)
  stageStars: {
    1: 3, 2: 3, 3: 3, 4: 2, 5: 3, 6: 3, 7: 2, 8: 3, 9: 3, 10: 2, //
    11: 3, 12: 2, 13: 3, 14: 3, 15: 1, 16: 3, 17: 2, 18: 3, 19: 3, 20: 2,
    21: 3, 22: 2, 23: 1,
  },
  displayName: ChosenDisplayName(
    adjectiveId: 'a05',
    nounId: 'n01',
    text: 'げんきな ドラゴン',
  ),
  onlineBadge: 'bear', // rated play: くま (the number is never shown)
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
  List<CharacterV2>? characters,
  FakeAnalyzer? analyzer,
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
  battleTimeScale: 1,
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

/// Highest stage of world 1 whose CPU [c]'s attribute beats.
int _advantageStage(CharacterV2 c) {
  final beats = c.attribute().beats;
  for (final st in stageTable().reversed) {
    if (st.stage > 10) continue;
    if (testRoster.byId[st.cpuId]?.genome().attr == beats) return st.stage;
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
    _green = _analyse(colourBlob(Crayon.green, seed: 9));
    for (final c in _collection()) {
      expect(
        c.genome().isBloomer,
        isFalse,
        reason: '${c.name}: store screenshots never show the hidden form',
      );
    }
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

  _shotTest('03b drawing tool (アプリで かく)', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('home-draw')));
    await _tap(tester, find.byKey(const Key('draw-in-app')));
    final st = tester.state<DrawCanvasScreenState>(
      find.byType(DrawCanvasScreen),
    );
    for (final s in _canvasMonster().strokes) {
      st.controller.setColor(s.color);
      st.controller.setTool(s.tool);
      st.controller.begin(s.xy[0], s.xy[1]);
      for (var i = 2; i < s.xy.length; i += 2) {
        st.controller.extend(s.xy[i], s.xy[i + 1]);
      }
      st.controller.end();
    }
    // Leave the crayon and a colour picked, as a child would.
    st.controller.setColor(kCanvasColors[3]);
    st.controller.setTool(DrawTool.crayon);
    await tester.pumpAndSettle();
    await _shot(tester, '03b_draw_canvas');
  });

  _shotTest('08c joint editor (うごく ところを なおす)', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('home-zukan')));
    await _tap(tester, find.byKey(const Key('zukan-card-c_1')));
    final joints = find.byKey(const Key('detail-joints'));
    await tester.scrollUntilVisible(
      joints,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(joints);
    await settleReal(tester);
    expect(find.byKey(const Key('joint-preview')), findsOneWidget);
    // The preview loops forever: let it run into a pose, no settling.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _shot(tester, '08c_joint_editor', settle: false);
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

  _shotTest('09 worlds / stages', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('home-battle')));
    await _tap(tester, find.byKey(const Key('select-c_1')));
    await _shot(tester, '09_world_select');
    await _tap(tester, find.byKey(const Key('world-3')));
    await _centre(
      tester,
      find.byKey(Key('stage-${_progress.clearedStage + 1}')),
      alignment: 0.7,
    );
    await _shot(tester, '09b_stage_select');
  });

  _shotTest('10 battle / 11 result / 12 ad notice', (tester) async {
    final hero = _collection().first;
    final stage = _advantageStage(hero);
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('home-battle')));
    await _tap(tester, find.byKey(const Key('select-c_1')));
    await _tap(tester, find.byKey(const Key('world-1')));
    await _centre(tester, find.byKey(Key('stage-$stage')));
    await tapNoSettle(tester, find.byKey(Key('stage-$stage')));
    await settleReal(tester, rounds: 10);
    // Mid-fight on the 2.5D stage, with a move picked ahead (さきどり).
    await tester.tap(find.byKey(const Key('move-0')));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _shot(tester, '10_battle', settle: false);

    await playBattle(tester);
    await _shot(tester, '11_result');

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

  // No purchase notice shot: in-app purchases are off in v2.0 (SPEC §10.2).
  _shotTest('15 おうちのひと', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('home-parent')));
    await _shot(tester, '15_parent_settings');
  });

  _shotTest('17 family setup / 19 family battle', (tester) async {
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
    await tapNoSettle(tester, find.byKey(const Key('family-start')));
    await settleReal(tester, rounds: 10);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('family-controls-b')), findsOneWidget);
    await _shot(tester, '19_family_battle', settle: false);
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

/// A round kid monster drawn with the in-app tools (canvas units, 1000×1250):
/// crayon outline and colouring, pen face, brush horns, crayon arms and legs.
StrokeDrawing _canvasMonster() {
  final r = math.Random(3);
  double j() => (r.nextDouble() - 0.5) * 8;
  Stroke line(DrawTool t, int colour, List<(double, double)> pts) {
    final s = Stroke(t, kCanvasColors[colour], null);
    for (var i = 0; i < pts.length - 1; i++) {
      for (var k = 0; k < 10; k++) {
        final u = k / 10;
        s.add(
          pts[i].$1 + (pts[i + 1].$1 - pts[i].$1) * u + j(),
          pts[i].$2 + (pts[i + 1].$2 - pts[i].$2) * u + j(),
        );
      }
    }
    s.add(pts.last.$1, pts.last.$2);
    return s;
  }

  List<(double, double)> ring(double cx, double cy, double rx, double ry) => [
    for (var i = 0; i <= 28; i++)
      (
        cx + rx * math.cos(i / 28 * 2 * math.pi),
        cy + ry * math.sin(i / 28 * 2 * math.pi),
      ),
  ];

  // Zig-zag colouring inside an ellipse, like a child filling it in.
  List<(double, double)> fill(double cx, double cy, double rx, double ry) => [
    for (var y = -ry * 0.8; y <= ry * 0.8; y += 34)
      for (final side in [-1, 1])
        (
          cx + side * rx * 0.85 * math.sqrt(1 - (y / ry) * (y / ry)),
          cy + y + (side > 0 ? 17 : 0),
        ),
  ];

  return StrokeDrawing(
    strokes: [
      line(DrawTool.brush, 3, fill(500, 620, 260, 280)),
      line(DrawTool.crayon, 2, ring(500, 620, 270, 290)),
      // horns
      line(DrawTool.brush, 9, [(360, 380), (330, 230), (430, 345)]),
      line(DrawTool.brush, 9, [(640, 380), (670, 230), (570, 345)]),
      // eyes and mouth
      line(DrawTool.marker, 0, ring(420, 560, 38, 44)),
      line(DrawTool.marker, 0, ring(580, 560, 38, 44)),
      line(DrawTool.brush, 0, ring(428, 572, 10, 12)),
      line(DrawTool.brush, 0, ring(572, 572, 10, 12)),
      line(DrawTool.marker, 0, [
        for (var i = 0; i <= 12; i++)
          (420 + i * 13.3, 700 + 50 * math.sin(i / 12 * math.pi)),
      ]),
      line(DrawTool.crayon, 10, ring(350, 660, 34, 20)),
      line(DrawTool.crayon, 10, ring(650, 660, 34, 20)),
      // arms and legs
      line(DrawTool.crayon, 8, [(245, 600), (140, 520), (90, 430)]),
      line(DrawTool.crayon, 8, [(755, 600), (860, 520), (910, 430)]),
      line(DrawTool.crayon, 6, [(410, 890), (390, 1060), (330, 1080)]),
      line(DrawTool.crayon, 6, [(590, 890), (610, 1060), (670, 1080)]),
      // a little sun
      line(DrawTool.brush, 4, ring(860, 150, 50, 50)),
    ],
  );
}
