import 'dart:convert';
import 'dart:math' as math;

/// Brushes of the in-app drawing tool. No pressure: every stroke of a
/// brush has the same width, so small fingers get the same result as a
/// stylus.
enum DrawTool {
  crayon(width: 16, code: 'c'),
  marker(width: 10, code: 'm'),
  brush(width: 26, code: 'b'),
  eraser(width: 34, code: 'e');

  const DrawTool({required this.width, required this.code});

  /// Line width in canvas units (the canvas is [StrokeDrawing.size] wide).
  final double width;
  final String code;

  static DrawTool fromCode(Object? c) =>
      values.firstWhere((t) => t.code == c, orElse: () => crayon);
}

/// The 12 crayon colours (ARGB): bright, distinct, and friendly to the
/// colour analysis (each falls into one hue family).
const kCanvasColors = <int>[
  0xFF1F1A1A, // くろ
  0xFF8A5A3B, // ちゃいろ
  0xFFE53935, // あか
  0xFFFF8A1F, // オレンジ
  0xFFFFD21F, // きいろ
  0xFF7CC943, // きみどり
  0xFF1E9E4A, // みどり
  0xFF2EC4E6, // みずいろ
  0xFF2F5FD8, // あお
  0xFF8E4FD8, // むらさき
  0xFFFF7EB6, // ピンク
  0xFF9E9E9E, // はいいろ
];

/// One stroke, in canvas units (0..[StrokeDrawing.size]).
class Stroke {
  Stroke(this.tool, this.color, List<double>? xy) : xy = xy ?? <double>[];

  final DrawTool tool;
  final int color;

  /// Flat x, y pairs.
  final List<double> xy;

  int get length => xy.length ~/ 2;
  double get width => tool.width;
  bool get isEraser => tool == DrawTool.eraser;

  /// Adds a point unless it is closer than 1.5 units to the last one.
  bool add(double x, double y) {
    final n = xy.length;
    if (n >= 2) {
      final dx = x - xy[n - 2], dy = y - xy[n - 1];
      if (dx * dx + dy * dy < 2.25) return false;
    }
    xy
      ..add(x)
      ..add(y);
    return true;
  }

  Map<String, Object?> toJson() => {
    't': tool.code,
    'c': color,
    'p': [for (final v in xy) v.round()],
  };

  static Stroke fromJson(Map<String, Object?> j) => Stroke(
    DrawTool.fromCode(j['t']),
    (j['c'] as num?)?.toInt() ?? kCanvasColors.first,
    [for (final v in (j['p'] as List? ?? const [])) (v as num).toDouble()],
  );
}

/// The whole drawing: an ordered stroke list on a [size]×[size]·[aspect]
/// canvas. This is what is kept on the phone (never uploaded) so the
/// auto-rigger can tell separately drawn limbs apart.
class StrokeDrawing {
  StrokeDrawing({List<Stroke>? strokes}) : strokes = strokes ?? [];

  /// Canvas width in units; height is [size] · [aspect].
  static const double size = 1000;
  static const double aspect = 1.25;
  static double get height => size * aspect;

  /// Caps (memory / JSON size); far above what a child draws.
  static const maxStrokes = 600;
  static const maxPoints = 4000;

  final List<Stroke> strokes;

  bool get isEmpty => strokes.every((s) => s.isEraser || s.length == 0);

  int get pointCount => strokes.fold(0, (a, s) => a + s.length);

  /// Bounding box of the ink (left, top, right, bottom) or null.
  (double, double, double, double)? inkBounds() {
    var l = double.infinity, t = double.infinity;
    var r = -double.infinity, b = -double.infinity;
    for (final s in strokes) {
      if (s.isEraser) continue;
      final hw = s.width / 2;
      for (var i = 0; i < s.xy.length; i += 2) {
        l = math.min(l, s.xy[i] - hw);
        r = math.max(r, s.xy[i] + hw);
        t = math.min(t, s.xy[i + 1] - hw);
        b = math.max(b, s.xy[i + 1] + hw);
      }
    }
    return r < l ? null : (l, t, r, b);
  }

  /// Stroke summary sent with `registerCharacter` (`source: canvas`) so the
  /// server can check that the cut-out was rendered by this tool
  /// (docs/TRUST.md §8.2): non-eraser strokes, their points, the palette
  /// colours used (ARGB) and the ink box. Null when there is no ink.
  Map<String, Object?>? canvasSummary() {
    final ink = [
      for (final s in strokes)
        if (!s.isEraser && s.length > 0) s,
    ];
    final box = inkBounds();
    if (ink.isEmpty || box == null) return null;
    final points = ink.fold(0, (a, s) => a + s.length);
    return {
      'v': 1,
      'strokes': ink.length.clamp(1, maxStrokes),
      'points': points.clamp(ink.length, maxPoints),
      'colors': {for (final s in ink) s.color & 0xFFFFFFFF}.toList(),
      'inkBox': [box.$1, box.$2, box.$3, box.$4],
    };
  }

  Map<String, Object?> toJson() => {
    'v': 1,
    'w': size,
    'h': height,
    's': [for (final s in strokes) s.toJson()],
  };

  String encode() => jsonEncode(toJson());

  static StrokeDrawing fromJson(Map<String, Object?> j) => StrokeDrawing(
    strokes: [
      for (final s in (j['s'] as List? ?? const []))
        Stroke.fromJson((s as Map).cast<String, Object?>()),
    ],
  );

  static StrokeDrawing? tryDecode(String? s) {
    if (s == null) return null;
    try {
      final j = jsonDecode(s);
      return j is Map ? fromJson(j.cast<String, Object?>()) : null;
    } on Object {
      return null;
    }
  }
}
