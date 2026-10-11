import 'package:doodle_battle/features/ar/sample_cutout.dart';
import 'package:doodle_battle/features/spike3d/battle/battle_3d_screen.dart';
import 'package:doodle_battle/features/spike3d/battle/battle_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Without Flutter GPU (plain `flutter test`, Skia devices) the screen
/// explains the fallback; with `--enable-impeller --enable-flutter-gpu` it
/// loads the scene and the player can pick a move from the overlay.
void main() {
  testWidgets('3D battle screen: overlay drives the ATB', (tester) async {
    final png = buildSampleCutoutPng();
    tester.view
      ..physicalSize = const Size(360, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Battle3DScreen(playerPng: png, cpuPng: png),
      ),
    );
    if (!flutterGpuAvailable()) {
      await tester.pump();
      expect(find.textContaining('Flutter GPU'), findsOneWidget);
      return;
    }
    // Generation runs on isolates: let real time pass.
    for (
      var i = 0;
      i < 100 && find.byType(FilledButton).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.text('ぽかぽかパンチ'), findsOneWidget);
    // Fill the player's gauge (≈2.8 s of wall time: SceneView measures
    // tick deltas with the real clock), then choose.
    for (
      var i = 0;
      i < 200 && find.textContaining('えらんでね').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.textContaining('えらんでね'), findsOneWidget);
    await tester.tap(find.text('ぐるぐるキック'));
    await tester.pump(const Duration(milliseconds: 50));
    // The menu closes (the move is queued or already playing).
    expect(find.textContaining('えらんでね'), findsNothing);
    // Unmount, then let flutter_scene's time-sliced environment prefilter
    // (which waits on 2 s raster-sync timers) run out.
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(seconds: 3));
    }
  });
}
