import 'dart:io';
import 'dart:typed_data';

import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/features/ar/ar_support.dart';
import 'package:doodle_battle/features/ar/ar_view_screen.dart';
import 'package:doodle_battle/features/ar/sample_cutout.dart';
import 'package:doodle_battle/features/ar/simple_ar/simple_ar_stage.dart';
import 'package:doodle_battle/features/ar/simple_ar/standee_sprite.dart';
import 'package:doodle_battle/features/ar/widgets/ar_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform extends ArPlatform {
  FakePlatform({
    this.support = ArSupport.unsupported,
    this.permission = CameraPermission.granted,
    this.install = ArInstallResult.declined,
  });

  ArSupport support;
  CameraPermission permission;
  ArInstallResult install;
  int permissionRequests = 0;
  int installRequests = 0;

  @override
  Future<ArSupport> checkArSupport() async => support;

  @override
  Future<CameraPermission> requestCameraPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<ArInstallResult> requestArCoreInstall({
    bool userRequested = true,
  }) async {
    installRequests++;
    return install;
  }

  @override
  Future<CameraPermission> checkCameraPermission() async => permission;

  @override
  Future<bool> openAppSettings() async => true;
}

CharacterV2 character({int level = 1}) => CharacterV2.create(
  id: 'c1',
  name: 'てすと',
  imagePath: '/sample.png',
  imageHash: 'abcdef0123456789abcdef',
  rawFeatures: const {},
  energy: 60,
  skill: 20,
  createdAt: DateTime(2026),
  legacyElement: ElementType.leaf,
).copyWith(level: level);

void main() {
  late Directory tmp;
  final png = buildSampleCutoutPng();

  setUp(() => tmp = Directory.systemTemp.createTempSync('ar_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pumpScreen(
    WidgetTester tester,
    FakePlatform platform, {
    CharacterV2? c,
    bool allowInstall = true,
    Future<Uint8List> Function(String)? readImage,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArViewScreen(
          character: c ?? character(),
          allowArCoreInstallPrompt: allowInstall,
          dependencies: ArViewDependencies(
            platform: platform,
            readImage: readImage ?? (_) async => png,
            glbDirectory: () async => tmp,
            simpleCameraBuilder: (_) =>
                const ColoredBox(key: Key('fake-camera'), color: Colors.teal),
          ),
        ),
      ),
    );
    // GLB generation runs on a real isolate: let real time pass until the
    // screen leaves the "preparing" state.
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
      if (find.text(ArStrings.preparing).evaluate().isEmpty) break;
    }
  }

  testWidgets('unsupported device → かんたん AR with sprite and shutter', (
    tester,
  ) async {
    final platform = FakePlatform(support: ArSupport.unsupported);
    await pumpScreen(tester, platform);
    expect(find.byType(SimpleArStage), findsOneWidget);
    expect(find.byKey(const Key('fake-camera')), findsOneWidget);
    expect(find.byType(StandeeSprite), findsOneWidget);
    expect(find.byType(ShutterButton), findsOneWidget);
    expect(find.text(ArStrings.simpleHint), findsOneWidget);
    // GLB written for the native path / cache.
    expect(tmp.listSync().single.path, endsWith('_normal_leaf.glb'));
    // Pinch/drag must not throw.
    await tester.drag(find.byType(SimpleArStage), const Offset(30, -20));
    await tester.pump();
    // Let the hint timer elapse.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('camera permission denied → ask again', (tester) async {
    final platform = FakePlatform(permission: CameraPermission.denied);
    await pumpScreen(tester, platform);
    expect(find.text(ArStrings.cameraNeeded), findsOneWidget);
    expect(find.byType(ShutterButton), findsNothing);

    platform.permission = CameraPermission.granted;
    await tester.tap(find.text(ArStrings.cameraAskAgain));
    await tester.pump();
    expect(find.byType(SimpleArStage), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('permanently denied → settings button; resume re-checks', (
    tester,
  ) async {
    final platform = FakePlatform(
      permission: CameraPermission.permanentlyDenied,
    );
    await pumpScreen(tester, platform);
    expect(find.text(ArStrings.openSettings), findsOneWidget);
    final requests = platform.permissionRequests;

    // Back from the system settings with the permission granted.
    platform.permission = CameraPermission.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.byType(SimpleArStage), findsOneWidget);
    // Resuming must not trigger another permission dialog.
    expect(platform.permissionRequests, requests);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('ARCore missing → offer install; declining falls back', (
    tester,
  ) async {
    final platform = FakePlatform(
      support: ArSupport.needsInstall,
      install: ArInstallResult.declined,
    );
    await pumpScreen(tester, platform);
    expect(find.text(ArStrings.installTitle), findsOneWidget);
    await tester.tap(find.text(ArStrings.installYes));
    await tester.pump();
    expect(platform.installRequests, 1);
    expect(find.byType(SimpleArStage), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('install prompt can be disabled', (tester) async {
    await pumpScreen(
      tester,
      FakePlatform(support: ArSupport.needsInstall),
      allowInstall: false,
    );
    expect(find.text(ArStrings.installTitle), findsNothing);
    expect(find.byType(SimpleArStage), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('unreadable image → friendly error', (tester) async {
    await pumpScreen(
      tester,
      FakePlatform(),
      readImage: (_) async => Uint8List.fromList([0, 1, 2]),
    );
    expect(find.text(ArStrings.imageError), findsOneWidget);
  });

  testWidgets('Lv20 character gets aura and sparkles in かんたん AR', (
    tester,
  ) async {
    await pumpScreen(tester, FakePlatform(), c: character(level: 20));
    final sprite = tester.widget<StandeeSprite>(find.byType(StandeeSprite));
    expect(sprite.sparkles, isTrue);
    expect(sprite.standee.auraPng, isNotNull);
    expect(tmp.listSync().single.path, endsWith('_densetsu_leaf.glb'));
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('back button pops', (tester) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ArViewScreen(
          character: character(),
          onBack: () => popped = true,
          dependencies: ArViewDependencies(
            platform: FakePlatform(permission: CameraPermission.denied),
            readImage: (_) async => png,
            glbDirectory: () async => tmp,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip(ArStrings.back));
    expect(popped, isTrue);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
  });
}
