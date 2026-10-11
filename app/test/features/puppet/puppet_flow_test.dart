import 'package:doodle_battle/domain/drawing_analysis_result.dart';
import 'package:doodle_battle/features/draw/draw_flow.dart';
import 'package:doodle_battle/features/draw_canvas/canvas_analysis.dart';
import 'package:doodle_battle/features/draw_canvas/draw_canvas_screen.dart';
import 'package:doodle_battle/features/puppet/editor/joint_editor_screen.dart';
import 'package:doodle_battle/features/puppet/puppet_store.dart';
import 'package:doodle_battle/features/puppet/samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';
import '../draw_canvas/draw_canvas_test.dart' show kidDrawing;

/// Real async work (image decoding / encoding) inside a widget test.
Future<void> settleReal(WidgetTester tester, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('after birth: うごく ところを なおそう, あとで → character page', (
    tester,
  ) async {
    final store = InMemoryPuppetStore();
    final app = await pumpApp(
      tester,
      jointEditorAfterBirth: true,
      analyzer: FakeAnalyzer(result: _withCutout(fakeAnalysis())),
      overrides: [puppetStoreProvider.overrideWithValue(store)],
    );
    await tapVisible(tester, find.byKey(const Key('home-draw')));
    await tapVisible(tester, find.byKey(const Key('draw-camera')));
    await tapVisible(tester, find.byKey(const Key('guide-shoot')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('birth-name')));
    await tester.enterText(find.byKey(const Key('name-field')), 'うごくん');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('name-save')));
    await settleReal(tester);
    expect(find.byType(JointEditorScreen), findsOneWidget);
    expect(find.text('うごく ところを なおそう'), findsOneWidget);
    expect(find.byKey(const Key('joint-preview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('joint-skip')));
    await settleReal(tester, rounds: 5);
    expect(find.byKey(const Key('detail-level')), findsOneWidget);
    final id = (await app.characters.loadAll()).single.id;
    expect(await store.loadRigJson(id), isNull, reason: 'skipped');
    // From the character page: うごく ところを なおす → できた！ saves.
    await tester.scrollUntilVisible(
      find.byKey(const Key('detail-joints')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-joints')));
    await settleReal(tester);
    await tester.tap(find.byKey(const Key('joint-add-tail')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('joint-done')));
    await settleReal(tester, rounds: 5);
    expect(await store.loadRigJson(id), isNotNull);
    expect(find.byType(JointEditorScreen), findsNothing);
    expect(find.byKey(const Key('detail-joints')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('アプリで かく → analysis → birth; strokes kept on the phone', (
    tester,
  ) async {
    final store = InMemoryPuppetStore();
    final app = await pumpApp(
      tester,
      overrides: [
        puppetStoreProvider.overrideWithValue(store),
        canvasAnalyzerProvider.overrideWithValue(
          (png) async => analyzeCanvasDrawingSync(png),
        ),
      ],
    );
    await tapVisible(tester, find.byKey(const Key('home-draw')));
    expect(find.byKey(const Key('draw-camera')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('draw-in-app')));
    expect(find.byType(DrawCanvasScreen), findsOneWidget);
    // Draw (programmatically: the controller takes the kid drawing).
    final st = tester.state<DrawCanvasScreenState>(
      find.byType(DrawCanvasScreen),
    );
    for (final s in kidDrawing().strokes) {
      st.controller.setTool(s.tool);
      st.controller.setColor(s.color);
      st.controller.setTool(s.tool);
      st.controller.begin(s.xy[0], s.xy[1]);
      for (var i = 2; i < s.xy.length; i += 2) {
        st.controller.extend(s.xy[i], s.xy[i + 1]);
      }
      st.controller.end();
    }
    await tester.pump();
    await tester.tap(find.byKey(const Key('canvas-done')));
    await settleReal(tester, rounds: 60);
    expect(app.analyzer.calls, 0, reason: 'the photo analyzer is not used');
    await tester.pumpAndSettle();
    expect(find.text('うまれたよ！'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('birth-name')));
    await tester.enterText(find.byKey(const Key('name-field')), 'かいたくん');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('name-save')));
    final c = (await app.characters.loadAll()).single;
    expect(c.skill, lessThan(75));
    final rec = await store.loadStrokesJson(c.id);
    expect(hintStrokesFromRecord(rec), hasLength(kidDrawing().strokes.length));
    await unmount(tester);
  });
}

DrawingAnalysisResult _withCutout(DrawingAnalysisResult r) =>
    DrawingAnalysisResult(
      cutoutPng: samplePng(Sample.hero),
      imageHash: r.imageHash,
      features: r.features,
      energy: r.energy,
      skill: r.skill,
      element: r.element,
      baseStats: r.baseStats,
    );
