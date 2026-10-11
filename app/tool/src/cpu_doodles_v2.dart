// v2.0 CPU doodles (25 new ones; the original 12 stay in
// gen_cpu_doodles.dart unchanged so their PNGs are byte-identical).
// Kid-crayon style: wobbly outlines, scribble fills, few colours. A mix of
// limbless blobs, vehicles and figures with clear limbs (for the 2.5D rig).
import 'dart:math' as math;

import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';

import 'doodle_painter.dart';

typedef DoodlePaint = void Function(DoodleCanvas c, math.Random rng);

/// id, kana name, shape hint (limbs / blob / vehicle), painter.
typedef DoodleV2 = (String, String, String, DoodlePaint);

void outline(
  DoodleCanvas c,
  List<Pt> shape,
  math.Random rng, {
  Rgb color = Crayon.black,
  double radius = 6,
  double shake = 3,
}) => c.stroke(
  tremble(densify(shape, 6, closed: true), shake, rng),
  radius,
  color,
  texture: 0.4,
  closed: true,
);

void line(
  DoodleCanvas c,
  List<Pt> pts,
  math.Random rng,
  Rgb color, {
  double radius = 6,
  double shake = 3,
}) =>
    c.stroke(tremble(densify(pts, 6), shake, rng), radius, color, texture: 0.4);

void eyes(DoodleCanvas c, Pt a, Pt b, {double r = 16}) {
  for (final p in [a, b]) {
    c.dot(p, r, Rgb.white);
    c.stroke(ellipse(p.x, p.y, r, r, n: 40), 3, Crayon.black, closed: true);
    c.dot(p + Pt(r * 0.2, r * 0.15), r * 0.45, Crayon.black, texture: 0.2);
  }
}

void fillOutlined(
  DoodleCanvas c,
  List<Pt> shape,
  Rgb fill,
  math.Random rng, {
  Rgb edge = Crayon.black,
  double radius = 6,
}) {
  c.scribbleFill(shape, fill, rng, radius: 7, spacing: 9);
  outline(c, shape, rng, color: edge, radius: radius);
}

/// Thin pencil-like drawing: thin outline, sparse hatching (thin lines read
/// as "sharp" → チョキ).
void thinFill(
  DoodleCanvas c,
  List<Pt> shape,
  Rgb fill,
  math.Random rng, {
  Rgb edge = Crayon.black,
  double radius = 3,
}) {
  c.scribbleFill(shape, fill, rng, radius: 2.5, spacing: 14);
  outline(c, shape, rng, color: edge, radius: 3);
}

List<Pt> box(double x0, double y0, double x1, double y1) => [
  Pt(x0, y0),
  Pt(x1, y0),
  Pt(x1, y1),
  Pt(x0, y1),
];

void smile(DoodleCanvas c, double x, double y, double w, math.Random rng) =>
    line(
      c,
      [Pt(x - w, y), Pt(x, y + w * 0.5), Pt(x + w, y)],
      rng,
      Crayon.black,
      radius: 4,
    );

