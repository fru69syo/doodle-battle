import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/data/backend/backend_models.dart';
import 'package:doodle_battle/data/file_character_repository.dart';
import 'package:doodle_battle/domain/character.dart';
import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/domain/cosmetics.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// Exactly what v1.0 wrote (`Character.toJson()` at bde9259).
const v10Json = '''
{"id":"c_1760000000000_ab12","name":"ねこまる","imagePath":"/data/user/0/x/app_flutter/characters/c_1760000000000_ab12.png","imageHash":"9f2c","element":"water","baseStats":{"hp":120,"atk":90,"def":80,"spd":110},"energy":72.5,"skill":20.0,"features":{"inkCoverage":0.31,"colorCount":4},"createdAt":"2026-10-09T10:00:00.000","level":7,"xp":40,"seedAllocations":{"atk":1},"subject":"ねこ","elementMoveName":null,"specialMoveName":null,"onlineId":"snap_1","cardFrame":null}
''';

Character sample({CharacterCosmetics cosmetics = CharacterCosmetics.none}) =>
    Character(
      id: 'c1',
      name: 'もこもこ',
      imagePath: '/tmp/c1.png',
      imageHash: 'abc',
      element: ElementType.leaf,
      baseStats: const Stats(hp: 80, atk: 70, def: 60, spd: 90),
      energy: 72.5,
      skill: 20,
      features: const {'inkCoverage': 0.31},
      createdAt: DateTime.utc(2026, 10, 10),
      level: 12,
      cosmetics: cosmetics,
    );

/// [sample] as the app stores it now (v2; migrated from the v1 record).
CharacterV2 sampleV2({CharacterCosmetics cosmetics = CharacterCosmetics.none}) =>
    CharacterV2.fromJson(sample(cosmetics: cosmetics).toJson());

const fullCosmetics = CharacterCosmetics(
  parts: [
    CharacterPart(
      id: 'p1',
      type: PartType.hat,
      transform: PartTransform(cx: 0.5, cy: 0.02, scale: 0.5),
    ),
    CharacterPart(
      id: 'p2',
      type: PartType.wings,
      transform: PartTransform(
        cx: 0.5,
        cy: 0.4,
        scale: 1.0,
        rotation: -0.25,
        behind: true,
      ),
    ),
  ],
  effects: {DrawnMove.element: 'fx_element_1', DrawnMove.special: 'fx_s_2'},
  odai: OdaiBadge(themeId: 'g12', date: '2026-10-10', text: 'つばさの ある いきもの'),
);

void main() {
  group('Character JSON backward compatibility', () {
    test('a v1.0 character loads with no cosmetics and keeps every field', () {
      final c = Character.fromJson(
        (jsonDecode(v10Json) as Map).cast<String, Object?>(),
      );
      expect(c.cosmetics.isEmpty, isTrue);
      expect(c.cosmetics.parts, isEmpty);
      expect(c.level, 7);
      expect(c.onlineId, 'snap_1');
      expect(c.seedAllocations, {StatKind.atk: 1});
      // Re-saving an untouched v1.0 character writes the same JSON.
      expect(c.toJson(), (jsonDecode(v10Json) as Map).cast<String, Object?>());
      expect(c.toJson().containsKey('cosmetics'), isFalse);
    });

    test('cosmetics round-trip', () {
      final c = sample(cosmetics: fullCosmetics);
      final back = Character.fromJson(
        (jsonDecode(jsonEncode(c.toJson())) as Map).cast<String, Object?>(),
      );
      expect(back.toJson(), c.toJson());
      expect(back.cosmetics.parts.map((p) => p.type), [
        PartType.hat,
        PartType.wings,
      ]);
      expect(back.cosmetics.parts[1].transform.behind, isTrue);
      expect(back.cosmetics.effects[DrawnMove.special], 'fx_s_2');
      expect(back.cosmetics.odai!.text, 'つばさの ある いきもの');
    });

    test('broken or future cosmetics never lose the character', () {
      final json = sample().toJson()
        ..['cosmetics'] = {
          'parts': [
            {
              'id': 'ok',
              'type': 'cape',
              'transform': {'cx': 9, 'scale': 99},
            },
            {'type': 'hat'}, // no id → skipped
            'garbage',
            for (var i = 0; i < 5; i++)
              {'id': 'x$i', 'type': 'horn', 'transform': <String, Object?>{}},
          ],
          'effects': {'element': 3, 'laser': 'fx', 'special': 'fx_ok'},
          'odai': {'themeId': 1},
          'somethingNew': true,
        };
      final c = Character.fromJson(json);
      expect(c.name, 'もこもこ');
      expect(c.cosmetics.parts.length, CharacterCosmetics.maxParts);
      final first = c.cosmetics.parts.first;
      expect(first.type, PartType.accessory, reason: 'unknown type');
      expect(first.transform.cx, 1 + PartTransform.maxOverhang);
      expect(first.transform.scale, PartTransform.maxScale);
      expect(c.cosmetics.effects, {DrawnMove.special: 'fx_ok'});
      expect(c.cosmetics.odai, isNull);
      expect(
        Character.fromJson(sample().toJson()..['cosmetics'] = 'nope').cosmetics,
        same(CharacterCosmetics.none),
      );
    });

    test(
      'FileCharacterRepository loads v1.0 files next to v1.1 files',
      () async {
        final dir = await Directory.systemTemp.createTemp('loop_migration');
        addTearDown(() => dir.delete(recursive: true));
        final chars = Directory('${dir.path}/characters')..createSync();
        File('${chars.path}/c_1760000000000_ab12.json')
            .writeAsStringSync(v10Json);
        final repo = FileCharacterRepository(dir);
        await repo.add(
          sampleV2(cosmetics: fullCosmetics),
          testPng(),
          limit: 12,
        );
        final all = await repo.loadAll();
        expect(all.map((c) => c.id), ['c_1760000000000_ab12', 'c1']);
        expect(all.first.cosmetics.isEmpty, isTrue);
        expect(all.last.cosmetics.parts.length, 2);
        // Updating the old one with cosmetics works in place.
        await repo.update(
          all.first.copyWith(
            cosmetics: const CharacterCosmetics(
              effects: {DrawnMove.element: 'fx'},
            ),
          ),
        );
        final again = await repo.loadAll();
        expect(again.first.cosmetics.effects[DrawnMove.element], 'fx');
        expect(again.first.level, 7);
      },
    );

    test('online registration never carries cosmetics', () {
      final json = RegisterCharacterRequest(
        character: sampleV2(cosmetics: fullCosmetics),
        png: testPng(),
      ).toJson();
      expect(json.containsKey('cosmetics'), isFalse);
      expect(jsonEncode(json).contains('part_'), isFalse);
      expect(jsonEncode(json).contains('fx_'), isFalse);
    });

    test('cosmetics do not touch stats or evolution', () {
      final plain = sample(), decorated = sample(cosmetics: fullCosmetics);
      expect(decorated.baseStats.toJson(), plain.baseStats.toJson());
      expect(decorated.stage, plain.stage);
      expect(decorated.isShobo, plain.isShobo);
    });

    test('part slots unlock at Lv5 / Lv10 / Lv20', () {
      expect([1, 4, 5, 9, 10, 19, 20, 30].map(partSlotsFor), [
        0,
        0,
        1,
        1,
        2,
        2,
        3,
        3,
      ]);
      expect([1, 2, 3].map(partSlotUnlockLevel), [5, 10, 20]);
    });
  });
}
