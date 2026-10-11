import 'dart:typed_data';

import 'package:doodle_battle/domain/cosmetics.dart';
import 'package:doodle_battle/features/puppet/anim/clips.dart';
import 'package:doodle_battle/features/puppet/anim/skinner.dart';
import 'package:doodle_battle/features/puppet/mesh/puppet_mesh.dart';
import 'package:doodle_battle/features/puppet/puppet_look.dart';
import 'package:doodle_battle/features/puppet/puppet_parts.dart';
import 'package:doodle_battle/features/puppet/rig/auto_rig.dart';
import 'package:doodle_battle/features/puppet/rig/bin_mask.dart';
import 'package:doodle_battle/features/puppet/rig/character_rig.dart';
import 'package:doodle_battle/features/puppet/rig/limb_hints.dart';
import 'package:doodle_battle/features/puppet/samples.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stroke_figures.dart';

void main() {
  group('strokes from the drawing tool', () {
    test('arms drawn touching the body are found with strokes', () {
      // Synthetic in-app drawings (40 figures, 4 arm poses). Prints the
      // with / without numbers quoted in docs/PUPPET.md §2.4.
      final stats = <String, List<int>>{};
      for (var seed = 0; seed < 40; seed++) {
        final f = strokeFigure(seed);
        final plain = autoRig(f.mask).rig;
        final withStrokes = autoRig(f.mask, strokes: f.strokes).rig;
        final s = stats.putIfAbsent(f.pose.name, () => [0, 0, 0]);
        s[0]++;
        if (handError(plain, f) <= 0.1) s[1]++;
        if (handError(withStrokes, f) <= 0.1) s[2]++;
        expect(withStrokes.source, RigSource.strokes);
      }
      // ignore: avoid_print
      print('stroke figures (n, hands≤10% silhouette, with strokes): $stats');
      for (final pose in ['hips', 'along']) {
        final s = stats[pose]!;
        expect(s[2], greaterThan(s[1]), reason: pose);
        expect(s[2] / s[0], greaterThanOrEqualTo(0.8), reason: pose);
      }
      for (final pose in ['out', 'up']) {
        final s = stats[pose]!;
        expect(s[2], greaterThanOrEqualTo(s[1] - 1), reason: 'no regression');
      }
    });

    test('long straight strokes and closed sausages become hints', () {
      final hints = strokeLimbHints([
        const HintStroke([P2(0, 0), P2(50, 0), P2(100, 2)], 6),
        // A closed elongated outline.
        HintStroke([
          for (var i = 0; i <= 20; i++)
            P2(
              200 + 60 * (i <= 10 ? i / 10 : (20 - i) / 10),
              i <= 10 ? 0 : 14,
            ),
        ], 4),
        // A scribble (not straight) is not a limb.
        const HintStroke([P2(0, 0), P2(30, 30), P2(0, 30), P2(30, 0)], 6),
      ], 300);
      expect(hints, hasLength(2));
      expect(hints.first.fromStroke, isTrue);
      expect(hints.first.length, closeTo(100, 3));
    });
  });

  group('picture lines (ink hints)', () {
    test('an outlined arm against an outlined body is a region hint', () {
      const w = 200, h = 260;
      final rgba = Uint8List(w * h * 4);
      final mask = BinMask(w, h);
      void px(int x, int y, int v) {
        final i = y * w + x;
        mask.data[i] = 1;
        rgba
          ..[i * 4] = v
          ..[i * 4 + 1] = v
          ..[i * 4 + 2] = v
          ..[i * 4 + 3] = 255;
      }

      void box(int x0, int y0, int x1, int y1) {
        for (var y = y0; y <= y1; y++) {
          for (var x = x0; x <= x1; x++) {
            final edge = x - x0 < 3 || x1 - x < 3 || y - y0 < 3 || y1 - y < 3;
            px(x, y, edge ? 20 : 250);
          }
        }
      }

      box(60, 40, 140, 220); // body
      box(141, 60, 170, 200); // arm hanging right next to it (shares edge)
      final hints = inkLimbHints(rgba, mask);
      expect(
        hints.any((hh) => hh.a.x > 140 && hh.b.x > 140 && hh.length > 90),
        isTrue,
        reason: '$hints',
      );
    });
  });

  group('silhouette fixes', () {
    test('a detached hand near the body is bridged, far doodles dropped', () {
      final m = BinMask(100, 100);
      m.line(20, 50, 60, 50, 4); // body / arm
      m.line(66, 50, 72, 50, 3); // hand, 2 px gap
      m.line(95, 5, 97, 5, 1); // a speck far away
      final out = m.largestBridged(maxGap: 8);
      expect(out.at(70, 50), isTrue);
      expect(out.at(63, 50), isTrue, reason: 'bridge');
      expect(out.at(96, 5), isFalse);
    });

    test('spike rules are still available for measurements', () {
      final f = strokeFigure(0, pose: ArmPose.out);
      final spike = autoRig(f.mask, o: AutoRigOptions.spike).rig;
      final now = autoRig(f.mask).rig;
      expect(spike.of(LimbKind.leg).length, now.of(LimbKind.leg).length);
    });
  });

  group('drawn parts become appendages', () {
    final base = buildPuppetMeshFromPng(samplePng(Sample.hero)).rig;
    // The rig in the base drawing's own pixels (remove the sticker border).
    final rig = base.shifted(-6, -6, padW: -12, padH: -12);
    final head = rig.head!;

    test('hat follows the head, sword the hand, wings flap', () {
      final arm = rig.limbs.indexWhere((l) => l.kind == LimbKind.arm);
      final hand = rig.limbs[arm].tip;
      final out = rigWithParts(
        rig,
        compositeW: rig.width + 40,
        compositeH: rig.height + 40,
        baseLeft: 20,
        baseTop: 20,
        k: 1,
        parts: [
          PartPlacement(
            id: 'hat',
            type: PartType.hat,
            left: head.tip.x - 20 + 20,
            top: 0,
            right: head.tip.x + 20 + 20,
            bottom: head.tip.y - 20 + 20,
          ),
          PartPlacement(
            id: 'sword',
            type: PartType.weapon,
            left: hand.x + 20,
            top: hand.y - 60 + 20,
            right: hand.x + 15 + 20,
            bottom: hand.y + 20,
          ),
          PartPlacement(
            id: 'wings',
            type: PartType.wings,
            left: rig.chest.x - 80 + 20,
            top: rig.chest.y - 30 + 20,
            right: rig.chest.x - 10 + 20,
            bottom: rig.chest.y + 30 + 20,
          ),
        ],
      );
      expect(out.validate(), isNull);
      final hat = out.limbs.firstWhere((l) => l.part == 'hat');
      final sword = out.limbs.firstWhere((l) => l.part == 'sword');
      final wing = out.limbs.firstWhere((l) => l.part == 'wings');
      expect(hat.kind, LimbKind.extra);
      expect(out.limbs[hat.attach!].kind, LimbKind.head);
      expect(sword.kind, LimbKind.item);
      expect(sword.attach, arm);
      expect(wing.kind, LimbKind.wing);
      expect(out.head!.tip.x, closeTo(head.tip.x + 20, 0.01));
      // Bones: the hat's bone hangs from the head bone.
      final bones = bonesOf(out);
      final hatBone = bones.firstWhere((b) => b.limb == out.limbs.indexOf(hat));
      expect(bones[hatBone.parent].limb, out.limbs.indexOf(out.head!));
    });

    test('moving the head moves the attached hat', () {
      final c = buildPuppetMeshFromPng(samplePng(Sample.hero));
      final r = c.rig.copy();
      final h = r.limbs.indexWhere((l) => l.kind == LimbKind.head);
      r.limbs.add(
        RigLimb(
          LimbKind.extra,
          r.limbs[h].tip,
          r.limbs[h].tip - const P2(0, 10),
          r.limbs[h].tip - const P2(0, 20),
          attach: h,
        ),
      );
      final m = buildPuppetMeshFromPng(
        samplePng(Sample.hero),
        rig: r.shifted(-6, -6, padW: -12, padH: -12),
      );
      final sk = Skinner(m);
      final p = Pose(m.rig.limbs.length)..a[h] = 0.8;
      sk.skin(p, const Affine.identity());
      final hat = m.rig.limbs.length - 1;
      final tip = sk.limbTip(hat, m.rig.limbs[hat]);
      expect(P2(tip.$1, tip.$2).dist(m.rig.limbs[hat].tip), greaterThan(5));
    });
  });

  test('look: hidden late bloomer simple until Lv50, でんせつ for all', () {
    expect(PuppetLook.of(level: 49, lateBloomer: true).simple, isTrue);
    expect(PuppetLook.of(level: 49, lateBloomer: true).legend, isFalse);
    expect(PuppetLook.of(level: 50, lateBloomer: true).simple, isFalse);
    expect(PuppetLook.of(level: 50, lateBloomer: true).legend, isTrue);
    expect(
      PuppetLook.of(level: 50, lateBloomer: true),
      PuppetLook.of(level: 50),
      reason: 'indistinguishable after the rebuild',
    );
    expect(PuppetLook.of(level: 12).fxScale, 1);
    // The simple look animates with the limbless clips.
    final c = buildPuppetMeshFromPng(
      samplePng(Sample.hero),
      options: const BuildOptions(simplified: true),
    );
    final ctx = AnimContext(c.rig, limited: true);
    expect(ctx.physicalClip(0), anyOf(Anim.tackle, Anim.jump));
  });
}
