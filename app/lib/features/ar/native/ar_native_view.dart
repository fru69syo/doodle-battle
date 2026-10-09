import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// View type registered by `ArPlugin.kt`.
const arViewType = 'doodle_battle/ar_view';

/// Event sent by the native AR view.
@immutable
class ArNativeEvent {
  const ArNativeEvent(this.type, [this.data = const {}]);

  /// `planes` ({detected: bool}), `tracking` ({reason: String?}), `placed`,
  /// `modelLoaded`, `modelFailed`, `sessionFailed` ({message}).
  final String type;
  final Map<String, Object?> data;

  @override
  String toString() => 'ArNativeEvent($type, $data)';
}

/// Talks to one native AR view instance (`doodle_battle/ar_view_<id>`).
class ArNativeController {
  ArNativeController(int viewId)
    : _channel = MethodChannel('doodle_battle/ar_view_$viewId') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _events = StreamController<ArNativeEvent>.broadcast();
  bool _disposed = false;

  Stream<ArNativeEvent> get events => _events.stream;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'onEvent' && !_disposed) {
      final map = (call.arguments as Map).cast<String, Object?>();
      _events.add(ArNativeEvent(map['type']! as String, map));
    }
    return null;
  }

  /// Hit-tests a horizontal plane at [physicalPx] (view-local, physical
  /// pixels) and places/moves the character there. Returns false when no
  /// plane was hit.
  Future<bool> placeAt(Offset physicalPx) async =>
      await _channel.invokeMethod<bool>('placeAt', {
        'x': physicalPx.dx,
        'y': physicalPx.dy,
      }) ??
      false;

  Future<void> setTransform({required double scale, required double yaw}) =>
      _channel.invokeMethod('setTransform', {'scale': scale, 'yaw': yaw});

  Future<void> setPlanesVisible(bool visible) =>
      _channel.invokeMethod('setPlanesVisible', {'visible': visible});

  /// JPEG of the current camera + 3D frame (what the user sees, without the
  /// Flutter UI on top).
  Future<Uint8List> capture() async {
    final bytes = await _channel.invokeMethod<Uint8List>('capture');
    if (bytes == null) throw PlatformException(code: 'capture_failed');
    return bytes;
  }

  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    _events.close();
  }
}

/// Hosts the native ARCore/SceneView view.
///
/// Gestures are NOT forwarded to the platform view: the parent handles taps
/// and pinches in Flutter and calls the [ArNativeController].
class ArNativeView extends StatelessWidget {
  const ArNativeView({
    super.key,
    required this.glbPath,
    required this.onCreated,
  });

  /// Absolute path of the standee GLB on device.
  final String glbPath;
  final ValueChanged<ArNativeController> onCreated;

  /// Texture Layer Hybrid Composition (falls back to Hybrid Composition when
  /// unsupported). The native scene renders into a TextureView, which works
  /// with both. Flip to true to force Hybrid Composition if a device shows
  /// rendering issues.
  static const forceHybridComposition = false;

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: arViewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (params) {
        final args = {'glbPath': glbPath};
        final AndroidViewController controller = forceHybridComposition
            ? PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: arViewType,
                layoutDirection: TextDirection.ltr,
                creationParams: args,
                creationParamsCodec: const StandardMessageCodec(),
              )
            : PlatformViewsService.initSurfaceAndroidView(
                id: params.id,
                viewType: arViewType,
                layoutDirection: TextDirection.ltr,
                creationParams: args,
                creationParamsCodec: const StandardMessageCodec(),
              );
        controller
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(
            (id) => onCreated(ArNativeController(id)),
          )
          ..create();
        return controller;
      },
    );
  }
}
