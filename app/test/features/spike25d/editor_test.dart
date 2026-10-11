import 'dart:io';
import 'dart:ui' as ui;

import 'package:doodle_battle/features/spike25d/editor/joint_editor_screen.dart';
import 'package:doodle_battle/features/spike25d/editor/rig_edit.dart';
import 'package:doodle_battle/features/spike25d/rig/rig.dart';
import 'package:doodle_battle/features/spike25d/samples25d.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_util.dart';

void main() {
  testWidgets('joint editor: drag a hand, save', (tester) async {
    await tester.runAsync(loadAppFonts);
    tester.view.physicalSize = const Size(393 * 2, 851 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = MemoryRigStore();
    final key = GlobalKey<JointEditorScreenState>();
    final boundary = GlobalKey();
    // A stick figure whose right hand we "fix".
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'ZenMaruGothic'),
        home: RepaintBoundary(
          key: boundary,
          child: JointEditorScreen(
            key: key,
            png: sample25dPng(Sample25d.stick),
            imageHash: 'h1',
            store: store,
          ),
        ),
      ),
    );
    for (var i = 0; i < 50 && key.currentState?.rig == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    final st = key.currentState!;
    final rig = st.rig!;
    final arm = rig.limbs.indexWhere(
      (l) => l.kind == LimbKind.arm && l.tip.x > rig.root.x,
    );
    expect(arm, isNonNegative);
    // Drag that hand's handle upward on screen.
    final canvas = find.byKey(const ValueKey('rig-canvas'));
    final box = tester.getRect(canvas);
    final sx = (box.width - 48) / rig.width,
        sy = (box.height - 48) / rig.height;
    final s = sx < sy ? sx : sy;
    final o =
        box.topLeft +
        Offset(
          (box.width - rig.width * s) / 2,
          (box.height - rig.height * s) / 2,
        );
    final hand = o + Offset(rig.limbs[arm].tip.x * s, rig.limbs[arm].tip.y * s);
    await tester.dragFrom(hand, const Offset(0, -90));
    await tester.pump();
    final moved = st.rig!.limbs[arm].tip;
    expect(moved.y, lessThan(rig.limbs[arm].tip.y - 30));
    expect(st.rig!.source, 'edited');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
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
    await tester.tap(find.text('できた！'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final saved = await tester.runAsync(() => store.load('h1'));
    expect(saved!.limbs[arm].tip.y, closeTo(moved.y, 0.1));
    await tester.pumpWidget(const SizedBox());
  });
}
