import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:doodle_battle/features/puppet/mesh/puppet_mesh.dart';
import 'package:doodle_battle/features/puppet/rig/auto_rig.dart';
import 'package:doodle_battle/features/puppet/rig/bin_mask.dart';
import 'package:doodle_battle/features/puppet/rig/character_rig.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Accuracy of the auto-rigger on Meta's Amateur Drawings (MIT), local
/// sample only (never committed):
///
///   AD_DIR=/home/user/datasets/ad_meta \
///   AD_ANN=/home/user/datasets/ad_meta_ann/sample_annotations.json \
///   AD_OUT=/tmp/rig_eval flutter test test/features/puppet/rig_eval_test.dart
///
/// Mode `gt`: the dataset's own segmentation mask (isolates the rigger).
/// Mode `app`: the app's own cut-out silhouette (Vision pipeline), for
/// pictures where no paper warp happened (same coordinates as the GT).
/// A `-spike` suffix (`gt-spike`, `app-spike`) runs the spike's rules
/// (AutoRigOptions.spike) for before/after numbers.
/// Skipped when AD_DIR is not set.
void main() {
  final dir = Platform.environment['AD_DIR'];
  final annPath = Platform.environment['AD_ANN'];
  final out = Platform.environment['AD_OUT'];
  final modes =
      (Platform.environment['AD_MODES'] ?? 'gt-spike,gt,app-spike,app').split(
        ',',
      );
  final limit = int.tryParse(Platform.environment['AD_LIMIT'] ?? '') ?? 1000;

  test('auto-rig accuracy on Amateur Drawings', () {
    final ann = (jsonDecode(File(annPath!).readAsStringSync()) as Map)
        .cast<String, Object?>();
    final results = <String, List<_Eval>>{
      for (final m in modes) ...{m: [], '$m/images': [], '$m/holdout': []},
    };
    final csv = StringBuffer(
      'mode,file,split,ok,head,arms,legs,extras,blob,'
      'e_head,e_hand,e_foot,e_shoulder,e_elbow,e_hip,e_knee,rig_ms,build_ms\n',
    );
    var k = 0;
    for (final entry in ann.entries) {
      if (k++ >= limit) break;
      final v = (entry.value! as Map).cast<String, Object?>();
      final split = v['split']! as String;
      final a = ((v['anns']! as List).first as Map).cast<String, Object?>();
      final bytes = File('$dir/$split/${entry.key}').readAsBytesSync();
      final image = img.decodeImage(bytes)!;
      final w = image.width, h = image.height;
      final poly = ((a['segmentation']! as List).first as List)
          .map((e) => (e as num).toDouble())
          .toList();
      final kp = (a['keypoints']! as List)
          .map((e) => (e as num).toDouble())
          .toList();
      final bbox = (a['bbox']! as List)
          .map((e) => (e as num).toDouble())
          .toList();
      final norm = math.max(bbox[2], bbox[3]);
      final rgbaImg = image.convert(numChannels: 4, format: img.Format.uint8);
      final rgba = Uint8List.fromList(
        rgbaImg.getBytes(order: img.ChannelOrder.rgba),
      );
      DrawingAnalysisReport? rep;
      for (final mode in modes) {
        BinMask? mask;
        final spike = mode.endsWith('-spike');
        if (mode.startsWith('gt')) {
          mask = _rasterPolygon(poly, w, h);
        } else {
          rep ??= analyzeDrawingSync(bytes);
          if (rep.paperQuad != null) continue;
          final s = rep.silhouette;
          if (s.width != w || s.height != h) continue;
          mask = BinMask(w, h);
          // Restrict to the annotated character's box (+10 %), as a child
          // would crop to one character.
          final mx = bbox[2] * 0.1, my = bbox[3] * 0.1;
          for (var y = 0; y < h; y++) {
            for (var x = 0; x < w; x++) {
              if (x < bbox[0] - mx || x > bbox[0] + bbox[2] + mx) continue;
              if (y < bbox[1] - my || y > bbox[1] + bbox[3] + my) continue;
              if (s.bits[y * w + x] != 0) mask.data[y * w + x] = 1;
            }
          }
        }
        final env = Platform.environment;
        final r = autoRig(
          mask,
          rgba: rgba,
          o: spike
              ? AutoRigOptions.spike
              : AutoRigOptions(
                  workSize: int.tryParse(env['AD_WORK'] ?? '') ?? 160,
                  inkHints: env['AD_INK'] != '0',
                  bridgeGapFrac:
                      double.tryParse(env['AD_BRIDGE'] ?? '') ?? 0.06,
                ),
        );
        // Full character build (mesh + weights) timing on a cut-out.
        final sw = Stopwatch()..start();
        final cut = Uint8List(w * h * 4);
        for (var i = 0; i < w * h; i++) {
          if (mask.data[i] != 0) cut[i * 4 + 3] = 255;
        }
        buildPuppetMesh(cut, w, h, rig: r.rig);
        final buildMs = sw.elapsedMicroseconds / 1000;
        final e = _Eval.of(r.rig, kp, norm, r.micros / 1000, buildMs);
        results[mode]!.add(e);
        results['$mode/$split']!.add(e);
        csv.writeln(
          '$mode,${entry.key},$split,${e.ok ? 1 : 0},${e.hasHead ? 1 : 0},'
          '${e.arms},${e.legs},${e.extras},${r.rig.isBlob ? 1 : 0},'
          '${e.err.map((x) => x.isFinite ? x.toStringAsFixed(4) : 'inf').join(',')},'
          '${e.rigMs.toStringAsFixed(1)},${buildMs.toStringAsFixed(1)}',
        );
        if (out != null &&
            mode == (Platform.environment['AD_OV_MODE'] ?? 'gt') &&
            k <= int.parse(Platform.environment['AD_OV'] ?? '48')) {
          _overlay(image, r, kp, '$out/ov_${k.toString().padLeft(3, '0')}.png');
        }
      }
    }
    final summary = <String, Object?>{};
    for (final m in results.keys) {
      summary[m] = _summarise(results[m]!);
    }
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(summary));
    if (out != null) {
      Directory(out).createSync(recursive: true);
      File('$out/rig_eval.csv').writeAsStringSync(csv.toString());
      File(
        '$out/rig_eval_summary.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
    }
  }, skip: dir == null || annPath == null ? 'AD_DIR / AD_ANN not set' : false);
}

