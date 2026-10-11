import 'dart:ui' as ui;

import 'dart:typed_data';

import 'package:doodle_battle/features/puppet/anim/clips.dart';
import 'package:doodle_battle/features/puppet/mesh/puppet_mesh.dart';
import 'package:doodle_battle/features/puppet/render/aura.dart';
import 'package:doodle_battle/features/puppet/render/puppet_sprite.dart';
import 'package:doodle_battle/features/puppet/rig/character_rig.dart';
import 'package:doodle_battle/features/puppet/rig/limb_hints.dart';
import 'package:doodle_battle/features/puppet/samples.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';
import 'stroke_figures.dart';

/// Contact sheet: every sample drawing, its auto-rig, and the procedural
/// clips rendered with Canvas.drawVertices (software Skia in the test, the
/// same path as GLES2 phones). Writes docs/v2_25d/rig_clips.png with
/// PUPPET_WRITE_DOCS=1.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rig + clips contact sheet', () async {
    await loadAppFonts();
    final clips = <(String, Anim, double)>[
      ('じっと', Anim.idle, 0.35),
      ('あるく', Anim.walk, 0.12),
      ('ぴょん', Anim.hop, 0.2),
      ('パンチ', Anim.swing, 0.3),
      ('キック', Anim.kick, 0.3),
      ('たいあたり', Anim.tackle, 0.3),
      ('ジャンプ', Anim.jump, 0.27),
      ('ためる', Anim.cast, 0.15),
      ('うつ', Anim.shoot, 0.25),
      ('うける', Anim.hit, 0.05),
      ('たおれる', Anim.faint, 1.0),
      ('かち', Anim.victory, 0.27),
      ('ぷにっ', Anim.squash, 0.1),
      ('ぷるぷる', Anim.wobble, 0.2),
    ];
    const cell = 120.0;
    // In-app drawing with hands on the hips (stroke rig).
    final fig = strokeFigure(1, pose: ArmPose.hips);
    final figPng = _png(fig.rgba, fig.mask.w, fig.mask.h);
    final rows = <(String, Uint8List, bool, List<HintStroke>?, bool)>[
      ...Sample.values.map((s) => (s.name, samplePng(s), false, null, false)),
      ('strokes', figPng, false, fig.strokes, false),
      ('simple', samplePng(Sample.hero), true, null, false),
      ('でんせつ', samplePng(Sample.hero), false, null, true),
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
      final data = buildPuppetMeshFromPng(
        row.$2,
        strokes: row.$4,
        options: BuildOptions(simplified: row.$3),
      );
      final sprite = await PuppetSprite.create(data);
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
        if (row.$5) {
          paintLegendAura(
            c,
            feet.translate(0, -sprite.height * sc * 0.5),
            sprite.height * sc * 0.62,
            cl.$3 + i,
          );
        }
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

void _drawRig(Canvas c, CharacterRig rig, Offset feet, double s, PuppetMesh d) {
  Offset m(P2 p) => Offset(
    feet.dx + (p.x - rig.root.x) * s,
    feet.dy + (p.y - rig.groundY) * s,
  );
  final colors = {
    LimbKind.head: const Color(0xFFE84393),
    LimbKind.arm: const Color(0xFFFF6B35),
    LimbKind.leg: const Color(0xFF2E9E44),
    LimbKind.tail: const Color(0xFF00A0A0),
    LimbKind.extra: const Color(0xFF8E7A00),
    LimbKind.wing: const Color(0xFF6C7BFF),
    LimbKind.item: const Color(0xFF6D6D6D),
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

/// Black-ink RGBA → PNG (the stroke figure as a cut-out).
Uint8List _png(Uint8List rgba, int w, int h) {
  final out = Uint8List.fromList(rgba);
  for (var i = 0; i < w * h; i++) {
    if (out[i * 4 + 3] != 0) {
      out[i * 4] = 40;
      out[i * 4 + 1] = 40;
      out[i * 4 + 2] = 60;
    }
  }
  return encodeRgbaPng(out, w, h);
}

Uint8List encodeRgbaPng(Uint8List rgba, int w, int h) => img.encodePng(
  img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, numChannels: 4),
);
