import 'dart:math' as math;
import 'package:doodle_battle/features/ar/glb/glb_reader.dart';
import 'package:doodle_battle/features/ar/sample_cutout.dart';
import 'package:doodle_battle/features/spike3d/inflate/inflate_mesh.dart';
import 'package:doodle_battle/features/spike3d/inflate/inflated_glb.dart';
import 'package:doodle_battle/features/spike3d/inflate/procedural_rig.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:doodle_battle/features/spike3d/samples.dart';

/// Every undirected edge used by exactly two triangles, in opposite
/// directions (closed, consistently oriented 2-manifold).
void expectWatertight(InflatedMesh m) {
  final directed = <int, int>{};
  final n = m.vertexCount;
  final idx = m.indices;
  // Weld by position for the flat-shaded variant.
  final key = <String, int>{};
  final weld = List<int>.generate(n, (v) {
    final p = m.positions;
    final k =
        '${p[v * 3].toStringAsFixed(5)},${p[v * 3 + 1].toStringAsFixed(5)},'
        '${p[v * 3 + 2].toStringAsFixed(5)}';
    return key.putIfAbsent(k, () => key.length);
  });
  for (var t = 0; t < idx.length; t += 3) {
    for (var e = 0; e < 3; e++) {
      final a = weld[idx[t + e]], b = weld[idx[t + (e + 1) % 3]];
      if (a == b) fail('degenerate triangle $t');
      final k = a * 1000003 + b;
      directed[k] = (directed[k] ?? 0) + 1;
    }
  }
  for (final MapEntry(key: k, value: c) in directed.entries) {
    expect(c, 1, reason: 'directed edge used $c times');
    final a = k ~/ 1000003, b = k % 1000003;
    expect(directed[b * 1000003 + a], 1, reason: 'edge $a-$b is open');
  }
}

/// Signed volume (divergence theorem); > 0 when faces point outward.
double signedVolume(InflatedMesh m) {
  final p = m.positions;
  var v = 0.0;
  for (var t = 0; t < m.indices.length; t += 3) {
    final a = m.indices[t] * 3, b = m.indices[t + 1] * 3;
    final c = m.indices[t + 2] * 3;
    v +=
        (p[a] * (p[b + 1] * p[c + 2] - p[b + 2] * p[c + 1]) -
            p[a + 1] * (p[b] * p[c + 2] - p[b + 2] * p[c]) +
            p[a + 2] * (p[b] * p[c + 1] - p[b + 1] * p[c])) /
        6;
  }
  return v;
}