const _names = ['head', 'hand', 'foot', 'shoulder', 'elbow', 'hip', 'knee'];

class _Eval {
  _Eval(
    this.err,
    this.hasHead,
    this.arms,
    this.legs,
    this.extras,
    this.rigMs,
    this.buildMs,
  );
  final List<double> err; // normalised, per joint type (mean of the pair)
  final bool hasHead;
  final int arms, legs, extras;
  final double rigMs, buildMs;

  /// Head, 2 hands and 2 feet found and every tip within 10 % of the size.
  bool get ok =>
      hasHead && arms == 2 && legs >= 2 && err.take(3).every((e) => e <= 0.1);

  static _Eval of(
    CharacterRig rig,
    List<double> kp,
    double norm,
    double rigMs,
    double buildMs,
  ) {
    P2 p(int i) => P2(kp[i * 3], kp[i * 3 + 1]);
    final headGt = [0, 1, 2].map(p).reduce((a, b) => a + b) * (1 / 3);
    final head = rig.head;
    final arms = rig.of(LimbKind.arm).toList();
    final legs = rig.of(LimbKind.leg).toList()
      ..sort((a, b) => b.tip.y.compareTo(a.tip.y));
    double pair(List<P2> pred, P2 l, P2 r) {
      if (pred.length < 2) {
        if (pred.isEmpty) return double.infinity;
        // One found: count it against the nearer GT, the other is a miss.
        return double.infinity;
      }
      final a = pred[0].dist(l) + pred[1].dist(r);
      final b = pred[0].dist(r) + pred[1].dist(l);
      return math.min(a, b) / 2 / norm;
    }

    final e = <double>[
      head == null ? double.infinity : head.tip.dist(headGt) / norm,
      pair([for (final a in arms) a.tip], p(9), p(10)),
      pair([for (final l in legs.take(2)) l.tip], p(15), p(16)),
      pair([for (final a in arms) a.base], p(5), p(6)),
      pair([for (final a in arms) a.mid], p(7), p(8)),
      pair([for (final l in legs.take(2)) l.base], p(11), p(12)),
      pair([for (final l in legs.take(2)) l.mid], p(13), p(14)),
    ];
    return _Eval(
      e,
      head != null,
      arms.length,
      legs.length,
      rig.of(LimbKind.extra).length + rig.of(LimbKind.tail).length,
      rigMs,
      buildMs,
    );
  }
}

