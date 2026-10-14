import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:doodle_battle/app.dart';
import 'package:doodle_battle/core/providers.dart';
import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/data/memory_character_repository.dart';
import 'package:doodle_battle/data/settings_repository.dart';
import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/domain/cpu_roster_v2.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/features/battle_ui/atb_parts.dart';
import 'package:doodle_battle/features/drawing_loop/display_image.dart';
import 'package:doodle_battle/features/drawing_loop/parts/composite.dart';
import 'package:doodle_battle/features/ng_filter/ng_filter.dart';
import 'package:doodle_battle/features/online/display_name_picker.dart';
import 'package:doodle_battle/features/online/realtime/realtime_client.dart';
import 'package:doodle_battle/features/parent/policy_links.dart';
import 'package:doodle_battle/features/parental_gate/parental_gate.dart';
import 'package:doodle_battle/features/puppet/puppet_builder.dart';
import 'package:doodle_battle/features/puppet/puppet_store.dart';
import 'package:doodle_battle/features/puppet/render/puppet_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final NgFilter testNgFilter = NgFilter.fromJsonString(
  File('assets/ng_words/ng_words.json').readAsStringSync(),
);
final DisplayNameWords testDisplayNameWords = DisplayNameWords.fromJsonString(
  File(displayNameWordsAsset).readAsStringSync(),
);
final CpuRosterV2 testRoster = CpuRosterV2.fromManifestJson(
  (jsonDecode(File(kCpuManifestV2Path).readAsStringSync()) as Map)
      .cast<String, Object?>(),
);

/// Realtime server URL used by tests (the connector is faked).
const testRealtimeUrl = 'wss://battle.example.test/v2';

const setupDone = AppSettings(
  setupCompleted: true,
  policyVersion: currentPolicyVersion,
);

/// A v2 character from simple analyser features. [skill] above 75 makes
/// the hidden late bloomer (tests of the hidden-state rules only).
CharacterV2 testCharacter({
  String id = 'c_1',
  String name = 'ねこまる',
  int level = 1,
  int xp = 0,
  double skill = 20,
  double energy = 80,
  String? onlineId,
  Map<String, num> features = const {'inkCoverage': 0.3},
  String? imageHash,
}) => CharacterV2.create(
  id: id,
  name: name,
  imagePath: 'memory://$id.png',
  imageHash: imageHash ?? 'h$id',
  rawFeatures: features,
  energy: energy,
  skill: skill,
  createdAt: DateTime.utc(2026, 10, 1),
  legacyElement: ElementType.fire,
).copyWith(level: level, xp: xp, onlineId: () => onlineId);

/// Everything a test may want to inspect after pumping the app.
class TestApp {
  TestApp({
    required this.characters,
    required this.settingsRepo,
    required this.backend,
    required this.monetization,
    required this.gate,
    required this.analyzer,
    required this.imageSource,
    required this.crash,
  });

  final InMemoryCharacterRepository characters;
  final InMemorySettingsRepository settingsRepo;
  final FakeBackend backend;
  final FakeMonetization monetization;
  final ParentalGate gate;
  final FakeAnalyzer analyzer;
  final FakeImageSource imageSource;
  final FakeCrashReporter crash;
  final openedUrls = <Uri>[];
  late ProviderContainer container;
}

