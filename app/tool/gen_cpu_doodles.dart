// Generates the bundled CPU opponent doodles (SPEC §4.3) into assets/cpu/.
//
//   cd app && dart run tool/gen_cpu_doodles.dart
//
// Every doodle is painted deterministically in a kid-crayon style, then run
// through the real on-device analyzer. The analyzer's cut-out PNG becomes the
// asset and its element / scores / Lv1 stats go into assets/cpu/manifest.json,
// so CPU characters are built exactly like players' characters. The Battle
// team references them by `id`.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';

import 'src/doodle_painter.dart';

class _Doodle {
  const _Doodle(this.id, this.name, this.expected, this.paint);
  final String id;

  /// Suggested hiragana/katakana display name.
  final String name;
  final ElementType expected;
  final void Function(DoodleCanvas c, math.Random rng) paint;
}

const _w = 800, _h = 640;

/// Shaky outline helper.
void _outline(
  DoodleCanvas c,
  List<Pt> shape,
  math.Random rng, {
  Rgb color = Crayon.black,
  double radius = 6,
  double shake = 3,
}) {
  c.stroke(
    tremble(densify(shape, 6, closed: true), shake, rng),
    radius,
    color,
    texture: 0.4,
    closed: true,
  );
}

void _line(
  DoodleCanvas c,
  List<Pt> pts,
  math.Random rng,
  Rgb color, {
  double radius = 6,
  double shake = 3,
}) {
  c.stroke(tremble(densify(pts, 6), shake, rng), radius, color, texture: 0.4);
}

void _eyes(DoodleCanvas c, Pt a, Pt b, {double r = 16}) {
  for (final p in [a, b]) {
    c.dot(p, r, Rgb.white);
    _ring(c, p, r);
    c.dot(p + Pt(r * 0.2, r * 0.15), r * 0.45, Crayon.black, texture: 0.2);
  }
}

void _ring(DoodleCanvas c, Pt p, double r) =>
    c.stroke(ellipse(p.x, p.y, r, r, n: 40), 3, Crayon.black, closed: true);

