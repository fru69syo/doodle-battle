import 'dart:math' as math;

import 'package:doodle_battle/features/ar/ar_support.dart';
import 'package:doodle_battle/features/ar/ar_view_screen.dart';
import 'package:doodle_battle/features/ar/capture/photo_saver.dart';
import 'package:doodle_battle/features/ar/glb/standee_glb.dart';
import 'package:doodle_battle/features/ar/native/ar_native_view.dart';
import 'package:doodle_battle/features/ar/native/arcore_stage.dart';
import 'package:doodle_battle/features/ar/placement_transform.dart';
import 'package:doodle_battle/features/ar/sample_cutout.dart';
import 'package:doodle_battle/features/ar/simple_ar/photo_compositor.dart';
import 'package:doodle_battle/features/ar/widgets/ar_overlays.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlacementTransform', () {
    test('pinch scales relative to gesture start and clamps', () {
      final t = PlacementTransform();
      t.begin();
      t.update(scaleFactor: 2);
      expect(t.scale, 2);
      t.begin();
      t.update(scaleFactor: 10);
      expect(t.scale, t.maxScale);
      t.begin();
      t.update(scaleFactor: 0.01);
      expect(t.scale, t.minScale);
    });

    test('twist accumulates; clockwise twist = negative yaw', () {
      final t = PlacementTransform();
      t.begin();
      t.update(rotationDelta: math.pi / 2);
      expect(t.yawDegrees, closeTo(-90, 1e-9));
      t.begin();
      t.update(rotationDelta: math.pi);
      // 3π/2 normalised to -π/2.
      expect(t.rotation, closeTo(-math.pi / 2, 1e-9));
      expect(t.yawDegrees, closeTo(90, 1e-9));
    });

    test('drag accumulates offset', () {
      final t = PlacementTransform();
      t.begin();
      t.update(panDelta: const Offset(10, 5));
      t.update(panDelta: const Offset(-3, 1));
      expect(t.offset, const Offset(7, 6));
    });
  });

  group('mode decision', () {
    test('supported → AR, missing ARCore → offer install or fallback', () {
      expect(
        decideArMode(ArSupport.supported, allowInstallPrompt: true),
        ArMode.ar,
      );
      expect(
        decideArMode(ArSupport.needsInstall, allowInstallPrompt: true),
        ArMode.offerInstall,
      );
      expect(
        decideArMode(ArSupport.needsInstall, allowInstallPrompt: false),
        ArMode.simple,
      );
      expect(
        decideArMode(ArSupport.unsupported, allowInstallPrompt: true),
        ArMode.simple,
      );
      expect(
        decideArMode(ArSupport.unknown, allowInstallPrompt: true),
        ArMode.simple,
      );
    });

    test('guide hints', () {
      expect(
        arGuideText(ArGuideState.searching, null)!.text,
        ArStrings.findPlane,
      );
      expect(
        arGuideText(ArGuideState.searching, 'INSUFFICIENT_LIGHT')!.sub,
        ArStrings.tooDark,
      );
      expect(
        arGuideText(ArGuideState.readyToPlace, null)!.text,
        ArStrings.tapToPlace,
      );
      expect(arGuideText(ArGuideState.placed, null), isNull);
      expect(
        arGuideText(ArGuideState.placed, 'EXCESSIVE_MOTION')!.text,
        ArStrings.tooFast,
      );
    });
  });

  group('platform channel', () {
    final log = <MethodCall>[];
    String? availability;
    setUp(() {
      log.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(arChannel, (call) async {
            log.add(call);
            return switch (call.method) {
              'checkAvailability' => availability,
              'requestInstall' => 'requested',
              'requestCameraPermission' => 'permanentlyDenied',
              _ => null,
            };
          });
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(arChannel, null);
    });

    test('checkArSupport maps native answers', () async {
      for (final (native, expected) in [
        ('supported', ArSupport.supported),
        ('needsInstall', ArSupport.needsInstall),
        ('unsupported', ArSupport.unsupported),
        ('unknown', ArSupport.unknown),
        (null, ArSupport.unknown),
      ]) {
        availability = native;
        expect(await checkArSupport(), expected);
      }
    });

    test('checkArSupport is unsupported off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await checkArSupport(), ArSupport.unsupported);
      expect(log, isEmpty);
    });

    test('install + permission', () async {
      expect(
        await requestArCoreInstall(userRequested: false),
        ArInstallResult.requested,
      );
      expect(log.last.arguments, {'userRequested': false});
      expect(
        await const ArPlatform().requestCameraPermission(),
        CameraPermission.permanentlyDenied,
      );
    });

    test('native view controller forwards calls and events', () async {
      const ch = MethodChannel('doodle_battle/ar_view_7');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, (call) async {
            calls.add(call);
            return switch (call.method) {
              'placeAt' => true,
              'capture' => Uint8List.fromList([1, 2, 3]),
              _ => null,
            };
          });
      final c = ArNativeController(7);
      final events = <ArNativeEvent>[];
      c.events.listen(events.add);

      expect(await c.placeAt(const Offset(100, 200)), true);
      expect(calls.last.arguments, {'x': 100.0, 'y': 200.0});
      await c.setTransform(scale: 1.5, yaw: -30);
      expect(calls.last.arguments, {'scale': 1.5, 'yaw': -30.0});
      expect(await c.capture(), [1, 2, 3]);

      // Native → Dart event.
      final data = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onEvent', {'type': 'planes', 'detected': true}),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(ch.name, data, (_) {});
      await Future<void>.delayed(Duration.zero);
      expect(events.single.type, 'planes');
      expect(events.single.data['detected'], true);
      c.dispose();
    });
  });

  group('かんたん AR photo', () {
    test('cover mapping crops the centre of a taller photo', () {
      final m = CoverMapping(
        viewport: const Size(400, 800),
        photo: const Size(1000, 1000),
      );
      expect(m.scale, 0.8);
      final r = m.visibleRect;
      expect(r.width, 500);
      expect(r.height, 1000);
      expect(r.left, 250);
      expect(m.toCropped(const Offset(200, 400)), const Offset(250, 500));
    });

    test('composes the sprite at the placement and crops to viewport', () {
      final standee = buildStandeeGlb(buildSampleCutoutPng());
      // Uniform blue "camera photo", 600x1200 (portrait).
      final photo = img.Image(width: 600, height: 1200);
      img.fill(photo, color: img.ColorRgb8(0, 0, 255));
      final out = composeArPhoto(
        ArPhotoRequest(
          photoBytes: img.encodeJpg(photo),
          viewport: const Size(300, 600),
          placement: const SpritePlacement(
            anchor: Offset(150, 500),
            pixelScale: 0.5,
            rotation: 0,
          ),
          spritePng: standee.spritePng,
        ),
      );
      final result = img.decodeJpg(out)!;
      expect(result.width, 600);
      expect(result.height, 1200);
      // Feet at (300, 1000) in the photo; just above them is the paper.
      final onSprite = result.getPixel(300, 960);
      expect(onSprite.b, lessThan(200));
      // Far corner keeps the photo.
      final corner = result.getPixel(10, 10);
      expect(corner.b, greaterThan(200));
    });

    test('rotation keeps the feet in place', () {
      final standee = buildStandeeGlb(buildSampleCutoutPng());
      final photo = img.Image(width: 300, height: 600);
      img.fill(photo, color: img.ColorRgb8(0, 0, 255));
      final out = img.decodeJpg(
        composeArPhoto(
          ArPhotoRequest(
            photoBytes: img.encodeJpg(photo),
            viewport: const Size(300, 600),
            placement: const SpritePlacement(
              anchor: Offset(150, 500),
              pixelScale: 0.4,
              rotation: math.pi / 2,
            ),
            spritePng: standee.spritePng,
          ),
        ),
      )!;
      // Rotated 90° clockwise: the body now extends to the right of the feet.
      expect(out.getPixel(150 + 40, 500).b, lessThan(200));
      expect(out.getPixel(150 - 60, 500 - 60).b, greaterThan(200));
    });
  });

  test('photo file name', () {
    expect(
      photoFileName(DateTime(2026, 10, 9, 7, 5, 3)),
      'rakugaki_ar_20261009_070503',
    );
  });
}
