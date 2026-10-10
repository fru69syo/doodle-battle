import 'dart:math' as math;
import 'dart:ui';

import 'package:doodle_battle/domain/cosmetics.dart';
import 'package:doodle_battle/features/drawing_loop/parts/part_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher near(Offset o, [double eps = 1e-9]) =>
    predicate<Offset>((p) => (p - o).distance < eps, 'near $o');

void main() {
  group('partToBase', () {
    test('centre lands on (cx, cy) of the base', () {
      const t = PartTransform(cx: 0.25, cy: 0.75, scale: 0.5, rotation: 1.1);
      final m = partToBase(t, baseW: 200, baseH: 100, partW: 40, partH: 20);
      expect(m.apply(const Offset(20, 10)), near(const Offset(50, 75)));
    });

    test('scale: longest side becomes scale × base longest side', () {
      const t = PartTransform(cx: 0.5, cy: 0.5, scale: 0.5);
      final m = partToBase(t, baseW: 200, baseH: 100, partW: 40, partH: 20);
      final b = m.boundsOf(40, 20);
      expect(b.width, closeTo(100, 1e-9)); // 0.5 × 200
      expect(b.height, closeTo(50, 1e-9)); // aspect kept
      expect(b.center, near(const Offset(100, 50)));
      final boosted = partToBase(
        t,
        baseW: 200,
        baseH: 100,
        partW: 40,
        partH: 20,
        scaleBoost: 1.15,
      ).boundsOf(40, 20);
      expect(boosted.width, closeTo(115, 1e-9));
      expect(boosted.center, near(const Offset(100, 50)));
    });

    test('rotation is clockwise on screen (y down)', () {
      const t = PartTransform(
        cx: 0.5,
        cy: 0.5,
        scale: 1,
        rotation: math.pi / 2,
      );
      final m = partToBase(t, baseW: 100, baseH: 100, partW: 100, partH: 100);
      // The part's right-middle point goes to the bottom-middle.
      expect(m.apply(const Offset(100, 50)), near(const Offset(50, 100)));
      // Its top-middle goes to the right-middle.
      expect(m.apply(const Offset(50, 0)), near(const Offset(100, 50)));
      final b = m.boundsOf(100, 100);
      expect(b.width, closeTo(100, 1e-9));
    });

    test('a 45° square grows its bounds by √2', () {
      const t = PartTransform(
        cx: 0.5,
        cy: 0.5,
        scale: 0.5,
        rotation: math.pi / 4,
      );
      final b = partToBase(
        t,
        baseW: 100,
        baseH: 100,
        partW: 10,
        partH: 10,
      ).boundsOf(10, 10);
      expect(b.width, closeTo(50 * math.sqrt2, 1e-9));
      expect(b.height, closeTo(50 * math.sqrt2, 1e-9));
    });

    test('inverse round-trips', () {
      const t = PartTransform(cx: -0.2, cy: 1.3, scale: 0.7, rotation: -2.4);
      final m = partToBase(t, baseW: 321, baseH: 123, partW: 57, partH: 91);
      final inv = m.inverse();
      for (final p in const [Offset(0, 0), Offset(57, 91), Offset(13.5, 70)]) {
        expect(inv.apply(m.apply(p)), near(p, 1e-6));
      }
      expect(m.determinant, greaterThan(0), reason: 'no mirroring');
    });
  });

  group('PartTransform', () {
    test('clamped keeps parts grabbable and normalises the angle', () {
      const t = PartTransform(cx: 5, cy: -5, scale: 10, rotation: 7);
      final c = t.clamped();
      expect(c.cx, 1 + PartTransform.maxOverhang);
      expect(c.cy, -PartTransform.maxOverhang);
      expect(c.scale, PartTransform.maxScale);
      expect(c.rotation, closeTo(7 - 2 * math.pi, 1e-9));
      expect(
        const PartTransform(cx: 0, cy: 0, scale: 0.01).clamped().scale,
        PartTransform.minScale,
      );
      expect(
        const PartTransform(
          cx: 0,
          cy: 0,
          scale: 1,
          rotation: -4,
        ).clamped().rotation,
        closeTo(-4 + 2 * math.pi, 1e-9),
      );
    });

    test('JSON round-trip', () {
      const t = PartTransform(
        cx: 0.1,
        cy: 0.9,
        scale: 0.3,
        rotation: 0.5,
        behind: true,
      );
      expect(PartTransform.fromJson(t.toJson()), t);
    });

    test('default placements are inside the editable range', () {
      for (final type in PartType.values) {
        for (var i = 0; i < 3; i++) {
          final t = defaultPlacement(type, index: i);
          expect(t.clamped(), t, reason: '$type $i');
        }
      }
      expect(defaultPlacement(PartType.wings).behind, isTrue);
      expect(defaultPlacement(PartType.tail).behind, isTrue);
      expect(defaultPlacement(PartType.hat).behind, isFalse);
      expect(defaultPlacement(PartType.hat).cy, lessThan(0.2));
    });
  });

  group('EditorGeometry', () {
    final g = EditorGeometry(
      canvas: const Size(400, 400),
      baseW: 200,
      baseH: 100,
      baseFraction: 0.5,
    );

    test('base is centred at the given fraction', () {
      expect(g.scale, 1.0); // 0.5 × 400 / 200
      expect(g.baseRect, const Rect.fromLTWH(100, 150, 200, 100));
      expect(
        g.partCenter(const PartTransform(cx: 0, cy: 1, scale: 0.3)),
        const Offset(100, 250),
      );
    });

    test('part size matches the compositor (same scale rule)', () {
      const t = PartTransform(cx: 0.5, cy: 0.5, scale: 0.5);
      expect(g.partSize(t, 40, 20), const Size(100, 50));
      final b = partToBase(
        t,
        baseW: 200,
        baseH: 100,
        partW: 40,
        partH: 20,
      ).boundsOf(40, 20);
      expect(g.partSize(t, 40, 20).width, closeTo(b.width * g.scale, 1e-9));
    });

    test('gestures: pan, pinch and twist', () {
      const t = PartTransform(cx: 0.5, cy: 0.5, scale: 0.5);
      final moved = g.applyGesture(t, pan: const Offset(20, -10));
      expect(moved.cx, closeTo(0.6, 1e-9)); // 20 / 200
      expect(moved.cy, closeTo(0.4, 1e-9)); // 10 / 100
      final pinched = g.applyGesture(t, scaleFactor: 1.5, rotationDelta: 0.4);
      expect(pinched.scale, closeTo(0.75, 1e-9));
      expect(pinched.rotation, closeTo(0.4, 1e-9));
      final far = g.applyGesture(t, pan: const Offset(10000, 10000));
      expect(far, far.clamped());
      expect(far.cx, 1 + PartTransform.maxOverhang);
      expect(g.applyGesture(t, scaleFactor: 0).scale, PartTransform.minScale);
    });

    test('hit test prefers the front layer and the newest part', () {
      const back = PartTransform(cx: 0.5, cy: 0.5, scale: 0.5, behind: true);
      const front = PartTransform(cx: 0.5, cy: 0.5, scale: 0.2);
      const other = PartTransform(cx: 0.0, cy: 0.0, scale: 0.2);
      final parts = [(back, 40, 20), (front, 10, 10), (other, 10, 10)];
      expect(g.hitTest(const Offset(200, 200), parts), 1);
      expect(g.hitTest(const Offset(240, 200), parts), 0); // only the wings
      expect(g.hitTest(const Offset(100, 150), parts), 2);
      expect(g.hitTest(const Offset(390, 10), parts), isNull);
      // Rotated rectangle: a long thin part rotated 90° is hit vertically.
      const thin = PartTransform(
        cx: 0.5,
        cy: 0.5,
        scale: 0.5,
        rotation: math.pi / 2,
      );
      expect(g.hitTest(const Offset(200, 245), [(thin, 100, 4)]), 0);
      expect(g.hitTest(const Offset(245, 200), [(thin, 100, 4)]), isNull);
    });
  });
}