final _doodles = <_Doodle>[
  _Doodle('cpu_fire_blob', 'ぷるぷるスライム', ElementType.fire, (c, rng) {
    final body = ellipse(400, 360, 230, 170, wobble: 0.18, rng: rng);
    c.scribbleFill(body, Crayon.red, rng, radius: 7, spacing: 9);
    _outline(c, body, rng);
    _eyes(c, const Pt(330, 320), const Pt(460, 310), r: 26);
    _line(
      c,
      const [Pt(340, 420), Pt(400, 450), Pt(470, 415)],
      rng,
      Crayon.black,
    );
    c.scribbleFill(
      ellipse(250, 400, 30, 22, rng: rng, wobble: 0.1),
      Crayon.pink,
      rng,
      radius: 5,
      spacing: 6,
    );
  }),
  _Doodle('cpu_fire_spiky', 'トゲトゲ', ElementType.fire, (c, rng) {
    final body = star(400, 330, 260, 130, 9, jitter: 0.35, rng: rng);
    c.scribbleFill(body, Crayon.orange, rng, radius: 7, spacing: 9);
    c.scribbleFill(
      ellipse(400, 330, 100, 90, wobble: 0.1, rng: rng),
      Crayon.red,
      rng,
      radius: 7,
      spacing: 9,
    );
    _outline(c, body, rng, radius: 5);
    _eyes(c, const Pt(360, 310), const Pt(440, 305), r: 18);
    _line(
      c,
      const [
        Pt(360, 370),
        Pt(380, 355),
        Pt(400, 372),
        Pt(420, 355),
        Pt(440, 370),
      ],
      rng,
      Crayon.black,
      radius: 4,
    );
  }),
  _Doodle('cpu_water_snake', 'にょろにょろ', ElementType.water, (c, rng) {
    final path = [
      for (var i = 0; i <= 60; i++)
        Pt(60 + i * 11.0, 320 + 110 * math.sin(i / 60 * 3 * math.pi)),
    ];
    c.stroke(tremble(path, 4, rng), 34, Crayon.blue, texture: 0.45);
    c.stroke(tremble(path, 3, rng), 10, Crayon.sky, texture: 0.45);
    c.dot(path.last + const Pt(10, -5), 46, Crayon.blue, texture: 0.4);
    _eyes(
      c,
      path.last + const Pt(0, -18),
      path.last + const Pt(28, -14),
      r: 12,
    );
    _line(
      c,
      [
        path.last + const Pt(40, 20),
        path.last + const Pt(80, 30),
        path.last + const Pt(70, 45),
      ],
      rng,
      Crayon.red,
      radius: 4,
    );
  }),
  _Doodle('cpu_water_fish', 'まんまるフィッシュ', ElementType.water, (c, rng) {
    final body = ellipse(370, 320, 200, 170, wobble: 0.12, rng: rng);
    c.scribbleFill(body, Crayon.sky, rng, radius: 7, spacing: 9);
    final tail = [const Pt(560, 320), const Pt(700, 200), const Pt(690, 450)];
    c.scribbleFill(tail, Crayon.blue, rng, radius: 6, spacing: 8);
    _outline(c, body, rng);
    _outline(c, tail, rng, radius: 5);
    c.dot(const Pt(260, 280), 24, Rgb.white);
    _ring(c, const Pt(260, 280), 24);
    c.dot(const Pt(265, 284), 11, Crayon.black);
    for (var k = 0; k < 3; k++) {
      _line(
        c,
        [
          Pt(360 + k * 50.0, 200),
          Pt(390 + k * 50.0, 320),
          Pt(360 + k * 50.0, 440),
        ],
        rng,
        Crayon.blue,
        radius: 4,
      );
    }
  }),
  _Doodle('cpu_leaf_frog', 'ケロケロ', ElementType.leaf, (c, rng) {
    final body = ellipse(400, 380, 220, 150, wobble: 0.14, rng: rng);
    c.scribbleFill(body, Crayon.green, rng, radius: 7, spacing: 9);
    for (final x in [300.0, 500.0]) {
      final eye = ellipse(x, 240, 60, 55, wobble: 0.1, rng: rng);
      c.scribbleFill(eye, Crayon.green, rng, radius: 6, spacing: 8);
      _outline(c, eye, rng, radius: 5);
    }
    _outline(c, body, rng);
    _eyes(c, const Pt(300, 235), const Pt(500, 235), r: 24);
    _line(
      c,
      const [Pt(300, 420), Pt(400, 470), Pt(500, 420)],
      rng,
      Crayon.red,
      radius: 5,
    );
    for (final x in [220.0, 580.0]) {
      _line(
        c,
        [Pt(x, 500), Pt(x - 40, 580), Pt(x + 40, 585)],
        rng,
        Crayon.green,
        radius: 9,
      );
    }
  }),
  _Doodle('cpu_leaf_caterpillar', 'もりもりイモムシ', ElementType.leaf, (c, rng) {
    for (var k = 0; k < 6; k++) {
      final cx = 140 + k * 100.0;
      final cy = 360 + 40 * math.sin(k * 1.1);
      final seg = ellipse(cx, cy, 70, 75, wobble: 0.12, rng: rng);
      c.scribbleFill(
        seg,
        k.isEven ? Crayon.green : const Rgb(140, 200, 50),
        rng,
        radius: 6,
        spacing: 8,
      );
      _outline(c, seg, rng, radius: 5);
      _line(
        c,
        [Pt(cx, cy + 70), Pt(cx - 10, cy + 110)],
        rng,
        Crayon.brown,
        radius: 5,
      );
    }
    _eyes(c, const Pt(640, 330), const Pt(680, 335), r: 15);
    _line(c, const [Pt(640, 290), Pt(610, 200)], rng, Crayon.black, radius: 4);
    _line(c, const [Pt(680, 290), Pt(710, 200)], rng, Crayon.black, radius: 4);
  }),
  _Doodle('cpu_thunder_bird', 'ピヨピカ', ElementType.thunder, (c, rng) {
    final body = ellipse(400, 340, 190, 180, wobble: 0.12, rng: rng);
    c.scribbleFill(body, Crayon.yellow, rng, radius: 7, spacing: 9);
    final wing = ellipse(470, 380, 90, 60, wobble: 0.2, rng: rng);
    c.scribbleFill(wing, const Rgb(240, 190, 20), rng, radius: 6, spacing: 8);
    _outline(c, body, rng, color: Crayon.orange);
    _outline(c, wing, rng, color: Crayon.orange, radius: 4);
    _eyes(c, const Pt(340, 290), const Pt(420, 285), r: 18);
    c.scribbleFill(
      const [Pt(250, 320), Pt(180, 345), Pt(250, 370)],
      Crayon.orange,
      rng,
      radius: 5,
      spacing: 6,
    );
    for (final x in [360.0, 450.0]) {
      _line(
        c,
        [Pt(x, 515), Pt(x - 5, 590), Pt(x - 35, 600)],
        rng,
        Crayon.orange,
        radius: 5,
      );
    }
  }),
  _Doodle('cpu_thunder_star', 'ビリビリスター', ElementType.thunder, (c, rng) {
    final body = star(400, 330, 270, 120, 5, jitter: 0.25, rng: rng);
    c.scribbleFill(body, Crayon.yellow, rng, radius: 7, spacing: 9);
    _outline(c, body, rng, color: Crayon.orange, radius: 6);
    _eyes(c, const Pt(360, 320), const Pt(440, 320), r: 16);
    _line(
      c,
      const [Pt(370, 380), Pt(400, 395), Pt(430, 380)],
      rng,
      Crayon.black,
      radius: 4,
    );
    _line(
      c,
      const [Pt(80, 120), Pt(130, 180), Pt(100, 190), Pt(150, 260)],
      rng,
      Crayon.yellow,
      radius: 7,
    );
  }),
  _Doodle('cpu_shadow_ghost', 'おばけのモヤ', ElementType.shadow, (c, rng) {
    final shape = <Pt>[
      ...ellipse(
        400,
        260,
        170,
        150,
        n: 40,
        start: math.pi,
        rng: rng,
      ).sublist(0, 21),
      for (var k = 0; k <= 8; k++)
        Pt(570 - k * 42.5, 520 + (k.isEven ? 0 : 40)),
    ];
    c.scribbleFill(shape, Crayon.grey, rng, radius: 7, spacing: 9);
    _outline(c, shape, rng, radius: 7);
    c.dot(const Pt(350, 250), 22, Crayon.black, texture: 0.3);
    c.dot(const Pt(450, 250), 22, Crayon.black, texture: 0.3);
    c.scribbleFill(
      ellipse(400, 340, 40, 30, rng: rng),
      Crayon.black,
      rng,
      radius: 5,
      spacing: 6,
    );
  }),
  _Doodle('cpu_shadow_bat', 'コウモリン', ElementType.shadow, (c, rng) {
    final wings = [
      const Pt(400, 260),
      const Pt(560, 160),
      const Pt(740, 220),
      const Pt(690, 300),
      const Pt(640, 280),
      const Pt(600, 360),
      const Pt(540, 320),
      const Pt(470, 400),
      const Pt(400, 360),
      const Pt(330, 400),
      const Pt(260, 320),
      const Pt(200, 360),
      const Pt(160, 280),
      const Pt(110, 300),
      const Pt(60, 220),
      const Pt(240, 160),
    ];
    c.scribbleFill(wings, Crayon.purple, rng, radius: 7, spacing: 9);
    _outline(c, wings, rng, radius: 6);
    final body = ellipse(400, 300, 70, 90, wobble: 0.1, rng: rng);
    c.scribbleFill(body, Crayon.black, rng, radius: 6, spacing: 7);
    _eyes(c, const Pt(375, 280), const Pt(425, 280), r: 13);
    _line(
      c,
      const [Pt(380, 210), Pt(365, 160), Pt(395, 205)],
      rng,
      Crayon.black,
      radius: 5,
    );
    _line(
      c,
      const [Pt(405, 205), Pt(435, 160), Pt(420, 210)],
      rng,
      Crayon.black,
      radius: 5,
    );
  }),
  _Doodle('cpu_rainbow_cat', 'にじにゃん', ElementType.rainbow, (c, rng) {
    final head = ellipse(400, 340, 210, 180, wobble: 0.1, rng: rng);
    final colours = [
      Crayon.red,
      Crayon.orange,
      Crayon.yellow,
      Crayon.green,
      Crayon.blue,
      Crayon.purple,
    ];
    for (var k = 0; k < colours.length; k++) {
      final top = 160 + k * 62.0;
      final band = <Pt>[
        for (final p in head) Pt(p.x, p.y.clamp(top, top + 62).toDouble()),
      ];
      c.scribbleFill(band, colours[k], rng, radius: 7, spacing: 8);
    }
    for (final sx in [-1.0, 1.0]) {
      final ear = [
        Pt(400 + sx * 80, 190),
        Pt(400 + sx * 190, 80),
        Pt(400 + sx * 200, 250),
      ];
      c.scribbleFill(ear, Crayon.red, rng, radius: 6, spacing: 8);
      _outline(c, ear, rng, radius: 5);
    }
    _outline(c, head, rng);
    _eyes(c, const Pt(330, 310), const Pt(470, 305), r: 22);
    for (final sx in [-1.0, 1.0]) {
      for (var k = -1; k <= 1; k++) {
        _line(
          c,
          [
            Pt(400 + sx * 60, 380 + k * 12.0),
            Pt(400 + sx * 190, 370 + k * 30.0),
          ],
          rng,
          Crayon.black,
          radius: 3,
        );
      }
    }
  }),
  _Doodle('cpu_rainbow_robot', 'カラフルロボ', ElementType.rainbow, (c, rng) {
    void box(double x0, double y0, double x1, double y1, Rgb col) {
      final b = tremble(
        densify(
          [Pt(x0, y0), Pt(x1, y0), Pt(x1, y1), Pt(x0, y1)],
          10,
          closed: true,
        ),
        3,
        rng,
      );
      c.scribbleFill(b, col, rng, radius: 7, spacing: 9);
      _outline(c, b, rng, radius: 5, shake: 2);
    }

    box(300, 70, 500, 210, Crayon.yellow); // head
    box(250, 220, 550, 340, Crayon.red); // body
    box(250, 345, 550, 470, Crayon.blue);
    box(130, 240, 240, 420, Crayon.green); // arms
    box(560, 240, 670, 420, Crayon.green);
    box(280, 480, 380, 600, Crayon.purple); // legs
    box(420, 480, 520, 600, Crayon.purple);
    _eyes(c, const Pt(360, 140), const Pt(440, 140), r: 18);
    _line(c, const [Pt(400, 70), Pt(400, 20)], rng, Crayon.black, radius: 4);
    c.dot(const Pt(400, 20), 12, Crayon.red);
  }),
];