final List<DoodleV2> kDoodlesV2 = [
  (
    'cpu_stickman',
    'ぼうにんげん',
    'limbs',
    (c, rng) {
      final head = ellipse(400, 150, 70, 70, wobble: 0.1, rng: rng);
      fillOutlined(c, head, Crayon.yellow, rng);
      eyes(c, const Pt(375, 140), const Pt(425, 140), r: 10);
      smile(c, 400, 175, 20, rng);
      line(c, const [Pt(400, 220), Pt(400, 430)], rng, Crayon.blue, radius: 9);
      line(
        c,
        const [Pt(400, 270), Pt(300, 330), Pt(240, 280)],
        rng,
        Crayon.blue,
        radius: 8,
      );
      line(
        c,
        const [Pt(400, 270), Pt(500, 320), Pt(570, 260)],
        rng,
        Crayon.blue,
        radius: 8,
      );
      line(
        c,
        const [Pt(400, 430), Pt(340, 520), Pt(320, 600)],
        rng,
        Crayon.blue,
        radius: 8,
      );
      line(
        c,
        const [Pt(400, 430), Pt(460, 520), Pt(490, 600)],
        rng,
        Crayon.blue,
        radius: 8,
      );
    },
  ),
  (
    'cpu_bear',
    'くまごろう',
    'limbs',
    (c, rng) {
      for (final x in [300.0, 500.0]) {
        fillOutlined(
          c,
          ellipse(x, 120, 45, 45, wobble: 0.1, rng: rng),
          Crayon.brown,
          rng,
        );
      }
      final body = ellipse(400, 420, 150, 150, wobble: 0.08, rng: rng);
      for (final (a, b) in [
        (const Pt(270, 400), const Pt(170, 470)),
        (const Pt(530, 400), const Pt(630, 470)),
        (const Pt(330, 540), const Pt(300, 610)),
        (const Pt(470, 540), const Pt(500, 610)),
      ]) {
        line(c, [a, b], rng, Crayon.brown, radius: 30);
      }
      fillOutlined(c, body, Crayon.brown, rng, radius: 8);
      final head = ellipse(400, 210, 130, 115, wobble: 0.08, rng: rng);
      fillOutlined(c, head, Crayon.brown, rng, radius: 8);
      eyes(c, const Pt(355, 190), const Pt(445, 190), r: 16);
      c.dot(const Pt(400, 245), 18, Crayon.black, texture: 0.3);
    },
  ),
  (
    'cpu_butterfly',
    'ひらひらちょう',
    'limbs',
    (c, rng) {
      final wings = [
        (ellipse(250, 220, 150, 120, wobble: 0.15, rng: rng), Crayon.pink),
        (ellipse(550, 220, 150, 120, wobble: 0.15, rng: rng), Crayon.purple),
        (ellipse(280, 430, 110, 100, wobble: 0.15, rng: rng), Crayon.yellow),
        (ellipse(520, 430, 110, 100, wobble: 0.15, rng: rng), Crayon.sky),
      ];
      for (final (w, col) in wings) {
        fillOutlined(c, w, col, rng);
      }
      for (final (p, col) in [
        (const Pt(240, 210), Crayon.orange),
        (const Pt(560, 210), Crayon.green),
      ]) {
        c.scribbleFill(
          ellipse(p.x, p.y, 45, 40, rng: rng),
          col,
          rng,
          radius: 6,
          spacing: 7,
        );
      }
      fillOutlined(
        c,
        ellipse(400, 330, 35, 170, wobble: 0.05, rng: rng),
        Crayon.black,
        rng,
      );
      line(c, const [Pt(390, 170), Pt(340, 70)], rng, Crayon.black, radius: 5);
      line(c, const [Pt(410, 170), Pt(460, 70)], rng, Crayon.black, radius: 5);
    },
  ),
  (
    'cpu_hedgehog',
    'ちくちくハリー',
    'limbs',
    (c, rng) {
      final spikes = star(420, 330, 270, 170, 14, jitter: 0.25, rng: rng);
      thinFill(c, spikes, Crayon.brown, rng, radius: 3);
      final face = ellipse(250, 380, 110, 90, wobble: 0.08, rng: rng);
      thinFill(c, face, const Rgb(240, 200, 150), rng);
      eyes(c, const Pt(230, 350), const Pt(290, 350), r: 12);
      c.dot(const Pt(150, 395), 16, Crayon.black);
      for (final x in [330.0, 470.0]) {
        line(c, [Pt(x, 520), Pt(x - 10, 600)], rng, Crayon.brown, radius: 4);
      }
    },
  ),
  (
    'cpu_octopus',
    'たこすけ',
    'limbs',
    (c, rng) {
      for (var k = 0; k < 8; k++) {
        final x0 = 230 + k * 48.0;
        line(
          c,
          [
            Pt(x0, 360),
            Pt(x0 + 25 * math.sin(k.toDouble()), 470),
            Pt(x0 - 20 + 10 * k % 30, 590),
          ],
          rng,
          Crayon.red,
          radius: 6,
        );
      }
      final head = ellipse(400, 250, 200, 170, wobble: 0.1, rng: rng);
      thinFill(c, head, Crayon.red, rng);
      eyes(c, const Pt(340, 250), const Pt(460, 250), r: 24);
      c.scribbleFill(
        ellipse(270, 170, 30, 20, rng: rng),
        Crayon.yellow,
        rng,
        radius: 3,
        spacing: 6,
      );
      c.scribbleFill(
        ellipse(520, 160, 25, 18, rng: rng),
        Crayon.green,
        rng,
        radius: 3,
        spacing: 6,
      );
    },
  ),
  (
    'cpu_jellyfish',
    'くらげっち',
    'blob',
    (c, rng) {
      final dome = <Pt>[
        ...ellipse(
          400,
          300,
          230,
          200,
          n: 40,
          start: math.pi,
          wobble: 0.08,
          rng: rng,
        ).sublist(0, 21),
      ];
      fillOutlined(c, dome, Crayon.sky, rng);
      for (var k = 0; k < 6; k++) {
        final x = 220 + k * 72.0;
        line(
          c,
          [Pt(x, 310), Pt(x + 30, 420), Pt(x - 10, 520), Pt(x + 20, 610)],
          rng,
          [Crayon.pink, Crayon.purple, Crayon.blue][k % 3],
          radius: 7,
        );
      }
      eyes(c, const Pt(350, 230), const Pt(450, 230), r: 18);
    },
  ),
  (
    'cpu_swordfish',
    'カジキング',
    'limbs',
    (c, rng) {
      final body = ellipse(380, 330, 230, 90, wobble: 0.08, rng: rng);
      thinFill(c, body, Crayon.blue, rng);
      line(c, const [Pt(150, 320), Pt(20, 300)], rng, Crayon.grey, radius: 3);
      thinFill(
        c,
        const [Pt(600, 330), Pt(760, 200), Pt(730, 330), Pt(760, 460)],
        Crayon.blue,
        rng,
      );
      thinFill(
        c,
        const [Pt(330, 250), Pt(420, 120), Pt(470, 250)],
        Crayon.sky,
        rng,
      );
      eyes(c, const Pt(230, 300), const Pt(260, 300), r: 12);
    },
  ),
  (
    'cpu_rock_golem',
    'ごろごろいわ',
    'limbs',
    (c, rng) {
      for (final (a, b) in [
        (const Pt(230, 330), const Pt(130, 450)),
        (const Pt(570, 330), const Pt(670, 450)),
      ]) {
        line(c, [a, b], rng, Crayon.grey, radius: 42);
      }
      for (final x in [320.0, 480.0]) {
        fillOutlined(
          c,
          box(x - 55, 480, x + 55, 610),
          Crayon.grey,
          rng,
          radius: 8,
        );
      }
      final body = ellipse(400, 300, 220, 210, wobble: 0.22, rng: rng);
      fillOutlined(c, body, Crayon.grey, rng, radius: 9);
      eyes(c, const Pt(340, 260), const Pt(460, 260), r: 20);
      line(c, const [Pt(330, 370), Pt(470, 370)], rng, Crayon.black, radius: 8);
    },
  ),
  (
    'cpu_flower',
    'はなぽん',
    'limbs',
    (c, rng) {
      line(
        c,
        const [Pt(400, 380), Pt(410, 620)],
        rng,
        Crayon.green,
        radius: 14,
      );
      fillOutlined(
        c,
        ellipse(320, 520, 70, 30, rng: rng),
        Crayon.green,
        rng,
        radius: 4,
      );
      final cols = [
        Crayon.red,
        Crayon.orange,
        Crayon.yellow,
        Crayon.pink,
        Crayon.purple,
        Crayon.sky,
      ];
      for (var k = 0; k < 6; k++) {
        final a = k * math.pi / 3;
        final p = Pt(400 + 130 * math.cos(a), 250 + 130 * math.sin(a));
        fillOutlined(
          c,
          ellipse(p.x, p.y, 80, 70, wobble: 0.1, rng: rng),
          cols[k],
          rng,
          radius: 5,
        );
      }
      fillOutlined(c, ellipse(400, 250, 90, 90, rng: rng), Crayon.yellow, rng);
      eyes(c, const Pt(370, 240), const Pt(430, 240), r: 13);
    },
  ),
  (
    'cpu_dino',
    'ガオザウルス',
    'limbs',
    (c, rng) {
      final body = <Pt>[
        const Pt(120, 420),
        const Pt(250, 300),
        const Pt(420, 260),
        const Pt(560, 200),
        const Pt(620, 90),
        const Pt(720, 110),
        const Pt(720, 190),
        const Pt(640, 230),
        const Pt(600, 380),
        const Pt(520, 470),
        const Pt(300, 480),
      ];
      for (var k = 0; k < 5; k++) {
        final x = 260 + k * 70.0;
        thinFill(
          c,
          [
            Pt(x, 300 - k * 12),
            Pt(x + 35, 200 - k * 12),
            Pt(x + 70, 290 - k * 12),
          ],
          Crayon.orange,
          rng,
          radius: 3,
        );
      }
      thinFill(c, body, Crayon.green, rng);
      for (final x in [320.0, 480.0]) {
        line(c, [Pt(x, 470), Pt(x, 600)], rng, Crayon.green, radius: 8);
      }
      line(c, const [Pt(600, 300), Pt(670, 340)], rng, Crayon.green, radius: 4);
      eyes(c, const Pt(670, 140), const Pt(695, 140), r: 10);
    },
  ),
  (
    'cpu_penguin',
    'ペンペン',
    'limbs',
    (c, rng) {
      final body = ellipse(400, 340, 170, 230, wobble: 0.06, rng: rng);
      fillOutlined(c, body, Crayon.black, rng);
      c.scribbleFill(
        ellipse(400, 390, 110, 160, rng: rng),
        Rgb.white,
        rng,
        radius: 7,
        spacing: 7,
      );
      for (final (a, b) in [
        (const Pt(240, 300), const Pt(160, 430)),
        (const Pt(560, 300), const Pt(640, 430)),
      ]) {
        line(c, [a, b], rng, Crayon.black, radius: 26);
      }
      fillOutlined(
        c,
        const [Pt(370, 220), Pt(400, 260), Pt(430, 220)],
        Crayon.orange,
        rng,
        radius: 4,
      );
      eyes(c, const Pt(360, 180), const Pt(440, 180), r: 15);
      for (final x in [340.0, 460.0]) {
        fillOutlined(
          c,
          ellipse(x, 590, 50, 22, rng: rng),
          Crayon.orange,
          rng,
          radius: 4,
        );
      }
    },
  ),
  (
    'cpu_snowman',
    'ゆきだるまん',
    'blob',
    (c, rng) {
      fillOutlined(
        c,
        ellipse(400, 450, 190, 160, wobble: 0.06, rng: rng),
        const Rgb(225, 240, 255),
        rng,
      );
      fillOutlined(
        c,
        ellipse(400, 200, 130, 120, wobble: 0.06, rng: rng),
        const Rgb(225, 240, 255),
        rng,
      );
      fillOutlined(c, box(320, 40, 480, 100), Crayon.red, rng);
      eyes(c, const Pt(360, 190), const Pt(440, 190), r: 13);
      fillOutlined(
        c,
        const [Pt(400, 215), Pt(470, 235), Pt(400, 245)],
        Crayon.orange,
        rng,
        radius: 3,
      );
      for (final y in [400.0, 470.0, 540.0]) {
        c.dot(Pt(400, y), 14, Crayon.black);
      }
    },
  ),
  (
    'cpu_car',
    'ブーブーカー',
    'vehicle',
    (c, rng) {
      final body = tremble(
        densify(
          [
            const Pt(90, 400),
            const Pt(150, 300),
            const Pt(260, 290),
            const Pt(330, 180),
            const Pt(530, 180),
            const Pt(600, 290),
            const Pt(720, 310),
            const Pt(730, 430),
            const Pt(90, 440),
          ],
          10,
          closed: true,
        ),
        3,
        rng,
      );
      fillOutlined(c, body, Crayon.red, rng);
      fillOutlined(c, box(350, 205, 430, 285), Crayon.sky, rng, radius: 4);
      fillOutlined(c, box(450, 205, 540, 285), Crayon.sky, rng, radius: 4);
      for (final x in [220.0, 590.0]) {
        fillOutlined(c, ellipse(x, 460, 70, 70, rng: rng), Crayon.black, rng);
        c.dot(Pt(x, 460), 22, Crayon.grey);
      }
      c.dot(const Pt(710, 360), 18, Crayon.yellow);
    },
  ),
  (
    'cpu_train',
    'でんしゃくん',
    'vehicle',
    (c, rng) {
      final cols = [Crayon.blue, Crayon.yellow, Crayon.green];
      for (var k = 0; k < 3; k++) {
        final x0 = 60 + k * 240.0;
        fillOutlined(c, box(x0, 220, x0 + 220, 440), cols[k], rng);
        fillOutlined(
          c,
          box(x0 + 40, 260, x0 + 120, 330),
          Rgb.white,
          rng,
          radius: 4,
        );
        for (final dx in [50.0, 170.0]) {
          fillOutlined(
            c,
            ellipse(x0 + dx, 470, 38, 38, rng: rng),
            Crayon.black,
            rng,
            radius: 4,
          );
        }
      }
      fillOutlined(c, box(110, 140, 170, 220), Crayon.red, rng);
      eyes(c, const Pt(200, 300), const Pt(240, 300), r: 12);
    },
  ),
  (
    'cpu_ufo',
    'ユーフォー',
    'vehicle',
    (c, rng) {
      fillOutlined(
        c,
        ellipse(400, 230, 120, 110, wobble: 0.05, rng: rng),
        Crayon.sky,
        rng,
      );
      fillOutlined(
        c,
        ellipse(400, 340, 320, 90, wobble: 0.05, rng: rng),
        Crayon.grey,
        rng,
      );
      final cols = [
        Crayon.red,
        Crayon.yellow,
        Crayon.green,
        Crayon.pink,
        Crayon.orange,
      ];
      for (var k = 0; k < 5; k++) {
        c.dot(Pt(200 + k * 100.0, 345), 22, cols[k], texture: 0.3);
      }
      for (final x in [300.0, 500.0]) {
        line(
          c,
          [Pt(x, 420), Pt(x + (x < 400 ? -40 : 40), 540)],
          rng,
          Crayon.yellow,
          radius: 10,
        );
      }
      eyes(c, const Pt(370, 220), const Pt(430, 220), r: 14);
    },
  ),
  (
    'cpu_crab',
    'チョキがに',
    'limbs',
    (c, rng) {
      for (var k = 0; k < 3; k++) {
        line(
          c,
          [Pt(300, 380 + k * 40.0), Pt(180, 430 + k * 50.0)],
          rng,
          Crayon.red,
          radius: 10,
        );
        line(
          c,
          [Pt(500, 380 + k * 40.0), Pt(620, 430 + k * 50.0)],
          rng,
          Crayon.red,
          radius: 10,
        );
      }
      for (final sx in [-1.0, 1.0]) {
        line(
          c,
          [Pt(400 + sx * 150, 300), Pt(400 + sx * 230, 180)],
          rng,
          Crayon.red,
          radius: 14,
        );
        fillOutlined(
          c,
          [
            Pt(400 + sx * 230, 180),
            Pt(400 + sx * 320, 60),
            Pt(400 + sx * 260, 150),
            Pt(400 + sx * 330, 140),
            Pt(400 + sx * 250, 220),
          ],
          Crayon.red,
          rng,
          radius: 5,
        );
      }
      final body = ellipse(400, 380, 170, 110, wobble: 0.1, rng: rng);
      fillOutlined(c, body, Crayon.orange, rng);
      eyes(c, const Pt(360, 330), const Pt(440, 330), r: 14);
    },
  ),
  (
    'cpu_cactus',
    'サボテンダ',
    'limbs',
    (c, rng) {
      final trunk = ellipse(400, 360, 80, 250, wobble: 0.05, rng: rng);
      for (final (a, b, e) in [
        (const Pt(330, 360), const Pt(220, 360), const Pt(220, 230)),
        (const Pt(470, 300), const Pt(580, 300), const Pt(580, 170)),
      ]) {
        line(c, [a, b, e], rng, Crayon.green, radius: 10);
      }
      thinFill(c, trunk, Crayon.green, rng);
      for (var k = 0; k < 12; k++) {
        final y = 150 + k * 35.0;
        line(
          c,
          [Pt(k.isEven ? 320 : 480, y), Pt(k.isEven ? 290 : 510, y - 15)],
          rng,
          Crayon.black,
          radius: 3,
        );
      }
      eyes(c, const Pt(370, 260), const Pt(430, 260), r: 13);
      thinFill(
        c,
        ellipse(400, 100, 40, 30, rng: rng),
        Crayon.pink,
        rng,
        radius: 3,
      );
    },
  ),
  (
    'cpu_knight',
    'ナイトくん',
    'limbs',
    (c, rng) {
      thinFill(c, box(330, 60, 470, 190), Crayon.grey, rng);
      line(c, const [Pt(345, 120), Pt(455, 120)], rng, Crayon.black, radius: 3);
      thinFill(c, box(320, 200, 480, 400), Crayon.blue, rng);
      line(
        c,
        const [Pt(320, 230), Pt(220, 300), Pt(170, 250)],
        rng,
        Crayon.grey,
        radius: 4,
      );
      line(c, const [Pt(170, 250), Pt(110, 60)], rng, Crayon.yellow, radius: 3);
      line(c, const [Pt(480, 230), Pt(570, 300)], rng, Crayon.grey, radius: 4);
      thinFill(c, ellipse(610, 320, 60, 80, rng: rng), Crayon.red, rng);
      line(c, const [Pt(360, 400), Pt(340, 600)], rng, Crayon.grey, radius: 5);
      line(c, const [Pt(440, 400), Pt(470, 600)], rng, Crayon.grey, radius: 5);
    },
  ),
  (
    'cpu_rocket',
    'ロケットン',
    'vehicle',
    (c, rng) {
      final body = [
        const Pt(400, 20),
        const Pt(470, 140),
        const Pt(470, 470),
        const Pt(330, 470),
        const Pt(330, 140),
      ];
      fillOutlined(c, body, Rgb.white, rng);
      fillOutlined(
        c,
        const [Pt(330, 360), Pt(250, 500), Pt(330, 470)],
        Crayon.red,
        rng,
      );
      fillOutlined(
        c,
        const [Pt(470, 360), Pt(550, 500), Pt(470, 470)],
        Crayon.red,
        rng,
      );
      fillOutlined(c, ellipse(400, 220, 45, 45, rng: rng), Crayon.sky, rng);
      fillOutlined(
        c,
        const [Pt(350, 480), Pt(400, 620), Pt(450, 480)],
        Crayon.orange,
        rng,
        radius: 4,
      );
    },
  ),
  (
    'cpu_castle',
    'おしろキング',
    'blob',
    (c, rng) {
      fillOutlined(c, box(160, 260, 640, 600), Crayon.grey, rng, radius: 8);
      for (final x in [160.0, 560.0]) {
        fillOutlined(c, box(x, 120, x + 80, 300), Crayon.grey, rng);
        fillOutlined(
          c,
          [Pt(x - 10, 130), Pt(x + 40, 40), Pt(x + 90, 130)],
          Crayon.red,
          rng,
        );
      }
      fillOutlined(c, box(340, 440, 460, 600), Crayon.brown, rng);
      eyes(c, const Pt(330, 340), const Pt(470, 340), r: 22);
    },
  ),
  (
    'cpu_cloud',
    'もくもくん',
    'blob',
    (c, rng) {
      for (final (x, y, r) in [
        (260.0, 330.0, 120.0),
        (400.0, 260.0, 150.0),
        (540.0, 330.0, 120.0),
        (330.0, 400.0, 110.0),
        (470.0, 400.0, 110.0),
      ]) {
        c.scribbleFill(
          ellipse(x, y, r, r * 0.85, wobble: 0.08, rng: rng),
          const Rgb(200, 225, 250),
          rng,
          radius: 7,
          spacing: 9,
        );
      }
      outline(
        c,
        ellipse(400, 330, 300, 190, wobble: 0.2, rng: rng),
        rng,
        color: Crayon.blue,
      );
      eyes(c, const Pt(350, 310), const Pt(450, 310), r: 18);
      smile(c, 400, 370, 30, rng);
    },
  ),
  (
    'cpu_rainbow_bird',
    'にじいろバード',
    'limbs',
    (c, rng) {
      final cols = [
        Crayon.red,
        Crayon.orange,
        Crayon.yellow,
        Crayon.green,
        Crayon.blue,
        Crayon.purple,
      ];
      for (var k = 0; k < 6; k++) {
        fillOutlined(
          c,
          [Pt(560, 300), Pt(760, 130 + k * 50.0), Pt(740, 180 + k * 50.0)],
          cols[k],
          rng,
          radius: 3,
        );
      }
      final body = ellipse(400, 320, 190, 140, wobble: 0.08, rng: rng);
      fillOutlined(c, body, Crayon.pink, rng);
      fillOutlined(
        c,
        ellipse(420, 330, 100, 60, wobble: 0.2, rng: rng),
        Crayon.purple,
        rng,
        radius: 4,
      );
      fillOutlined(
        c,
        const [Pt(220, 290), Pt(140, 310), Pt(220, 330)],
        Crayon.orange,
        rng,
        radius: 3,
      );
      eyes(c, const Pt(280, 270), const Pt(320, 270), r: 12);
      for (final x in [360.0, 440.0]) {
        line(
          c,
          [Pt(x, 450), Pt(x, 560), Pt(x - 30, 580)],
          rng,
          Crayon.orange,
          radius: 6,
        );
      }
    },
  ),
  (
    'cpu_kite',
    'たこあげカイト',
    'vehicle',
    (c, rng) {
      final kite = [
        const Pt(400, 30),
        const Pt(560, 230),
        const Pt(400, 430),
        const Pt(240, 230),
      ];
      fillOutlined(
        c,
        [kite[0], kite[1], const Pt(400, 230)],
        Crayon.red,
        rng,
        radius: 4,
      );
      fillOutlined(
        c,
        [kite[1], kite[2], const Pt(400, 230)],
        Crayon.yellow,
        rng,
        radius: 4,
      );
      fillOutlined(
        c,
        [kite[2], kite[3], const Pt(400, 230)],
        Crayon.blue,
        rng,
        radius: 4,
      );
      fillOutlined(
        c,
        [kite[3], kite[0], const Pt(400, 230)],
        Crayon.green,
        rng,
        radius: 4,
      );
      line(
        c,
        const [Pt(400, 430), Pt(450, 500), Pt(380, 560), Pt(440, 620)],
        rng,
        Crayon.black,
        radius: 4,
      );
      eyes(c, const Pt(370, 200), const Pt(430, 200), r: 12);
    },
  ),
  (
    'cpu_dragon',
    'ドラゴラ',
    'limbs',
    (c, rng) {
      fillOutlined(
        c,
        const [Pt(330, 230), Pt(160, 60), Pt(120, 260), Pt(260, 300)],
        Crayon.purple,
        rng,
      );
      fillOutlined(
        c,
        const [Pt(470, 230), Pt(640, 60), Pt(680, 260), Pt(540, 300)],
        Crayon.purple,
        rng,
      );
      final body = ellipse(400, 360, 150, 170, wobble: 0.08, rng: rng);
      fillOutlined(c, body, Crayon.green, rng);
      c.scribbleFill(
        ellipse(400, 400, 80, 110, rng: rng),
        Crayon.yellow,
        rng,
        radius: 6,
        spacing: 7,
      );
      fillOutlined(
        c,
        ellipse(400, 160, 100, 80, wobble: 0.08, rng: rng),
        Crayon.green,
        rng,
      );
      for (final x in [350.0, 450.0]) {
        fillOutlined(
          c,
          [Pt(x - 20, 100), Pt(x, 30), Pt(x + 20, 100)],
          Crayon.orange,
          rng,
          radius: 3,
        );
      }
      eyes(c, const Pt(365, 150), const Pt(435, 150), r: 14);
      for (final x in [330.0, 470.0]) {
        line(c, [Pt(x, 500), Pt(x, 610)], rng, Crayon.green, radius: 22);
      }
      line(
        c,
        const [Pt(540, 420), Pt(680, 480), Pt(740, 400)],
        rng,
        Crayon.green,
        radius: 18,
      );
      fillOutlined(
        c,
        const [Pt(560, 140), Pt(700, 120), Pt(640, 170), Pt(720, 200)],
        Crayon.red,
        rng,
        radius: 3,
      );
    },
  ),
  (
    'cpu_scribble_king',
    'らくがきキング',
    'limbs',
    (c, rng) {
      final body = ellipse(400, 360, 220, 200, wobble: 0.2, rng: rng);
      final cols = [
        Crayon.red,
        Crayon.yellow,
        Crayon.green,
        Crayon.blue,
        Crayon.purple,
        Crayon.orange,
      ];
      fillOutlined(c, body, Crayon.sky, rng, radius: 8);
      for (var k = 0; k < 14; k++) {
        final a = k * 0.9;
        line(
          c,
          [
            Pt(400 + 120 * math.cos(a), 360 + 110 * math.sin(a)),
            Pt(400 + 150 * math.cos(a + 1.3), 360 + 120 * math.sin(a + 2.1)),
          ],
          rng,
          cols[k % cols.length],
          radius: 6,
        );
      }
      fillOutlined(
        c,
        const [
          Pt(280, 170),
          Pt(310, 60),
          Pt(360, 140),
          Pt(400, 40),
          Pt(440, 140),
          Pt(490, 60),
          Pt(520, 170),
        ],
        Crayon.yellow,
        rng,
        radius: 5,
      );
      eyes(c, const Pt(340, 300), const Pt(460, 300), r: 26);
      smile(c, 400, 400, 60, rng);
      line(c, const [Pt(190, 360), Pt(80, 260)], rng, Crayon.sky, radius: 20);
      line(c, const [Pt(610, 360), Pt(720, 260)], rng, Crayon.sky, radius: 20);
      line(c, const [Pt(330, 550), Pt(310, 620)], rng, Crayon.sky, radius: 22);
      line(c, const [Pt(470, 550), Pt(490, 620)], rng, Crayon.sky, radius: 22);
    },
  ),
];

/// The analyser report of a painted doodle (helper for the generator).
DrawingAnalysisReport analyseDoodle(DoodleCanvas c) =>
    analyzeDrawingSync(c.encodePng());
