// Calibration report for the "is this a hand drawing on paper?" detector
// (docs/TRUST.md §3).
//
//   cd app
//   dart run tool/trust_calibration.dart [--out dir] [--kids dir]...
//
// Runs every synthetic case of tool/src/trust_cases.dart through the real
// analyzer and prints the signals, the verdict and the rates:
//   * false-reject rate on kids' drawings (target: < 1 %, ideally 0)
//   * detection rate per non-drawing category (digital / print / screen /
//     photo)
// --kids dir   also treats every image in `dir` as a real kid drawing (e.g. a
//              local sample of Meta's Amateur Drawings dataset, never
//              committed) and lists the ones that were rejected.
// --out dir    writes the synthetic images (to eyeball them).
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';

import 'src/trust_cases.dart';

void main(List<String> args) {
  String? outDir;
  final kidDirs = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--out' when i + 1 < args.length:
        outDir = args[++i];
      case '--kids' when i + 1 < args.length:
        kidDirs.add(args[++i]);
      default:
        stderr.writeln(
          'usage: dart run tool/trust_calibration.dart [--out dir] '
          '[--kids dir]...',
        );
        exitCode = 64;
        return;
    }
  }
  if (outDir != null) Directory(outDir).createSync(recursive: true);

  final tally = <String, ({int n, int rejected})>{};
  void count(String category, bool rejected) {
    final t = tally[category] ?? (n: 0, rejected: 0);
    tally[category] = (n: t.n + 1, rejected: t.rejected + (rejected ? 1 : 0));
  }

  print(
    '${'case'.padRight(40)} ${'verdict'.padRight(11)} paper  photo polish '
    'noise  flat  luma chroma per',
  );
  for (final c in [...kidCases(), ...notDrawingCases()]) {
    final bytes = c.build();
    if (outDir != null) {
      final file = c.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final ext = bytes[0] == 0x89 ? 'png' : 'jpg';
      File('$outDir/${c.category}__$file.$ext').writeAsBytesSync(bytes);
    }
    final r = analyzeDrawingSync(bytes);
    final why = r.rejectReason;
    final notPaper = why != null && why.isNotPaperDrawing;
    count(c.category, notPaper);
    print(_row(c.name, why?.name ?? 'ok', r.authenticity));
  }

  for (final dir in kidDirs) {
    final files =
        Directory(dir)
            .listSync()
            .whereType<File>()
            .where(
              (f) => RegExp(
                r'\.(jpe?g|png|webp)$',
                caseSensitive: false,
              ).hasMatch(f.path),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final rejected = <String>[];
    for (final f in files) {
      final DrawingAnalysisReport r;
      try {
        r = analyzeDrawingSync(f.readAsBytesSync());
      } on UndecodableImageException {
        continue;
      }
      final why = r.rejectReason;
      final notPaper = why != null && why.isNotPaperDrawing;
      count('kid ($dir)', notPaper);
      if (notPaper) {
        rejected.add(_row(f.uri.pathSegments.last, why.name, r.authenticity));
      }
    }
    print('\nrejected in $dir:');
    rejected.forEach(print);
  }

  print('\nsummary');
  for (final e in tally.entries) {
    final rate = 100 * e.value.rejected / e.value.n;
    final label = e.key.startsWith('kid') ? 'false-reject' : 'detected';
    print(
      '  ${e.key.padRight(40)} ${e.value.rejected}/${e.value.n} '
      '$label ${rate.toStringAsFixed(1)}%',
    );
  }
}

String _row(String name, String verdict, AuthenticitySignals s) {
  String f(double v, [int d = 2]) => v.toStringAsFixed(d).padLeft(5);
  return '${(name.length > 40 ? name.substring(0, 40) : name).padRight(40)} '
      '${verdict.padRight(11)} ${f(s.paperLikeness)} ${f(s.photoLikelihood)} '
      '${f(s.polish)} ${f(s.noiseLevel)} ${f(s.exactFlatShare)} '
      '${f(s.lumaPeriodicity, 1)} ${f(s.chromaPeriodicity, 1)} '
      '${s.periodicPatches}/${s.patchCount}';
}
