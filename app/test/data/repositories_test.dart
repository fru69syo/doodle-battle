import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/character_repository.dart';
import 'package:doodle_battle/data/file_character_repository.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/data/memory_character_repository.dart';
import 'package:doodle_battle/data/settings_repository.dart';
import 'package:doodle_battle/domain/character_v2.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('db_repo'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('FileCharacterRepository', () {
    test('add / loadAll / readImage round-trip', () async {
      final repo = FileCharacterRepository(dir);
      final c = testCharacter(id: 'c_a', level: 3, xp: 5);
      await repo.add(c, testPng(), limit: 12);
      final all = await repo.loadAll();
      expect(all.single.toJson(), c.toJson());
      expect(await repo.readImage('c_a'), testPng());
      expect(repo.imagePathFor('c_a'), endsWith('characters/c_a.png'));
      expect(File(repo.imagePathFor('c_a')).existsSync(), isTrue);
    });

    test('a new repository instance reads what was stored', () async {
      await FileCharacterRepository(dir)
          .add(testCharacter(), testPng(), limit: 12);
      final again = await FileCharacterRepository(dir).loadAll();
      expect(again.single.name, 'ねこまる');
    });

    test('enforces the collection limit', () async {
      final repo = FileCharacterRepository(dir);
      for (var i = 0; i < 3; i++) {
        await repo.add(testCharacter(id: 'c_$i'), testPng(), limit: 3);
      }
      expect(
        () => repo.add(testCharacter(id: 'c_x'), testPng(), limit: 3),
        throwsA(isA<CollectionFullException>()),
      );
    });

    test('update, delete and deleteAll', () async {
      final repo = FileCharacterRepository(dir);
      await repo.add(testCharacter(id: 'c_1'), testPng(), limit: 12);
      await repo.add(testCharacter(id: 'c_2'), testPng(), limit: 12);
      await repo.update(testCharacter(id: 'c_1').copyWith(level: 7, xp: 3));
      expect((await repo.loadAll()).first.level, 7);
      await repo.delete('c_1');
      expect((await repo.loadAll()).map((c) => c.id), ['c_2']);
      expect(await repo.readImage('c_1'), isNull);
      await repo.deleteAll();
      expect(await repo.loadAll(), isEmpty);
    });

    test('rejects ids that could escape the directory', () async {
      final repo = FileCharacterRepository(dir);
      expect(
        () => repo.add(testCharacter(id: '../x'), testPng(), limit: 12),
        throwsArgumentError,
      );
    });

    test('migrates a saved v1 character on load and stores it as v2', () async {
      final f = File('${dir.path}/characters/c_old.json')
        ..createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({
          'id': 'c_old',
          'name': 'むかしくん',
          'imagePath': '/x/c_old.png',
          'imageHash': 'deadbeef00',
          'element': 'water',
          'baseStats': {'hp': 100, 'atk': 90, 'def': 80, 'spd': 70},
          'energy': 82.5,
          'skill': 20.0,
          'features': {'inkCoverage': 0.3, 'roundness': 0.6},
          'createdAt': '2026-09-01T00:00:00.000Z',
          'level': 12,
          'xp': 10,
          'seedAllocations': {'atk': 2},
          'elementMoveName': 'ざぶーんパンチ',
          'specialMoveName': null,
          'onlineId': 'snap-v1',
        }),
      );
      final c = (await FileCharacterRepository(dir).loadAll()).single;
      expect(c.level, 12);
      expect(c.onlineId, isNull); // v1 snapshots are not v2 ones
      expect(c.allMoves().first.name, 'ざぶーんパンチ');
      final stored = jsonDecode(f.readAsStringSync()) as Map;
      expect(stored['schema'], CharacterV2.schema);
      expect(stored.containsKey('baseStats'), isFalse);
    });

    test('skips corrupt files instead of losing the collection', () async {
      final repo = FileCharacterRepository(dir);
      await repo.add(testCharacter(id: 'c_ok'), testPng(), limit: 12);
      File('${dir.path}/characters/broken.json').writeAsStringSync('{not json');
      expect((await repo.loadAll()).map((c) => c.id), ['c_ok']);
    });
  });

  test('InMemoryCharacterRepository behaves like the file one', () async {
    final repo = InMemoryCharacterRepository();
    await repo.add(testCharacter(id: 'c_1'), testPng(), limit: 1);
    expect(
      () => repo.add(testCharacter(id: 'c_2'), testPng(), limit: 1),
      throwsA(isA<CollectionFullException>()),
    );
    expect(() => repo.update(testCharacter(id: 'nope')), throwsStateError);
    expect(await repo.readImage('c_1'), isNotNull);
  });

  group('FileSettingsRepository', () {
    test('defaults when nothing is stored', () async {
      final repo = FileSettingsRepository(dir);
      final s = await repo.loadSettings();
      expect(s.needsSetup, isTrue);
      expect(s.consents, const ParentConsents());
      expect((await repo.loadProgress()).clearedStage, 0);
    });

    test('round-trips settings and progress, clear wipes both', () async {
      final repo = FileSettingsRepository(dir);
      const s = AppSettings(
        setupCompleted: true,
        policyVersion: currentPolicyVersion,
        consents: ParentConsents(cloudJudge: true, ads: true),
        playTimeMinutes: 60,
        entitlements: {'slots_24'},
      );
      await repo.saveSettings(s);
      await repo.saveProgress(
        const GameProgress(
          clearedStage: 4,
          onlineLevels: {'c_1': 6},
        ).withAppliedMatch('m1'),
      );
      final again = FileSettingsRepository(dir);
      final loaded = await again.loadSettings();
      expect(loaded.toJson(), s.toJson());
      expect(loaded.needsSetup, isFalse);
      final p = await again.loadProgress();
      expect(p.clearedStage, 4);
      expect(p.appliedMatchIds, ['m1']);
      expect(p.onlineLevels, {'c_1': 6});
      await again.clear();
      expect((await again.loadSettings()).setupCompleted, isFalse);
    });
  });

  test('stage stars, おまかせ and the online badge round-trip', () {
    const p = GameProgress(
      clearedStage: 3,
      stageStars: {1: 3, 2: 1, 3: 2},
      omakase: true,
      onlineBadge: 'fox',
    );
    final back = GameProgress.fromJson(
      (jsonDecode(jsonEncode(p.toJson())) as Map).cast<String, Object?>(),
    );
    expect(back.stageStars, {1: 3, 2: 1, 3: 2});
    expect(back.starsOf(4), 0);
    expect(back.omakase, isTrue);
    expect(back.onlineBadge, 'fox');
  });

  test('applied match ids are deduplicated and capped', () {
    var p = const GameProgress();
    for (var i = 0; i < GameProgress.maxAppliedMatchIds + 5; i++) {
      p = p.withAppliedMatch('m$i');
    }
    p = p.withAppliedMatch('m10');
    expect(p.appliedMatchIds.length, GameProgress.maxAppliedMatchIds);
    expect(p.appliedMatchIds.last, 'm10');
    expect(p.appliedMatchIds.where((m) => m == 'm10').length, 1);
  });

  test('an older policy version requires the setup again', () {
    const s = AppSettings(setupCompleted: true, policyVersion: 0);
    expect(s.needsSetup, isTrue);
  });
}
