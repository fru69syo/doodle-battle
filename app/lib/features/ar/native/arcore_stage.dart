import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../placement_transform.dart';
import '../simple_ar/simple_ar_stage.dart' show ArCaptureSource;
import '../widgets/ar_overlays.dart';
import 'ar_native_view.dart';

/// Where the user is in the AR flow; drives the hint overlay.
enum ArGuideState { searching, readyToPlace, placed }

/// Hint text for the current state (null = no bubble).
({String text, String? sub})? arGuideText(
  ArGuideState state,
  String? trackingFailure,
) {
  final failure = switch (trackingFailure) {
    'INSUFFICIENT_LIGHT' => ArStrings.tooDark,
    'EXCESSIVE_MOTION' => ArStrings.tooFast,
    'INSUFFICIENT_FEATURES' => ArStrings.noTexture,
    _ => null,
  };
  return switch (state) {
    ArGuideState.searching => (
      text: ArStrings.findPlane,
      sub: failure ?? ArStrings.findPlaneSub,
    ),
    ArGuideState.readyToPlace => (text: ArStrings.tapToPlace, sub: failure),
    ArGuideState.placed => failure == null ? null : (text: failure, sub: null),
  };
}

/// ARCore stage: native view + Flutter gestures and hints.
class ArCoreStage extends StatefulWidget {
  const ArCoreStage({
    super.key,
    required this.glbPath,
    required this.onSessionFailed,
  });

  final String glbPath;
  final ValueChanged<String> onSessionFailed;

  @override
  State<ArCoreStage> createState() => ArCoreStageState();
}

class ArCoreStageState extends State<ArCoreStage> implements ArCaptureSource {
  ArNativeController? _controller;
  StreamSubscription<ArNativeEvent>? _sub;
  var _guide = ArGuideState.searching;
  String? _trackingFailure;
  bool _showGestureTip = false;
  Timer? _tipTimer;
  final _transform = PlacementTransform();
  int _pointers = 0;
  DateTime _lastDragPlace = DateTime.fromMillisecondsSinceEpoch(0);

  void _onCreated(ArNativeController c) {
    _controller = c;
    _sub = c.events.listen(_onEvent);
  }

  void _onEvent(ArNativeEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case 'planes':
        final detected = e.data['detected'] == true;
        if (_guide != ArGuideState.placed) {
          setState(
            () => _guide = detected
                ? ArGuideState.readyToPlace
                : ArGuideState.searching,
          );
        }
      case 'tracking':
        setState(() => _trackingFailure = e.data['reason'] as String?);
      case 'placed':
        if (_guide != ArGuideState.placed) {
          _controller?.setPlanesVisible(false);
          setState(() {
            _guide = ArGuideState.placed;
            _showGestureTip = true;
          });
          _tipTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _showGestureTip = false);
          });
        }
      case 'sessionFailed':
      case 'modelFailed':
        widget.onSessionFailed('${e.data['message'] ?? e.type}');
    }
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _sub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Future<Uint8List> capture() async {
    final c = _controller;
    if (c == null) throw StateError('AR view not ready');
    return c.capture();
  }

  Future<void> _placeAt(Offset local) async {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    await _controller?.placeAt(local * dpr);
  }

  @override
  Widget build(BuildContext context) {
    final hint = arGuideText(_guide, _trackingFailure);
    return Stack(
      fit: StackFit.expand,
      children: [
        ArNativeView(glbPath: widget.glbPath, onCreated: _onCreated),
        Listener(
          onPointerDown: (_) => _pointers++,
          onPointerUp: (_) => _pointers--,
          onPointerCancel: (_) => _pointers--,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _placeAt(d.localPosition),
            onScaleStart: (_) => _transform.begin(),
            onScaleUpdate: (d) {
              if (_guide != ArGuideState.placed) return;
              if (d.pointerCount >= 2 || _pointers >= 2) {
                _transform.update(
                  scaleFactor: d.scale,
                  rotationDelta: d.rotation,
                );
                _controller?.setTransform(
                  scale: _transform.scale,
                  yaw: _transform.yawDegrees,
                );
              } else {
                // One finger: drag the character along the floor (throttled).
                final now = DateTime.now();
                if (now.difference(_lastDragPlace).inMilliseconds > 80) {
                  _lastDragPlace = now;
                  _placeAt(d.localFocalPoint);
                }
              }
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.paddingOf(context).top + 80,
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: hint != null
                  ? ArHintBubble(
                      key: ValueKey(hint.text),
                      text: hint.text,
                      subText: hint.sub,
                      icon: _guide == ArGuideState.searching
                          ? const ScanAnimation()
                          : null,
                    )
                  : _showGestureTip
                  ? const ArHintBubble(
                      key: ValueKey('tip'),
                      text: ArStrings.gestureTip,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}
