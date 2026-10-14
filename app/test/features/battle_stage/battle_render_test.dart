import 'dart:io';
import 'dart:ui' as ui;

import 'package:doodle_battle/features/battle_stage/battle_stage.dart';
import 'package:doodle_battle/features/battle_stage/debug/demo_battle.dart';
import 'package:doodle_battle/features/puppet/puppet_builder.dart';
import 'package:doodle_battle/features/puppet/render/puppet_view.dart';
import 'package:doodle_battle/features/puppet/samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../puppet/render_util.dart';

/// Renders the 2.5D battle headlessly (software Skia, i.e. the same
/// Canvas path as GLES2 phones) and writes frames to docs/v2_25d/ with
/// PUPPET_WRITE_DOCS=1. Also measures the CPU cost per frame.
void main() {
  Future<void> run(
    WidgetTester tester, {
    required String name,
    required DemoSide player,
    required DemoSide cpu,
    StageTheme theme = StageTheme.meadow,
    StageQuality? quality,
    required Map<double, String> shots,
    Map<double, int> taps = const {},
    int seed = 7,
    double until = 30,
    String? outDir,
    double cpuSize = 1,
  }) async {
    await tester.runAsync(loadAppFonts);
    tester.view.physicalSize = const Size(393 * 2, 851 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey<DemoBattleScreenState>();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          puppetBuilderProvider.overrideWithValue(
            PuppetBuilder(runner: syncRunner),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'ZenMaruGothic'),
          home: RepaintBoundary(
            key: boundary,
            child: DemoBattleScreen(
              key: key,
              player: player,
              cpu: cpu,
              seed: seed,
              theme: theme,
              quality: quality,
              autoStart: false,
              cpuSize: cpuSize,
            ),
          ),
        ),
      ),
    );
    // Character build + texture upload are real async work.
    for (
      var i = 0;
      i < 80 && key.currentState?.controller.director == null;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final st = key.currentState!;
    expect(st.controller.director, isNotNull);
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
          st.feed.tap(e.value);
          pendingTaps.remove(e.key);
        }
      }
      sw.start();
      st.controller.advance(dt);
      sw.stop();
      frames++;
      t += dt;
      if (overAt == null && st.controller.over) overAt = t;
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
      '$name: $frames frames, advance avg ${(sw.elapsedMicroseconds / frames).toStringAsFixed(0)} µs, battle ${st.feed.engine.tick / 10}s, over=${st.controller.over}',
    );
    await tester.pumpWidget(const SizedBox());
  }

  final strip = Platform.environment['PUPPET_STRIP'];
  testWidgets('frame strip (debug)', (tester) async {
    await run(
      tester,
      name: 'strip',
      player: DemoSide(
        png: samplePng(Sample.hero),
        name: 'ぼく',
        level: 12,
        genomeSeed: 11,
      ),
      cpu: DemoSide(
        png: samplePng(Sample.dog),
        name: 'わんこ',
        level: 12,
        genomeSeed: 5,
      ),
      taps: {0.2: 0, 4.2: 2, 8.5: 1},
      shots: {
        for (var i = 0; i < 40; i++)
          3.6 + i * 0.05: 'strip_${i.toString().padLeft(2, '0')}',
      },
      outDir: strip,
    );
  }, skip: strip == null);

  testWidgets('battle frames: hero vs dog', (tester) async {
    await run(
      tester,
      name: 'hero-dog',
      player: DemoSide(
        png: samplePng(Sample.hero),
        name: 'ぼく',
        level: 12,
        genomeSeed: 11,
      ),
      cpu: DemoSide(
        png: samplePng(Sample.dog),
        name: 'わんこ',
        level: 12,
        genomeSeed: 5,
      ),
      taps: {0.2: 0, 4.2: 2, 8.5: 1},
      shots: {
        1.0: 'battle_start',
        3.2: 'battle_choose',
        4.3: 'battle_hit',
        6.0: 'battle_6s',
        9.5: 'battle_9s',
      },
    );
  });

  testWidgets('battle frames: world boss drawn bigger', (tester) async {
    await run(
      tester,
      name: 'boss',
      player: DemoSide(
        png: samplePng(Sample.hero),
        name: 'ぼく',
        level: 10,
        genomeSeed: 11,
      ),
      cpu: DemoSide(
        png: samplePng(Sample.dog),
        name: 'ボス',
        level: 10,
        genomeSeed: 5,
      ),
      cpuSize: kBossSize,
      taps: {0.2: 0, 4.2: 1},
      shots: {1.0: 'boss_start', 4.3: 'boss_hit', -1.0: 'boss_ko'},
    );
  });

  testWidgets('battle frames: blob vs simplified (hidden late bloomer)', (
    tester,
  ) async {
    await run(
      tester,
      name: 'blob-bloomer',
      player: DemoSide(
        png: samplePng(Sample.blob),
        name: 'ぷにぷに',
        level: 12,
        genomeSeed: 3,
      ),
      cpu: DemoSide(
        png: samplePng(Sample.hero),
        name: 'ひみつ',
        level: 12,
        lateBloomer: true,
        genomeSeed: 9,
      ),
      theme: StageTheme.snow,
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
      player: DemoSide(
        png: samplePng(Sample.stick),
        name: 'ぼうにんげん',
        level: 50,
        genomeSeed: 21,
      ),
      cpu: DemoSide(
        png: samplePng(Sample.hero),
        name: 'ひみつ',
        level: 50,
        lateBloomer: true,
        genomeSeed: 9,
      ),
      theme: StageTheme.night,
      taps: {0.2: 3},
      shots: {4.1: 'battle_lv50'},
    );
  });

  for (final (theme, sample, q) in [
    (StageTheme.beach, Sample.car, null),
    (StageTheme.forest, Sample.stick, null),
    (StageTheme.desert, Sample.blob, null),
    (StageTheme.candy, Sample.dog, null),
    (StageTheme.volcano, Sample.car, StageQuality.low),
  ]) {
    testWidgets('stage theme ${theme.id}', (tester) async {
      await run(
        tester,
        name: 'theme-${theme.id}',
        player: DemoSide(
          png: samplePng(Sample.hero),
          name: 'ぼく',
          genomeSeed: 11,
        ),
        cpu: DemoSide(png: samplePng(sample), name: 'あいて', genomeSeed: 5),
        theme: theme,
        quality: q,
        shots: {3.0: q == null ? 'stage_${theme.id}' : 'stage_${theme.id}_low'},
      );
    });
  }
}
