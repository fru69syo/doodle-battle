import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doodle_battle/features/puppet/rig/auto_rig.dart';
import 'package:doodle_battle/features/puppet/rig/bin_mask.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

BinMask raster(List<double> p, int w, int h) {
  final m = BinMask(w, h);
  final n = p.length ~/ 2;
  final xs = <double>[];
  for (var y = 0; y < h; y++) {
    final yc = y + 0.5;
    xs.clear();
    for (var i = 0; i < n; i++) {
      final x0 = p[2 * i], y0 = p[2 * i + 1];
      final x1 = p[(2 * i + 2) % (2 * n)], y1 = p[(2 * i + 3) % (2 * n)];
      if ((y0 <= yc) != (y1 <= yc))
        xs.add(x0 + (yc - y0) / (y1 - y0) * (x1 - x0));
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

void main() {
  test('debug', () {
    final ann = (jsonDecode(
      File('/home/user/datasets/ad_meta_ann/sample_annotations.json')
          .readAsStringSync(),
    ) as Map);
    final keys = ann.keys.toList();
    for (final idx
        in (Platform.environment['IDX'] ?? '16').split(',').map(int.parse)) {
      final key = keys[idx - 1];
      final v = ann[key] as Map;
      final a = (v['anns'] as List).first as Map;
      final bytes = File('/home/user/datasets/ad_meta/${v['split']}/$key')
          .readAsBytesSync();
      final im = img.decodeImage(bytes)!;
      final poly = ((a['segmentation'] as List).first as List)
          .map((e) => (e as num).toDouble())
          .toList();
      final mask = raster(poly, im.width, im.height);
      final rgba = Uint8List.fromList(
        im
            .convert(numChannels: 4, format: img.Format.uint8)
            .getBytes(order: img.ChannelOrder.rgba),
      );
      final r = autoRig(mask, rgba: rgba, debug: true);
      // ignore: avoid_print
      print(
        '#$idx ${r.rig.limbs.map((l) => '${l.kind.name}${l.tip}').join(' ')}',
      );
    }
  });
}
