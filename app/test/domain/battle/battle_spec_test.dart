import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/battle/battle_spec_asset.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled asset is byte-identical to shared/battle_spec/battle_spec.json',
    () {
      expect(
        File(assetCopyPath).readAsStringSync(),
        File(sharedSpecPath).readAsStringSync(),
        reason: 'run `dart run tool/sync_battle_spec.dart`',
      );
    },
  );

  test(
    'spec loaded through the asset bundle equals the shared JSON file',
    () async {
      final spec = await loadBattleSpec();
      final raw = jsonDecode(File(sharedSpecPath).readAsStringSync());
      // toJson() rebuilds every field from the typed model, so this also proves
      // nothing in the JSON is dropped or misread.
      expect(spec.toJson(), raw);
    },
  );

  final spec = loadSpecFromFile();

  test('type chart follows SPEC §4.1', () {
    const beats = {
      (ElementType.fire, ElementType.leaf),
      (ElementType.leaf, ElementType.thunder),
      (ElementType.thunder, ElementType.water),
      (ElementType.water, ElementType.fire),
      (ElementType.shadow, ElementType.rainbow),
      (ElementType.rainbow, ElementType.shadow),
    };
    for (final a in ElementType.values) {
      for (final d in ElementType.values) {
        final adv = beats.contains((a, d));
        final dis = !adv && beats.contains((d, a));
        expect(
          spec.typeChart.multiplierPct(a, d),
          adv ? 150 : (dis ? 75 : 100),
          reason: '${a.name} -> ${d.name}',
        );
      }
    }
  });

  test('moves follow SPEC §4.1', () {
    expect(spec.moves.tackle.power, 40);
    expect(spec.moves.tackle.typed, isFalse);
    expect(spec.moves.element.power, 60);
    expect(spec.moves.element.accuracyPct, 90);
    expect(spec.moves.guard.damageTakenPct(1), 50);
    expect(
      spec.moves.guard.damageTakenPct(2),
      greaterThan(spec.moves.guard.damageTakenPct(1)),
    );
    expect(spec.moves.guard.damageTakenPct(99), 100);
    expect(spec.moves.special.power, 120);
    expect(spec.gauge.max, 100);
    expect(spec.hpMultiplier, 3);
    expect(spec.timeoutAction, BattleAction.tackle);
  });

  test('CPU stage table covers 1..30 with known placeholder ids', () {
    expect(
      [for (final s in spec.cpu.stages) s.stage],
      [for (var i = 1; i <= 30; i++) i],
    );
    for (final s in spec.cpu.stages) {
      expect(spec.cpu.characterIds, contains(s.cpuId));
      expect(s.level, inInclusiveRange(1, spec.growth.maxLevel));
      expect(s.xpMultiplierPct, greaterThanOrEqualTo(100));
    }
    expect(spec.cpu.stage(30).level, spec.growth.maxLevel);
    expect(spec.cpu.stage(1).aiTier, AiTier.weak);
    expect(spec.cpu.stage(30).aiTier, AiTier.strong);
  });
}
