import 'dart:ui' as ui;

import 'package:doodle_battle/features/spike25d/anim/clips.dart';
import 'package:doodle_battle/features/spike25d/rig/rig.dart';
import 'package:doodle_battle/features/spike25d/rig/rigged_character.dart';
import 'package:doodle_battle/features/spike25d/render/character_sprite.dart';
import 'package:doodle_battle/features/spike25d/samples25d.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

/// Contact sheet: every sample drawing, its auto-rig, and the procedural
/// clips rendered with Canvas.drawVertices (software Skia in the test, the
/// same path as GLES2 phones). Writes docs/v2_25d/rig_clips.png with
/// SPIKE25D_WRITE_DOCS=1.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rig + clips contact sheet', () async {
    await loadAppFonts();
    final clips = <(String, Anim, double)>[
      ('じっと', Anim.idle, 0.35),
      ('あるく', Anim.walk, 0.12),
      ('こうげき', Anim.swing, 0.3),
      ('ジャンプ', Anim.jump, 0.27),
      ('ためる', Anim.cast, 0.15),
      ('うける', Anim.hit, 0.05),
      ('たおれる', Anim.faint, 1.0),
    ];
    const cell = 150.0;
    final rows = [
      ...Sample25d.values.map((s) => (s.name, sample25dPng(s), false)),
      ('simple', sample25dPng(Sample25d.hero), true),
    ];
    final w = (cell * (clips.length + 1)).toInt();
    final h = (cell * rows.length + 30).toInt();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFF8E7),
    );
    label(c, 'リグ', const Offset(50, 4));
    for (final (i, cl) in clips.indexed) {
      label(c, cl.$1, Offset(cell * (i + 1) + 40, 4));
    }
    for (final (r, row) in rows.indexed) {
      final data = buildRiggedCharacterFromPng(
        row.$2,
        options: BuildOptions(simplified: row.$3),
      );
      final sprite = await CharacterSprite.create(data);
      final y0 = 30 + r * cell;
      final scale = (cell * 0.72) / sprite.height.clamp(1, 1e9);
      final s2 = (cell * 0.8) / sprite.width;
      final sc = scale < s2 ? scale : s2;
      // Rig overlay cell.
      final feet0 = Offset(cell / 2, y0 + cell - 14);
      sprite.draw(c, Anim.idle, 0, feet: feet0, scale: sc, screenDir: 1);
      _drawRig(c, data.rig, feet0, sc, data);
      for (final (i, cl) in clips.indexed) {
        final feet = Offset(cell * (i + 1) + cell / 2, y0 + cell - 14);
        c.drawOval(
          Rect.fromCenter(
            center: feet,
            width: sprite.width * sc * 0.7,
            height: 12,
          ),
          Paint()..color = const Color(0x33000000),
        );
        sprite.draw(c, cl.$2, cl.$3, feet: feet, scale: sc, screenDir: 1);
      }
      sprite.dispose();
    }
    await savePicture(
      rec.endRecording(),
      w,
      h,
      renderDir() == null ? null : '${renderDir()}/rig_clips.png',
    );
  });
}

void _drawRig(
  Canvas c,
  CharacterRig rig,
  Offset feet,
  double s,
  RiggedCharacter d,
) {
  Offset m(V2 p) => Offset(
    feet.dx + (p.x - rig.root.x) * s,
    feet.dy + (p.y - rig.groundY) * s,
  );
  final colors = {
    LimbKind.head: const Color(0xFFE84393),
    LimbKind.arm: const Color(0xFFFF6B35),
    LimbKind.leg: const Color(0xFF2E9E44),
    LimbKind.tail: const Color(0xFF00A0A0),
    LimbKind.extra: const Color(0xFF8E7A00),
  };
  final bone = Paint()
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  c.drawLine(m(rig.root), m(rig.chest), bone..color = const Color(0xFFD7263D));
  for (final l in rig.limbs) {
    bone.color = colors[l.kind]!;
    c.drawLine(m(l.base), m(l.mid), bone);
    c.drawLine(m(l.mid), m(l.tip), bone);
    c.drawCircle(m(l.tip), 4, Paint()..color = colors[l.kind]!);
  }
  c.drawCircle(m(rig.root), 4, Paint()..color = const Color(0xFFD7263D));
  label(
    c,
    '${d.triangleCount}△',
    Offset(feet.dx - 70, feet.dy - 130),
    size: 11,
  );
}