void main() {
  final sample = img.decodePng(buildSampleCutoutPng())!;

  group('puffy inflate', () {
    final m = buildInflatedMesh(sample);

    test('is a closed, outward-facing body', () {
      expectWatertight(m);
      expect(signedVolume(m), greaterThan(0));
      expect(m.boundaryVertexCount, greaterThan(50));
    });

    test('feet at the origin, height as requested, symmetric depth', () {
      var minY = double.infinity, maxY = -double.infinity;
      var minZ = double.infinity, maxZ = -double.infinity;
      var minX = double.infinity, maxX = -double.infinity;
      for (var v = 0; v < m.vertexCount; v++) {
        minX = math.min(minX, m.positions[v * 3]);
        maxX = math.max(maxX, m.positions[v * 3]);
        minY = math.min(minY, m.positions[v * 3 + 1]);
        maxY = math.max(maxY, m.positions[v * 3 + 1]);
        minZ = math.min(minZ, m.positions[v * 3 + 2]);
        maxZ = math.max(maxZ, m.positions[v * 3 + 2]);
      }
      expect(minY, closeTo(0, 1e-6));
      expect(maxY, closeTo(1.0, 1e-6));
      expect((minX + maxX).abs(), lessThan(1e-6));
      expect(maxZ, closeTo(-minZ, 1e-6));
      // A round body: thickness comparable to the width, not a flat card.
      expect(m.depth, greaterThan(0.4 * m.width));
      expect(m.depth, lessThan(1.2 * m.width));
    });

    test('front normals face +Z, back normals −Z', () {
      var front = 0, back = 0;
      for (var v = 0; v < m.vertexCount; v++) {
        final z = m.positions[v * 3 + 2];
        final nz = m.normals[v * 3 + 2];
        if (z > 0.05 && nz > 0) front++;
        if (z < -0.05 && nz < 0) back++;
      }
      expect(front, greaterThan(100));
      expect(back, front);
    });

    test('textured with the drawing, UVs inside the image', () {
      expect(m.texture, isNotNull);
      for (final u in m.uvs) {
        expect(u, inInclusiveRange(0, 1));
      }
    });

    test('thin parts are thin (inscribed-disc radius, not global)', () {
      final stick = img.Image(width: 300, height: 300, numChannels: 4);
      img.fillRect(stick, x1: 20, y1: 100, x2: 280, y2: 200, color: img.ColorRgba8(0, 0, 255, 255));
      img.fillRect(stick, x1: 140, y1: 0, x2: 160, y2: 100, color: img.ColorRgba8(0, 0, 255, 255));
      final s = buildInflatedMesh(stick);
      expectWatertight(s);
      // Max |z| among vertices high up in the 20-px antenna vs the body.
      var antenna = 0.0, body = 0.0;
      for (var v = 0; v < s.vertexCount; v++) {
        final y = s.positions[v * 3 + 1], z = s.positions[v * 3 + 2].abs();
        if (y > s.height * 0.8) antenna = math.max(antenna, z);
        if (y < s.height * 0.5) body = math.max(body, z);
      }
      expect(antenna, lessThan(body * 0.45));
    });

    test('deterministic', () {
      final again = buildInflatedMesh(sample);
      expect(again.positions, m.positions);
      expect(again.indices, m.indices);
    });

    test('rejects an empty cut-out', () {
      final empty = img.Image(width: 10, height: 10, numChannels: 4);
      expect(() => buildInflatedMesh(empty), throwsA(isA<EmptyCutoutException>()));
    });
  });

  group('simplified blob', () {
    final m = buildInflatedMesh(sample, options: const InflateOptions.simplified());

    test('low poly, faceted, flat colours, no texture', () {
      expectWatertight(m);
      expect(signedVolume(m), greaterThan(0));
      expect(m.triangleCount, lessThan(400));
      expect(m.flatShaded, isTrue);
      expect(m.texture, isNull);
      final colours = <String>{};
      for (var v = 0; v < m.vertexCount; v++) {
        colours.add(m.colors.sublist(v * 4, v * 4 + 3).map((c) => c.toStringAsFixed(3)).join(','));
      }
      // 3 palette colours × (front, darker back).
      expect(colours.length, lessThanOrEqualTo(6));
    });
  });

  group('GLB', () {
    test('valid container with skin and the five clips', () {
      for (final options in const [InflateOptions(), InflateOptions.simplified()]) {
        final r = buildInflatedGlb(buildSampleCutoutPng(), options: options);
        final doc = GlbDocument.parse(r.glb);
        expect(doc.validate(), isEmpty);
        expect(doc.list('skins').single['joints'], [1, 2, 3]);
        expect(doc.list('animations').map((a) => a['name']), RigClips.all);
        final prim = (doc.list('meshes').single['primitives'] as List).single as Map;
        final attrs = (prim['attributes'] as Map).cast<String, int>();
        expect(attrs.keys, containsAll(['POSITION', 'NORMAL', 'JOINTS_0', 'WEIGHTS_0', 'COLOR_0']));
        // Weights sum to 1.
        final w = doc.floatAccessor(attrs['WEIGHTS_0']!);
        for (var v = 0; v < w.length; v += 4) {
          expect(w[v] + w[v + 1] + w[v + 2] + w[v + 3], closeTo(1, 1e-5));
        }
        expect(attrs.containsKey('TEXCOORD_0'), options.variant == InflateVariant.puffy);
      }
    });

    test('idle loops seamlessly; quaternions are unit length', () {
      final clips = buildRigClips(1.0);
      for (final c in clips) {
        for (final joint in c.poses) {
          for (final p in joint) {
            final q = p.quaternion;
            expect(q.fold<double>(0, (s, x) => s + x * x), closeTo(1, 1e-9));
          }
        }
      }
      final idle = clips.firstWhere((c) => c.name == RigClips.idle);
      for (final joint in idle.poses) {
        expect(joint.first.ty, closeTo(joint.last.ty, 1e-9));
        expect(joint.first.rz, closeTo(joint.last.rz, 1e-9));
        expect(joint.first.sy, closeTo(joint.last.sy, 1e-9));
      }
      // One-shot clips start and (except faint) end at rest.
      for (final c in clips.where((c) => c.name != RigClips.faint)) {
        expect(c.poses[0].first.tz, closeTo(0, 1e-9));
        expect(c.poses[0].last.tz, closeTo(0, 1e-6));
      }
      final faint = clips.firstWhere((c) => c.name == RigClips.faint);
      expect(faint.poses[0].last.rx, lessThan(-70));
    });

    test('512 px cut-out: generation time (printed) stays well under 1 s', () {
      final png = buildLargeSampleCutoutPng();
      // Warm up the JIT once, then measure.
      buildInflatedGlb(png);
      final runs = <InflatedGlb>[for (var i = 0; i < 3; i++) buildInflatedGlb(png)];
      final best = runs.map((r) => r.timings.totalUs).reduce(math.min);
      final simple = buildInflatedGlb(png, options: const InflateOptions.simplified());
      // ignore: avoid_print
      print(
        'inflate 512px: ${runs.last.timings}; best ${best ~/ 1000} ms; '
        '${runs.last.vertexCount} verts / ${runs.last.triangleCount} tris, '
        '${runs.last.glb.length ~/ 1024} KiB | simplified: ${simple.timings}, '
        '${simple.triangleCount} tris, ${simple.glb.length ~/ 1024} KiB',
      );
      expect(best, lessThan(1000000));
    });
  });
}
