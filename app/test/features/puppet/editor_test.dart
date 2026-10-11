import 'dart:io';
import 'dart:ui' as ui;

import 'package:doodle_battle/features/puppet/editor/joint_editor_screen.dart';
import 'package:doodle_battle/features/puppet/editor/rig_edits.dart';
import 'package:doodle_battle/features/puppet/puppet_builder.dart';
import 'package:doodle_battle/features/puppet/puppet_store.dart';
import 'package:doodle_battle/features/puppet/render/puppet_view.dart';
import 'package:doodle_battle/features/puppet/rig/character_rig.dart';
import 'package:doodle_battle/features/puppet/samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

void main() {
  Future<(GlobalKey<JointEditorScreenState>, GlobalKey, List<Object?>)> pump(
    WidgetTester tester,
    InMemoryPuppetStore store, {
    bool first = true,
  }) async {
    await tester.runAsync(loadAppFonts);
    tester.view.physicalSize = const Size(393 * 2, 851 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey<JointEditorScreenState>();
    final boundary = GlobalKey();
    final finished = <Object?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          puppetStoreProvider.overrideWithValue(store),
          puppetBuilderProvider.overrideWithValue(
            PuppetBuilder(runner: syncRunner),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'ZenMaruGothic'),
          home: RepaintBoundary(
            key: boundary,
            child: JointEditorScreen(
              key: key,
              characterId: 'c1',
              png: samplePng(Sample.stick),
              firstTime: first,
              onFinished: finished.add,
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 60 && key.currentState?.rig == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return (key, boundary, finished);
  }

  /// Screen position of drawing point [p] (same fit as the editor).
  Offset screenOf(WidgetTester tester, CharacterRig rig, P2 p) {
    final box = tester.getRect(find.byKey(const Key('joint-canvas')));
    const m = kHandleRadius + 10;
    final sx = (box.width - 2 * m) / rig.width;
    final sy = (box.height - 2 * m) / rig.height;
    final s = sx < sy ? sx : sy;
    final o =
        box.topLeft +
        Offset(
          (box.width - rig.width * s) / 2,
          (box.height - rig.height * s) / 2,
        );
    return o + Offset(p.x * s, p.y * s);
  }

  testWidgets('drag a hand, undo, redo by dragging, save', (tester) async {
    final store = InMemoryPuppetStore();
    final (key, boundary, finished) = await pump(tester, store);
    final st = key.currentState!;
    final rig = st.rig!;
    final arm = rig.limbs.indexWhere(
      (l) => l.kind == LimbKind.arm && l.tip.x > rig.root.x,
    );
    expect(arm, isNonNegative);
    final hand = screenOf(tester, rig, rig.limbs[arm].tip);
    await tester.dragFrom(hand, const Offset(0, -90));
    await tester.pump();
    final moved = st.rig!.limbs[arm].tip;
    expect(moved.y, lessThan(rig.limbs[arm].tip.y - 30));
    expect(st.rig!.source, RigSource.edited);
    expect(st.canUndo, isTrue);
    await tester.tap(find.byKey(const Key('joint-undo')));
    await tester.pump();
    expect(st.rig!.limbs[arm].tip, rig.limbs[arm].tip, reason: 'one step');
    // A finger slightly off the handle still grabs it (big hit area).
    await tester.dragFrom(hand + const Offset(20, 15), const Offset(0, -90));
    await tester.pump();
    final moved2 = st.rig!.limbs[arm].tip;
    expect(moved2.y, lessThan(rig.limbs[arm].tip.y - 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final dir = renderDir();
    if (dir != null) {
      await tester.runAsync(() async {
        final ro =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final img = await ro.toImage(pixelRatio: 1.5);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/editor.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    await tester.tap(find.byKey(const Key('joint-done')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final saved = CharacterRig.tryDecode(await store.loadRigJson('c1'));
    expect(saved!.limbs[arm].tip.y, closeTo(moved2.y, 0.1));
    expect(finished.single, isA<CharacterRig>());
    expect(find.byKey(const Key('joint-preview')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('add a tail, select and remove it; reset; skip', (tester) async {
    final store = InMemoryPuppetStore();
    final (key, _, finished) = await pump(tester, store);
    final st = key.currentState!;
    final auto = st.rig!;
    await tester.tap(find.byKey(const Key('joint-add-tail')));
    await tester.pump();
    expect(st.rig!.of(LimbKind.tail).length, 1);
    final tail = st.rig!.limbs.length - 1;
    await tester.tapAt(screenOf(tester, st.rig!, st.rig!.limbs[tail].tip));
    await tester.pump();
    expect(st.selected, tail);
    await tester.tap(find.byKey(const Key('joint-remove')));
    await tester.pump();
    expect(st.rig!.of(LimbKind.tail), isEmpty);
    await tester.tap(find.byKey(const Key('joint-add-arm')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('joint-reset')));
    await tester.pump();
    expect(st.rig!.encode(), auto.encode());
    await tester.tap(find.byKey(const Key('joint-skip')));
    await tester.pump();
    expect(finished.single, isNull);
    expect(await store.loadRigJson('c1'), isNull, reason: 'skip saves nothing');
    await tester.pumpWidget(const SizedBox());
  });

  test('history and limits', () {
    final r = CharacterRig(
      width: 100,
      height: 100,
      root: const P2(50, 80),
      chest: const P2(50, 40),
      limbs: [],
    );
    var x = r;
    for (var i = 0; i < 10; i++) {
      x = RigEdits.addLimb(x, LimbKind.arm);
    }
    expect(x.of(LimbKind.arm).length, RigEdits.maxOf[LimbKind.arm]);
    final h = RigHistory(r);
    for (var i = 0; i < 100; i++) {
      h.push(RigEdits.moveRoot(h.current, P2(50, 80.0 - i % 3)));
    }
    var undos = 0;
    while (h.canUndo) {
      h.undo();
      undos++;
    }
    expect(undos, RigHistory.maxSteps - 1);
    // Removing a limb re-points attachments.
    final withHat = r.copy()
      ..limbs.addAll([
        RigLimb(
          LimbKind.head,
          const P2(50, 40),
          const P2(50, 30),
          const P2(50, 20),
        ),
        RigLimb(
          LimbKind.arm,
          const P2(50, 40),
          const P2(60, 40),
          const P2(70, 40),
        ),
        RigLimb(
          LimbKind.extra,
          const P2(50, 20),
          const P2(50, 15),
          const P2(50, 10),
          attach: 1,
        ),
      ]);
    final removed = RigEdits.removeLimb(withHat, 0);
    expect(removed.limbs.last.attach, 0);
    expect(removed.validate(), isNull);
  });
}