Future<void> main(List<String> args) async {
  final outDir = Directory(args.isNotEmpty ? args.first : 'assets/cpu');
  outDir.createSync(recursive: true);
  final entries = <Map<String, Object?>>[];
  var mismatches = 0;
  for (final (index, d) in _doodles.indexed) {
    final canvas = DoodleCanvas(_w, _h, seed: 1000 + index);
    d.paint(canvas, math.Random(2000 + index));
    final report = analyzeDrawingSync(canvas.encodePng());
    final r = report.result;
    File('${outDir.path}/${d.id}.png').writeAsBytesSync(r.cutoutPng);
    if (r.element != d.expected || report.rejectReason != null) {
      mismatches++;
      print(
        '!! ${d.id}: expected ${d.expected.name}, got ${r.element.name} '
        '(reject: ${report.rejectReason})',
      );
    }
    print(
      '${d.id.padRight(22)} ${r.element.name.padRight(8)} '
      'E=${r.energy.toStringAsFixed(1).padLeft(5)} '
      'S=${r.skill.toStringAsFixed(1).padLeft(5)} ${r.baseStats}',
    );
    entries.add({
      'id': d.id,
      'name': d.name,
      'asset': 'assets/cpu/${d.id}.png',
      'element': r.element.name,
      'energy': r.energy,
      'skill': r.skill,
      'isShobo': r.isShobo,
      'baseStats': r.baseStats.toJson(),
      'imageHash': r.imageHash,
    });
  }
  final manifest = {
    'version': 1,
    'generatedBy': 'tool/gen_cpu_doodles.dart',
    'note':
        'Lv1 stats from the on-device analyzer; scale by level with the '
        'battle growth rules.',
    'characters': entries,
  };
  File('${outDir.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  if (mismatches > 0) {
    stderr.writeln('$mismatches doodle(s) did not get their intended element');
    exitCode = 1;
  }
}
