import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart' show randomFeatures;
import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/features/puppet/character_puppet.dart';
import 'package:doodle_battle/features/puppet/puppet_builder.dart';
import 'package:doodle_battle/features/puppet/rig/character_rig.dart';
import 'package:doodle_battle/features/puppet/samples.dart';
import 'package:flutter_test/flutter_test.dart';

CharacterV2 v2({
  required int level,
  required int skill10,
  Map<String, Object?>? rig,
}) => CharacterV2(
  id: 'c',
  name: 'て',
  imagePath: '/x.png',
  imageHash: 'ab' * 32,
  features: randomFeatures(Mulberry32(3)),
  energy10: 700,
  skill10: skill10,
  createdAt: DateTime.utc(2026, 10, 1),
  level: level,
  rig: rig,
);

void main() {
  test('CharacterV2: stored rig blob drives the puppet; looks by level', () {
    final png = samplePng(Sample.hero);
    final rig = autoRigPng(png);
    final edited = rig.copy(source: RigSource.edited);
    final c = v2(level: 12, skill10: 200, rig: edited.toBlob());
    final spec = characterV2PuppetSpec(c, png);
    expect(spec.rig!.encode(), edited.encode());
    expect(spec.look.simple, isFalse);
    expect(spec.look.legend, isFalse);
    // A very polished picture (hidden late bloomer): simple until Lv50,
    // then でんせつ like everyone.
    expect(
      characterV2PuppetSpec(v2(level: 49, skill10: 950), png).look.simple,
      isTrue,
    );
    final at50 = characterV2PuppetSpec(v2(level: 50, skill10: 950), png).look;
    expect(at50.simple, isFalse);
    expect(at50.legend, isTrue);
    // A broken blob falls back to the auto rig.
    expect(
      characterV2PuppetSpec(
        v2(level: 3, skill10: 200, rig: {'v': 99}),
        png,
      ).rig,
      isNull,
    );
    expect(characterV2PuppetSpec(v2(level: 3, skill10: 200), png).rig, isNull);
  });
}
