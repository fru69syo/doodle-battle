// Prints the Vision feature / score table for every image in a folder.
// Use it to calibrate the energy & skill functions against real drawings.
//
//   cd app
//   dart run tool/analyze_dir.dart <folder> [--csv out.csv] [--cutouts dir]
//
// --csv      also writes every feature and authenticity signal (`auth.*`,
//            docs/TRUST.md) of every image as CSV
// --cutouts  also writes the cut-out PNGs (to eyeball segmentation)
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';

const _columns = <String>[
  'inkCoverage',
  'colorCount',
  'strokeSmoothness',
  'symmetry',
  'shadingLevel',
  'detailDensity',
  'photoLikelihood',
  'lineThickness',
];

const _abbrev = {
  'inkCoverage': 'ink',
  'colorCount': 'col',
  'strokeSmoothness': 'smooth',
  'symmetry': 'sym',
  'shadingLevel': 'shade',
  'detailDensity': 'detail',
  'photoLikelihood': 'photo',
  'lineThickness': 'thick',
};

void main(List<String> args) {
  String? csvPath;
  String? cutoutDir;
  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--csv' when i + 1 < args.length:
        csvPath = args[++i];
      case '--cutouts' when i + 1 < args.length:
        cutoutDir = args[++i];
      case '-h' || '--help':
        print(
          'usage: dart run tool/analyze_dir.dart <folder> '
          '[--csv out.csv] [--cutouts dir]',
        );
        return;
      default:
        positional.add(args[i]);
    }
  }
  if (positional.length != 1) {
    stderr.writeln(
      'usage: dart run tool/analyze_dir.dart <folder> '
      '[--csv out.csv] [--cutouts dir]',
    );
    exitCode = 64;
    return;
  }
  final dir = Directory(positional.single);
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where(
            (f) => RegExp(
              r'\.(jpe?g|png|webp|bmp|gif)$',
              caseSensitive: false,
            ).hasMatch(f.path),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stderr.writeln('no images in ${dir.path}');
    exitCode = 1;
    return;
  }
  if (cutoutDir != null) Directory(cutoutDir).createSync(recursive: true);

  final header = [
    'file'.padRight(28),
    'ms'.padLeft(5),
    'paper',
    'energy',
    'skill',
    'element'.padRight(8),
    'hp/atk/def/spd'.padRight(16),
    for (final c in _columns) _abbrev[c]!.padLeft(6),
    'reject',
  ].join(' ');
  print(header);
  print('-' * header.length);

  final csv = StringBuffer();
  List<String>? featureKeys;
  List<String>? authKeys;
  final rejects = <String, int>{};
  var analysed = 0;
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final sw = Stopwatch()..start();
    DrawingAnalysisReport report;
    try {
      report = analyzeDrawingSync(f.readAsBytesSync());
    } on UndecodableImageException {
      print('${name.padRight(28)} (not an image)');
      continue;
    }
    final ms = sw.elapsedMilliseconds;
    analysed++;
    final why = report.rejectReason?.name ?? 'accepted';
    rejects[why] = (rejects[why] ?? 0) + 1;
    final r = report.result;
    final s = r.baseStats;
    final m = r.features;
    print(
      [
        _clip(name, 28).padRight(28),
        '$ms'.padLeft(5),
        (report.paperQuad != null ? 'yes' : 'no').padRight(5),
        r.energy.toStringAsFixed(1).padLeft(6),
        '${r.skill.toStringAsFixed(1)}${r.isShobo ? '*' : ' '}'.padLeft(6),
        r.element.name.padRight(8),
        '${s.hp}/${s.atk}/${s.def}/${s.spd}'.padRight(16),
        for (final c in _columns) _fmt(m[c]).padLeft(6),
        report.rejectReason?.name ?? '',
      ].join(' '),
    );

    if (csvPath != null) {
      featureKeys ??= m.keys.toList();
      final auth = report.authenticity.toMap();
      authKeys ??= auth.keys.toList();
      if (csv.isEmpty) {
        csv.writeln(
          [
            'file',
            'ms',
            'energy',
            'skill',
            'element',
            'hp',
            'atk',
            'def',
            'spd',
            'reject',
            ...featureKeys,
            for (final k in authKeys) 'auth.$k',
          ].join(','),
        );
      }
      csv.writeln(
        [
          name,
          ms,
          r.energy,
          r.skill,
          r.element.name,
          s.hp,
          s.atk,
          s.def,
          s.spd,
          report.rejectReason?.name ?? '',
          for (final k in featureKeys) m[k] ?? '',
          for (final k in authKeys) auth[k] ?? '',
        ].join(','),
      );
    }
    if (cutoutDir != null) {
      final base = name.replaceAll(RegExp(r'\.[^.]+$'), '');
      File('$cutoutDir/$base.cutout.png').writeAsBytesSync(r.cutoutPng);
    }
  }
  print('(* = しょぼキャラ, skill > 75)');
  print('summary ($analysed images):');
  for (final e in rejects.entries) {
    final pct = (100 * e.value / analysed).toStringAsFixed(1);
    print('  ${e.key.padRight(12)} ${e.value} ($pct%)');
  }
  if (csvPath != null) {
    File(csvPath).writeAsStringSync(csv.toString());
    print('wrote $csvPath');
  }
}

String _fmt(num? v) {
  if (v == null) return '-';
  if (v is int || v == v.roundToDouble() && v.abs() >= 10) {
    return v.round().toString();
  }
  return v.toStringAsFixed(2);
}

String _clip(String s, int n) =>
    s.length <= n ? s : '${s.substring(0, n - 1)}…';
