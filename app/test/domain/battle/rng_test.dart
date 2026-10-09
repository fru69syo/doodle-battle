import 'package:doodle_battle/domain/battle/rng.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imul32 matches Math.imul semantics', () {
    expect(imul32(0xFFFFFFFF, 0xFFFFFFFF), 1);
    expect(imul32(0x6D2B79F5, 0x6D2B79F5), 0xD4678479);
    expect(imul32(-1, 5), 0xFFFFFFFB);
    expect(imul32(0x12345678, 0x9ABCDEF0), 0x242D2080);
  });

  test('mulberry32 matches the canonical JS implementation', () {
    // Produced by the canonical JS mulberry32 (`>>> 0` on the output).
    final r0 = Mulberry32(0);
    expect(
      [for (var i = 0; i < 3; i++) r0.nextUint32()],
      [0x4434B462, 0x00159C37, 0x39285B08],
    );
    final r1 = Mulberry32(0xDEADBEEF);
    expect(
      [for (var i = 0; i < 3; i++) r1.nextUint32()],
      [0xF0FD995A, 0x4466F0CF, 0xC5A3FA66],
    );
  });

  test('state round-trips', () {
    final r = Mulberry32(1234);
    for (var i = 0; i < 17; i++) {
      r.nextUint32();
    }
    final resumed = Mulberry32(r.state);
    for (var i = 0; i < 10; i++) {
      expect(resumed.nextUint32(), r.nextUint32());
    }
  });

  test('nextInt range and validation', () {
    final r = Mulberry32(9);
    for (var i = 0; i < 2000; i++) {
      expect(r.nextInt(7), inInclusiveRange(0, 6));
    }
    expect(() => r.nextInt(0), throwsArgumentError);
  });

  test('fnv1a32 known values', () {
    expect(fnv1a32(''), 0x811C9DC5);
    expect(fnv1a32('a'), 0xE40C292C);
    expect(fnv1a32('foobar'), 0xBF9CF968);
  });

  test('deriveSeed gives distinct streams', () {
    final s = {for (var i = 0; i < 8; i++) deriveSeed(42, i)};
    expect(s.length, 8);
  });
}
