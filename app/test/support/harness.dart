import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:doodle_battle/app.dart';
import 'package:doodle_battle/core/providers.dart';
import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/data/memory_character_repository.dart';
import 'package:doodle_battle/data/settings_repository.dart';
import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/character.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:doodle_battle/features/battle_ui/cpu_battle_screen.dart';
import 'package:doodle_battle/features/ng_filter/ng_filter.dart';
import 'package:doodle_battle/features/online/display_name_picker.dart';
import 'package:doodle_battle/features/online/online_battle_screen.dart';
import 'package:doodle_battle/features/online/online_lobby_screen.dart';
import 'package:doodle_battle/features/parent/policy_links.dart';
import 'package:doodle_battle/features/parental_gate/parental_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final BattleSpec testSpec = BattleSpec.fromJsonString(
  File('assets/battle/battle_spec.json').readAsStringSync(),
);
final NgFilter testNgFilter = NgFilter.fromJsonString(
  File('assets/ng_words/ng_words.json').readAsStringSync(),
);
final DisplayNameWords testDisplayNameWords = DisplayNameWords.fromJsonString(
  File(displayNameWordsAsset).readAsStringSync(),
);
final CpuRoster testRoster = CpuRoster.fromManifestJson(
  (jsonDecode(File('assets/cpu/manifest.json').readAsStringSync()) as Map)
      .cast<String, Object?>(),
);

const setupDone = AppSettings(
  setupCompleted: true,
  policyVersion: currentPolicyVersion,
);

Character testCharacter({
  String id = 'c_1',
  String name = 'ねこまる',
  int level = 1,
  int xp = 0,
  double skill = 20,
  Stats stats = const Stats(hp: 140, atk: 140, def: 120, spd: 130),
  String? onlineId,
}) => Character(
  id: id,
  name: name,
  imagePath: 'memory://$id.png',
  imageHash: 'h$id',
  element: ElementType.fire,
  baseStats: stats,
  energy: 80,
  skill: skill,
  features: const {'inkCoverage': 0.3},
  createdAt: DateTime.utc(2026, 10, 1),
  level: level,
  xp: xp,
  onlineId: onlineId,
);

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
  List<Character> characters = const [],
  FakeBackend? backend,
  FakeMonetization? monetization,
  ParentalGate? gate,
  FakeAnalyzer? analyzer,
  FakeImageSource? imageSource,
  FakeCrashReporter? crash,
  int seed = 7,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final png = testPng();
  final app = TestApp(
    characters: InMemoryCharacterRepository([
      for (final c in characters) (c, png),
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
        battleSpecProvider.overrideWithValue(AsyncData(testSpec)),
        ngFilterProvider.overrideWithValue(AsyncData(testNgFilter)),
        cpuRosterProvider.overrideWithValue(AsyncData(testRoster)),
        displayNameWordsProvider.overrideWithValue(
          AsyncData(testDisplayNameWords),
        ),
        battleStepProvider.overrideWithValue(const Duration(milliseconds: 20)),
        queueHeartbeatProvider.overrideWithValue(const Duration(seconds: 10)),
        matchPollProvider.overrideWithValue(const Duration(seconds: 5)),
      ],
      child: const DoodleBattleApp(),
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

/// Taps moves (ひっさつ when ready) until the result screen shows. Returns
/// the number of turns played.
Future<int> fightUntilResult(WidgetTester tester) async {
  var turns = 0;
  while (find.byKey(const Key('result-title')).evaluate().isEmpty) {
    expect(turns, lessThan(40), reason: 'battle should end by the turn cap');
    final special = find.byKey(const Key('move-special'));
    final ready = tester.widget<ButtonStyleButton>(special).enabled;
    await tester.tap(ready ? special : find.byKey(const Key('move-element')));
    await tester.pumpAndSettle();
    turns++;
  }
  return turns;
}