Map<String, Object?> _summarise(List<_Eval> rs) {
  if (rs.isEmpty) return {'n': 0};
  double pct(bool Function(_Eval) f) =>
      (1000 * rs.where(f).length / rs.length).round() / 10;
  final perJoint = <String, Object?>{};
  for (var j = 0; j < _names.length; j++) {
    final es = rs.map((r) => r.err[j]).toList()..sort();
    final found = es.where((e) => e.isFinite).toList();
    perJoint[_names[j]] = {
      'found%': pct((r) => r.err[j].isFinite),
      'pck05%': pct((r) => r.err[j] <= 0.05),
      'pck10%': pct((r) => r.err[j] <= 0.10),
      'pck20%': pct((r) => r.err[j] <= 0.20),
      'medianFound': found.isEmpty
          ? null
          : (found[found.length ~/ 2] * 1000).round() / 1000,
    };
  }
  final rig = rs.map((r) => r.rigMs).toList()..sort();
  final build = rs.map((r) => r.buildMs).toList()..sort();
  return {
    'n': rs.length,
    'rigSuccess%': pct((r) => r.ok),
    'structure5%': pct((r) => r.hasHead && r.arms == 2 && r.legs >= 2),
    'usable20%': pct((r) => r.err.take(3).every((e) => e <= 0.2)),
    'anyLimb%': pct((r) => r.arms + r.legs + (r.hasHead ? 1 : 0) > 0),
    'blob%': pct((r) => r.arms + r.legs + r.extras == 0 && !r.hasHead),
    'joints': perJoint,
    'rigMsMedian': rig[rig.length ~/ 2],
    'rigMsP90': rig[(rig.length * 0.9).floor()],
    'buildMsMedian': build[build.length ~/ 2],
    'buildMsP90': build[(build.length * 0.9).floor()],
  };
}

BinMask _rasterPolygon(List<double> p, int w, int h) {
  final m = BinMask(w, h);
  final n = p.length ~/ 2;
  final xs = <double>[];
  for (var y = 0; y < h; y++) {
    final yc = y + 0.5;
    xs.clear();
    for (var i = 0; i < n; i++) {
      final x0 = p[2 * i], y0 = p[2 * i + 1];
      final x1 = p[(2 * i + 2) % (2 * n)], y1 = p[(2 * i + 3) % (2 * n)];
      if ((y0 <= yc) != (y1 <= yc)) {
        xs.add(x0 + (yc - y0) / (y1 - y0) * (x1 - x0));
      }
    }
    xs.sort();
    for (var k = 0; k + 1 < xs.length; k += 2) {
      for (var x = xs[k].ceil(); x < xs[k + 1] && x < w; x++) {
        if (x >= 0) m.data[y * w + x] = 1;
      }
    }
  }
  return m;
}

void _overlay(img.Image src, AutoRigResult r, List<double> kp, String path) {
  final im = img.Image.from(src);
  final skel = r.skeleton;
  for (var i = 0; i < skel.pixels.length; i++) {
    if (skel.pixels[i] == 0) continue;
    final p = r.toDrawing((i % skel.w).toDouble(), (i ~/ skel.w).toDouble());
    img.fillRect(
      im,
      x1: p.x.round() - 1,
      y1: p.y.round() - 1,
      x2: p.x.round() + 1,
      y2: p.y.round() + 1,
      color: img.ColorRgb8(150, 150, 150),
    );
  }
  for (var j = 0; j < 17; j++) {
    img.fillCircle(
      im,
      x: kp[j * 3].round(),
      y: kp[j * 3 + 1].round(),
      radius: 3,
      color: img.ColorRgb8(0, 0, 255),
    );
  }
  final colors = {
    LimbKind.head: img.ColorRgb8(255, 0, 255),
    LimbKind.arm: img.ColorRgb8(255, 120, 0),
    LimbKind.leg: img.ColorRgb8(0, 170, 0),
    LimbKind.tail: img.ColorRgb8(0, 170, 170),
    LimbKind.extra: img.ColorRgb8(120, 120, 0),
    LimbKind.wing: img.ColorRgb8(120, 120, 255),
    LimbKind.item: img.ColorRgb8(60, 60, 60),
  };
  for (final h in r.hints) {
    img.drawLine(
      im,
      x1: h.a.x.round(),
      y1: h.a.y.round(),
      x2: h.b.x.round(),
      y2: h.b.y.round(),
      color: img.ColorRgb8(0, 200, 255),
    );
  }
  final rig = r.rig;
  for (final l in rig.limbs) {
    final c = colors[l.kind]!;
    for (final (a, b) in [(l.base, l.mid), (l.mid, l.tip)]) {
      img.drawLine(
        im,
        x1: a.x.round(),
        y1: a.y.round(),
        x2: b.x.round(),
        y2: b.y.round(),
        color: c,
        thickness: 2,
      );
    }
    img.fillCircle(
      im,
      x: l.tip.x.round(),
      y: l.tip.y.round(),
      radius: 5,
      color: c,
    );
  }
  img.drawLine(
    im,
    x1: rig.root.x.round(),
    y1: rig.root.y.round(),
    x2: rig.chest.x.round(),
    y2: rig.chest.y.round(),
    color: img.ColorRgb8(255, 0, 0),
    thickness: 3,
  );
  img.fillCircle(
    im,
    x: rig.root.x.round(),
    y: rig.root.y.round(),
    radius: 5,
    color: img.ColorRgb8(255, 0, 0),
  );
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(im));
}
