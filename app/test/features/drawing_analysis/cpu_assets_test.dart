import 'dart:convert';
import 'dart:io';

import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final manifest = jsonDecode(
    File('assets/cpu/manifest.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final chars = (manifest['characters']! as List).cast<Map<String, Object?>>();

  test('CPU doodles cover every element, twice', () {
    expect(chars.length, 12);
    final counts = <ElementType, int>{};
    for (final c in chars) {
      final e = ElementType.fromName(c['element']! as String);
      counts[e] = (counts[e] ?? 0) + 1;
    }
    for (final e in ElementType.values) {
      expect(counts[e], 2, reason: e.name);
    }
    expect({for (final c in chars) c['id']}.length, chars.length);
  });

  test('manifest entries are consistent with their assets and SPEC §3.2', () {
    for (final c in chars) {
      final file = File(c['asset']! as String);
      expect(file.existsSync(), isTrue, reason: file.path);
      final png = img.decodePng(file.readAsBytesSync())!;
      expect(png.numChannels, 4);
      expect(png.width <= 512 && png.height <= 512, isTrue);
      final stats = Stats.fromJson(
        (c['baseStats']! as Map).cast<String, Object?>(),
      );
      final energy = (c['energy']! as num).toDouble();
      final skill = (c['skill']! as num).toDouble();
      expect(stats.total, statBudget(energy, skill).round());
      expect(c['isShobo'], skill > 75);
    }
  });
}
