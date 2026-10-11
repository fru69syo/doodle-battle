// v2 CPU roster (assets/cpu/manifest_v2.json) and the stage table.
import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/cpu_roster_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = V3Spec();
  final manifest = (jsonDecode(
    File(kCpuManifestV2Path).readAsStringSync(),
  ) as Map).cast<String, Object?>();
  final roster = CpuRosterV2.fromManifestJson(manifest);
  final raw = (manifest['characters']! as List).cast<Map<String, Object?>>();

  test('about 30 doodles covering every attribute and shape', () {
    expect(roster.byId.length, raw.length); // unique ids
    expect(raw.length, inInclusiveRange(28, 40));
    final attrs = <String, int>{};
    final shapes = <String>{};
    for (final c in raw) {
      attrs[c['attribute']! as String] = (attrs[c['attribute']] ?? 0) + 1;
      shapes.add(c['shape']! as String);
    }
    for (final a in ['gu', 'choki', 'pa']) {
      expect(attrs[a], greaterThanOrEqualTo(8), reason: a);
    }
    expect(shapes, containsAll(['limbs', 'blob', 'vehicle']));
  });

  test('recorded attribute / Lv1 stats match the engine; no hidden form', () {
    for (final c in raw) {
      final g = roster.byId[c['id']]!.genome(s);
      expect(g.attr.name, c['attribute'], reason: '${c['id']}');
      expect(g.statsAt(1), c['statsLv1'], reason: '${c['id']}');
      expect(maxHpOf(s, g.statsAt(1)), c['maxHpLv1']);
      expect(g.isBloomer, isFalse, reason: '${c['id']}');
      expect(File(c['asset']! as String).existsSync(), isTrue);
    }
  });

  test('every stage CPU exists and builds a fighter', () {
    for (final st in stageTable()) {
      final f = roster.stageFighter(st);
      expect(f.moves, hasLength(unlockedSlots(s, st.cpuLevel)));
      expect(f.stats, hasLength(10));
    }
  });
}
