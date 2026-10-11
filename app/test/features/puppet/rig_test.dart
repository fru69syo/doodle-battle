import 'dart:convert';

import 'package:doodle_battle/domain/rig_blob.dart';
import 'package:doodle_battle/features/puppet/anim/clips.dart';
import 'package:doodle_battle/features/puppet/anim/skinner.dart';
import 'package:doodle_battle/features/puppet/editor/rig_edits.dart';
import 'package:doodle_battle/features/puppet/mesh/puppet_mesh.dart';
import 'package:doodle_battle/features/puppet/puppet_store.dart';
import 'package:doodle_battle/features/puppet/rig/auto_rig.dart';
import 'package:doodle_battle/features/puppet/rig/bin_mask.dart';
import 'package:doodle_battle/features/puppet/rig/character_rig.dart';
import 'package:doodle_battle/features/puppet/rig/skeleton.dart';
import 'package:doodle_battle/features/puppet/samples.dart';
import 'package:flutter_test/flutter_test.dart';

int count(CharacterRig r, LimbKind k) => r.of(k).length;

void main() {
  final hero = buildPuppetMeshFromPng(samplePng(Sample.hero));

  group('auto-rig', () {
    test('person: head, 2 arms, 2 legs in the right places', () {
      final r = hero.rig;
      expect(count(r, LimbKind.head), 1);
      expect(count(r, LimbKind.arm), 2);
      expect(count(r, LimbKind.leg), 2);
      final head = r.head!;
      expect(head.tip.y, lessThan(r.chest.y));
      for (final l in r.of(LimbKind.leg)) {
        expect(l.tip.y, greaterThan(r.root.y));
      }
      final arms = r.of(LimbKind.arm).toList()
        ..sort((a, b) => a.tip.x.compareTo(b.tip.x));
      expect(arms.first.tip.x, lessThan(r.root.x));
      expect(arms.last.tip.x, greaterThan(r.root.x));
      expect(r.facing, 0, reason: 'frontal drawings are never mirrored');
    });

    test('stick figure (1-px lines + circle head)', () {
      final r = buildPuppetMeshFromPng(samplePng(Sample.stick)).rig;
      expect(count(r, LimbKind.head), 1);
      expect(count(r, LimbKind.arm), 2);
      expect(count(r, LimbKind.leg), 2);
    });

    test('dog in profile: 4 legs, head on the right, tail', () {
      final r = buildPuppetMeshFromPng(samplePng(Sample.dog)).rig;
      expect(count(r, LimbKind.leg), 4);
      expect(count(r, LimbKind.head), 1);
      expect(count(r, LimbKind.tail), 1);
      expect(r.facing, 1);
    });

    test('blob without limbs falls back to a body-only rig', () {
      final c = buildPuppetMeshFromPng(samplePng(Sample.blob));
      expect(count(c.rig, LimbKind.arm) + count(c.rig, LimbKind.leg), 0);
    });

    test('empty mask gives a blob rig, no crash', () {
      final r = autoRig(BinMask(40, 30)).rig;
      expect(r.isBlob, isTrue);
    });

    test('deterministic and fast', () {
      final a = buildPuppetMeshFromPng(samplePng(Sample.hero));
      expect(jsonEncode(a.rig.toJson()), jsonEncode(hero.rig.toJson()));
      expect(a.indices, hero.indices);
      final sw = Stopwatch()..start();
      buildPuppetMeshFromPng(samplePng(Sample.dog));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('skeleton of a plus sign has 4 leaves', () {
      final m = BinMask(60, 60);
      for (var i = 10; i < 50; i++) {
        for (var k = 27; k < 33; k++) {
          m.data[i * 60 + k] = 1;
          m.data[k * 60 + i] = 1;
        }
      }
      final g = SkeletonGraph.build(m, m.insideDistance());
      expect(g.nodes.where((n) => n.isEnd).length, 4);
    });
  });

  group('rig JSON', () {
    test('round trip and size', () {
      final j = jsonEncode(hero.rig.toJson());
      final back = CharacterRig.fromJson(
        (jsonDecode(j) as Map).cast<String, Object?>(),
      );
      expect(jsonEncode(back.toJson()), j);
      expect(j.length, lessThan(CharacterRig.maxJsonBytes));
      expect(back.validate(), isNull);
    });

    test('stored form is the CharacterV2 rig blob (rig_blob.dart)', () {
      final blob = hero.rig.toBlob();
      expect(blob, isNotNull);
      expect(validateRigJson(blob), isNotNull);
      expect(rigProblem(blob), isNull);
      final back = CharacterRig.fromBlob(blob)!;
      expect(back.encode(), hero.rig.encode());
      // Drawn-part limbs are not stored; strokes rigs are stored as auto.
      final withPart = hero.rig.copy(source: RigSource.strokes)
        ..limbs.add(
          RigLimb(
            LimbKind.wing,
            const P2(1, 1),
            const P2(2, 2),
            const P2(3, 3),
            part: 'w1',
          ),
        );
      expect(withPart.toBlob()!['limbs'], hasLength(hero.rig.limbs.length));
      expect(withPart.toBlob()!['source'], 'auto');
      expect(withPart.cacheKey, isNot(hero.rig.cacheKey));
      expect(CharacterRig.fromBlob(null), isNull);
      expect(CharacterRig.fromBlob({'v': 9}), isNull);
    });

    test('v1 (spike) JSON still loads', () {
      final v1 = {
        'v': 1,
        'size': [100, 120],
        'root': [50, 90],
        'chest': [50, 50],
        'limbs': [
          {
            'kind': 'arm',
            'base': [50, 50],
            'mid': [70, 55],
            'tip': [90, 60],
            'edited': true,
          },
        ],
        'source': 'edited',
      };
      final r = CharacterRig.fromJson(v1);
      expect(r.limbs.single.kind, LimbKind.arm);
      expect(r.limbs.single.edited, isTrue);
      expect(r.source, RigSource.edited);
    });

    test('validation rejects bad rigs (fallback to auto-rig)', () {
      Map<String, Object?> j() =>
          (jsonDecode(hero.rig.encode()) as Map).cast<String, Object?>();
      expect(CharacterRig.tryDecode(hero.rig.encode()), isNotNull);
      expect(CharacterRig.tryDecode('nope'), isNull);
      expect(CharacterRig.tryDecode(null), isNull);
      final far = j()..['root'] = [1e6, 0];
      expect(CharacterRig.tryDecode(jsonEncode(far)), isNull);
      final many = j()
        ..['limbs'] = [
          for (var i = 0; i < 13; i++)
            {
              'k': 'x',
              'b': [1, 1],
              't': [2, 2],
            },
        ];
      expect(CharacterRig.tryDecode(jsonEncode(many)), isNull);
      final cyc = j()
        ..['limbs'] = [
          {
            'k': 'x',
            'b': [1, 1],
            't': [2, 2],
            'p': 0,
          },
        ];
      expect(CharacterRig.tryDecode(jsonEncode(cyc)), isNull, reason: 'self');
      final kind = j()
        ..['limbs'] = [
          {
            'k': 'zz',
            'b': [1, 1],
            't': [2, 2],
          },
        ];
      expect(CharacterRig.tryDecode(jsonEncode(kind)), isNull);
      expect(CharacterRig.tryDecode('x' * 3000), isNull, reason: '> 2 KB');
    });

    test('the largest possible rig still fits in 2 KB', () {
      final r = CharacterRig(
        width: 4095.5,
        height: 4095.5,
        root: const P2(-1000.5, 4000.5),
        chest: const P2(-1000.5, 3000.5),
        limbs: [
          for (var i = 0; i < CharacterRig.maxLimbs; i++)
            RigLimb(
              LimbKind.item,
              const P2(-1234.5, -1234.5),
              const P2(-1234.5, -1234.5),
              const P2(-1234.5, -1234.5),
              edited: true,
              attach: i == 0 ? null : 0,
              part: 'p_1234567890123456',
            ),
        ],
        ground: 4000.5,
        source: RigSource.edited,
      );
      expect(r.encode().length, lessThan(CharacterRig.maxJsonBytes));
    });

    test('unknown version is rejected', () {
      expect(
        () => CharacterRig.fromJson({'v': 99}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('mesh and skinning', () {
    test('2–4k triangles, 16-bit indices, weights sum to 1', () {
      expect(hero.triangleCount, inInclusiveRange(1500, 4000));
      expect(hero.vertexCount, lessThan(65536));
      for (var v = 0; v < hero.vertexCount; v++) {
        var s = 0.0;
        for (var k = 0; k < 4; k++) {
          s += hero.boneW[v * 4 + k];
        }
        expect(s, closeTo(1, 1e-4));
      }
    });

    test('rest pose with identity placement returns the rest mesh', () {
      final sk = Skinner(hero);
      final p = Pose(hero.rig.limbs.length);
      sk.skin(p, const Affine.identity());
      for (var i = 0; i < hero.rest.length; i++) {
        expect(sk.out[i], closeTo(hero.rest[i], 1e-3));
      }
    });

    test('raising an arm moves its hand, not the feet', () {
      final sk = Skinner(hero);
      final ctx = AnimContext(hero.rig);
      final p = Pose(hero.rig.limbs.length);
      final arm = hero.rig.limbs.indexWhere((l) => l.kind == LimbKind.arm);
      final leg = hero.rig.limbs.indexWhere((l) => l.kind == LimbKind.leg);
      p.a[arm] = 1.2;
      sk.skin(p, const Affine.identity());
      final hand = sk.limbTip(arm, hero.rig.limbs[arm]);
      final foot = sk.limbTip(leg, hero.rig.limbs[leg]);
      final l = hero.rig.limbs;
      expect((P2(hand.$1, hand.$2) - l[arm].tip).length, greaterThan(20));
      expect((P2(foot.$1, foot.$2) - l[leg].tip).length, lessThan(0.5));
      expect(ctx.hasArms, isTrue);
    });

    test('every clip evaluates for every sample (finite poses)', () {
      for (final s in Sample.values) {
        final c = buildPuppetMeshFromPng(samplePng(s));
        final sk = Skinner(c);
        final ctx = AnimContext(c.rig);
        final p = Pose(c.rig.limbs.length);
        for (final a in Anim.values) {
          for (final t in [0.0, 0.3, 0.9]) {
            evaluateAnim(a, t, ctx, 1, p);
            sk.skin(p, const Affine.identity());
            expect(sk.out.every((v) => v.isFinite), isTrue, reason: '$s $a');
          }
        }
      }
    });

    test('simplified look: coarse, body only, few colours', () {
      final c = buildPuppetMeshFromPng(
        samplePng(Sample.hero),
        options: const BuildOptions(simplified: true),
      );
      expect(c.rig.isBlob, isTrue);
      expect(c.triangleCount, lessThan(400));
      final colours = <int>{};
      for (var i = 0; i < c.textureRgba.length; i += 4) {
        if (c.textureRgba[i + 3] == 0) continue;
        colours.add(
          c.textureRgba[i] << 16 |
              c.textureRgba[i + 1] << 8 |
              c.textureRgba[i + 2],
        );
      }
      expect(colours.length, lessThanOrEqualTo(4));
    });
  });

  group('editor edits', () {
    test('move a hand, add a tail, remove it, store', () async {
      final r0 = hero.rig;
      final arm = r0.limbs.indexWhere((l) => l.kind == LimbKind.arm);
      final r1 = RigEdits.moveTip(r0, arm, const P2(10, 10));
      expect(r1.limbs[arm].tip, isA<P2>());
      expect(r1.limbs[arm].tip.x, 10);
      expect(r1.limbs[arm].edited, isTrue);
      expect(r1.source, RigSource.edited);
      expect(r0.limbs[arm].tip.x, isNot(10), reason: 'edits copy');
      final r2 = RigEdits.addLimb(r1, LimbKind.tail);
      expect(count(r2, LimbKind.tail), 1);
      final r3 = RigEdits.removeLimb(r2, r2.limbs.length - 1);
      expect(count(r3, LimbKind.tail), 0);
      final store = InMemoryPuppetStore();
      await store.saveRig('abc', r1);
      final back = CharacterRig.tryDecode(await store.loadRigJson('abc'));
      expect(back!.limbs[arm].tip.x, 10);
      // The edited rig drives the build.
      final c = buildPuppetMeshFromPng(samplePng(Sample.hero), rig: back);
      expect(c.rig.limbs[arm].tip.x, 10 + 6, reason: 'shifted by border');
    });
  });
}
