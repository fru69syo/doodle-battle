import 'dart:io';
import 'dart:ui' as ui;

import 'package:doodle_battle/features/spike25d/battle/battle_25d_screen.dart';
import 'package:doodle_battle/features/spike25d/battle/battle_session25.dart';
import 'package:doodle_battle/features/spike25d/samples25d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

/// Renders the 2.5D battle headlessly (software Skia, i.e. the same
/// Canvas path as GLES2 phones) and writes frames to docs/v2_25d/ with
/// SPIKE25D_WRITE_DOCS=1. Also measures the CPU cost per frame.
void main() {
  Future<void> run(
    WidgetTester tester, {
    required String name,
    required Side25 player,
    required Side25 cpu,
    required Map<double, String> shots,
    Map<double, int> taps = const {},
    int seed = 7,
    double until = 30,
    String? outDir,
  }) async {
    await tester.runAsync(loadAppFonts);
    tester.view.physicalSize = const Size(393 * 2, 851 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey<Battle25dScreenState>();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'ZenMaruGothic'),
        home: RepaintBoundary(
          key: boundary,
          child: Battle25dScreen(
            key: key,
            player: player,
            cpu: cpu,
            seed: seed,
            autoStart: false,
          ),
        ),
      ),
    );
    // Character build + texture upload are real async work.
    for (var i = 0; i < 50 && key.currentState?.session == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final st = key.currentState!;
    expect(st.session, isNotNull);
    const dt = 1 / 30;
    var t = 0.0;
    final pending = Map.of(shots);
    final pendingTaps = Map.of(taps);
    var frames = 0;
    double? overAt;
    final sw = Stopwatch();
    while (t < until && pending.isNotEmpty) {
      for (final e in pendingTaps.entries.toList()) {
        if (t >= e.key) {
          st.session!.tap(e.value);
          pendingTaps.remove(e.key);
        }
      }
      sw.start();
      st.advance(dt);
      sw.stop();
      frames++;
      t += dt;
      if (overAt == null && st.session!.over) overAt = t;
      for (final e in pending.entries.toList()) {
        // Negative keys: seconds after the KO.
        final due = e.key >= 0
            ? t >= e.key
            : overAt != null && t >= overAt + -e.key;
        if (due) {
          pending.remove(e.key);
          await tester.pump();
          final dir = outDir ?? renderDir();
          if (dir != null) {
            await tester.runAsync(() async {
              final ro =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final img = await ro.toImage(pixelRatio: 1.5);
              final png = await img.toByteData(format: ui.ImageByteFormat.png);
              File('$dir/${e.value}.png')
                ..createSync(recursive: true)
                ..writeAsBytesSync(png!.buffer.asUint8List());
              img.dispose();
            });
          }
        }
      }
    }
    // ignore: avoid_print
    print(
      '$name: $frames frames, advance avg ${(sw.elapsedMicroseconds / frames).toStringAsFixed(0)} µs, battle ${st.battleSeconds}s, over=${st.session!.over}',
    );
    await tester.pumpWidget(const SizedBox());
  }

  final strip = Platform.environment['SPIKE25D_STRIP'];
  testWidgets('frame strip (debug)', (tester) async {
    await run(
      tester,
      name: 'strip',
      player: Side25(
        png: sample25dPng(Sample25d.hero),
        name: 'ぼく',
        level: 12,
        genomeSeed: 11,
      ),
      cpu: Side25(
        png: sample25dPng(Sample25d.dog),
        name: 'わんこ',
        level: 12,
        genomeSeed: 5,
      ),
      taps: {0.2: 0, 4.2: 2, 8.5: 1},
      shots: {
        for (var i = 0; i < 40; i++)
          2.0 + i * 0.2: 'strip_${i.toString().padLeft(2, '0')}',
      },
      outDir: strip,
    );
  }, skip: strip == null);

  testWidgets('battle frames: hero vs dog', (tester) async {
    await run(
      tester,
      name: 'hero-dog',
      player: Side25(
        png: sample25dPng(Sample25d.hero),
        name: 'ぼく',
        level: 12,
        genomeSeed: 11,
      ),
      cpu: Side25(
        png: sample25dPng(Sample25d.dog),
        name: 'わんこ',
        level: 12,
        genomeSeed: 5,
      ),
      taps: {0.2: 0, 4.2: 2, 8.5: 1},
      shots: {
        1.0: 'battle_start',
        3.2: 'battle_choose',
        3.85: 'battle_hit',
        6.0: 'battle_6s',
        9.5: 'battle_9s',
      },
    );
  });

  testWidgets('battle frames: blob vs simplified (hidden late bloomer)', (
    tester,
  ) async {
    await run(
      tester,
      name: 'blob-bloomer',
      player: Side25(
        png: sample25dPng(Sample25d.blob),
        name: 'ぷにぷに',
        level: 12,
        genomeSeed: 3,
      ),
      cpu: Side25(
        png: sample25dPng(Sample25d.hero),
        name: 'ひみつ',
        level: 12,
        bloomer: true,
        genomeSeed: 9,
      ),
      taps: {0.2: 1},
      shots: {3.9: 'battle_blob_vs_simple', -0.7: 'battle_ko'},
      until: 120,
    );
  });

  testWidgets('battle frames: Lv50 legend (rebuilt late bloomer) vs car', (
    tester,
  ) async {
    await run(
      tester,
      name: 'legend-car',
      player: Side25(
        png: sample25dPng(Sample25d.stick),
        name: 'ぼうにんげん',
        level: 50,
        genomeSeed: 21,
      ),
      cpu: Side25(
        png: sample25dPng(Sample25d.hero),
        name: 'ひみつ',
        level: 50,
        bloomer: true,
        genomeSeed: 9,
      ),
      taps: {0.2: 3},
      shots: {4.1: 'battle_lv50'},
    );
  });
}