/// Pumps the whole app with fakes (phone-sized portrait surface).
Future<TestApp> pumpApp(
  WidgetTester tester, {
  AppSettings settings = setupDone,
  GameProgress progress = const GameProgress(),
  List<CharacterV2> characters = const [],
  FakeBackend? backend,
  FakeMonetization? monetization,
  ParentalGate? gate,
  FakeAnalyzer? analyzer,
  FakeImageSource? imageSource,
  FakeCrashReporter? crash,
  int seed = 7,
  bool settle = true,
  Map<String, Uint8List> images = const {},
  Size physicalSize = const Size(1080, 2340),
  double devicePixelRatio = 2.75,
  double battleTimeScale = 40,
  bool adsSupported = true,
  bool iapEnabled = false,
  String realtimeUrl = testRealtimeUrl,
  Widget Function(Widget app)? wrap,
  List<Override> overrides = const [],
  bool jointEditorAfterBirth = false,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);
  final png = testPng();
  final app = TestApp(
    characters: InMemoryCharacterRepository([
      for (final c in characters) (c, images[c.id] ?? png),
    ]),
    settingsRepo: InMemorySettingsRepository(
      settings: settings,
      progress: progress,
    ),
    backend: backend ?? FakeBackend(available: false),
    monetization: monetization ?? FakeMonetization(),
    gate: gate ?? FakeGate(),
    analyzer: analyzer ?? FakeAnalyzer(),
    imageSource: imageSource ?? FakeImageSource(),
    crash: crash ?? FakeCrashReporter(isAvailable: false),
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        characterRepositoryProvider.overrideWithValue(app.characters),
        settingsRepositoryProvider.overrideWithValue(app.settingsRepo),
        backendApiProvider.overrideWithValue(app.backend),
        monetizationServiceProvider.overrideWithValue(app.monetization),
        parentalGateProvider.overrideWithValue(app.gate),
        crashReporterProvider.overrideWithValue(app.crash),
        urlOpenerProvider.overrideWithValue((uri) async {
          app.openedUrls.add(uri);
          return true;
        }),
        drawingAnalyzerProvider.overrideWithValue(app.analyzer),
        drawingImageSourceProvider.overrideWithValue(app.imageSource),
        randomProvider.overrideWithValue(Random(seed)),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 9, 10)),
        ngFilterProvider.overrideWithValue(AsyncData(testNgFilter)),
        cpuRosterV2Provider.overrideWithValue(AsyncData(testRoster)),
        battleTimeScaleProvider.overrideWithValue(battleTimeScale),
        adsSupportedProvider.overrideWithValue(adsSupported),
        iapEnabledProvider.overrideWithValue(iapEnabled),
        realtimeUrlProvider.overrideWithValue(realtimeUrl),
        displayNameWordsProvider.overrideWithValue(
          AsyncData(testDisplayNameWords),
        ),
        // Isolates don't run inside testWidgets' fake async zone.
        compositeRunnerProvider.overrideWithValue(
          (r) async => renderComposite(r),
        ),
        puppetBuilderProvider.overrideWithValue(
          PuppetBuilder(runner: syncRunner),
        ),
        // The joint editor animates forever (preview), which would keep
        // pumpAndSettle from settling; flows that do not test it skip it.
        jointEditorAfterBirthProvider.overrideWithValue(jointEditorAfterBirth),
        ...overrides,
      ],
      child: wrap == null
          ? const DoodleBattleApp()
          : wrap(const DoodleBattleApp()),
    ),
  );
  app.container = ProviderScope.containerOf(
    tester.element(find.byType(DoodleBattleApp)),
  );
  if (settle) await tester.pumpAndSettle();
  return app;
}

/// Scrolls [finder] into view inside the first scrollable and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    // Lazily built list items: scroll until built.
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  // Centre it so neighbours stay built in lazy lists.
  final element = finder.evaluate().single;
  Scrollable.ensureVisible(element, alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Unmounts the app so periodic timers are cancelled before the test ends.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// Real async work (image decoding, puppet sprites) inside a widget test.
Future<void> settleReal(WidgetTester tester, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets an ATB battle on the 2.5D stage run (the child does not tap: the
/// 5 s timer picks おまかせ) until [done] (default: the result screen).
Future<void> playBattle(
  WidgetTester tester, {
  Finder? done,
  int maxFrames = 3000,
}) async {
  final target = done ?? find.byKey(const Key('result-title'));
  await settleReal(tester, rounds: 10);
  for (var i = 0; i < maxFrames && target.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (i % 100 == 99) await settleReal(tester, rounds: 1);
  }
  expect(target, findsWidgets, reason: 'the battle should end');
  await tester.pumpAndSettle();
}

/// Taps [finder] (scrolling it into view) without waiting for animations
/// to settle — for buttons that open a battle (the stage animates forever).
Future<void> tapNoSettle(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
