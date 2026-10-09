import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ar_effects.dart';
import '../glb/standee_glb.dart';
import '../placement_transform.dart';
import '../widgets/ar_overlays.dart';
import 'photo_compositor.dart';
import 'standee_sprite.dart';

/// Something that can produce the photo for the shutter button.
abstract interface class ArCaptureSource {
  /// JPEG of what the user sees (without buttons/hints).
  Future<Uint8List> capture();
}

/// 「かんたん AR」: camera preview with the paper standee overlaid. Drag to
/// move, pinch to scale, twist to rotate. Used when ARCore is unavailable.
class SimpleArStage extends StatefulWidget {
  const SimpleArStage({
    super.key,
    required this.standee,
    required this.effects,
    this.onCameraError,
    this.cameraBuilder,
  });

  final StandeeGlb standee;
  final ArEffects effects;
  final ValueChanged<Object>? onCameraError;

  /// Test hook: replaces the camera preview.
  @visibleForTesting
  final WidgetBuilder? cameraBuilder;

  @override
  State<SimpleArStage> createState() => SimpleArStageState();
}

class SimpleArStageState extends State<SimpleArStage>
    with WidgetsBindingObserver
    implements ArCaptureSource {
  CameraController? _camera;
  Object? _error;
  final _transform = PlacementTransform(minScale: 0.3, maxScale: 3.0);
  Size _viewport = Size.zero;
  bool _hintVisible = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.cameraBuilder == null) _initCamera();
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _hintVisible = false);
    });
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('no_camera', 'no camera');
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      widget.onCameraError?.call(e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _camera;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (c != null) {
        _camera = null;
        c.dispose();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed &&
        _camera == null &&
        widget.cameraBuilder == null) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hintTimer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  /// Logical px per sprite px at transform scale 1: the paper is ~38% of the
  /// viewport height (and at most 75% of its width).
  double _basePixelScale(Size viewport) {
    final s = widget.standee;
    return math.min(
      0.38 * viewport.height / s.spriteHeight,
      0.75 * viewport.width / s.spriteWidth,
    );
  }

  Offset _anchor(Size viewport) =>
      Offset(viewport.width / 2, viewport.height * 0.78) + _transform.offset;

  SpritePlacement get placement => SpritePlacement(
    anchor: _anchor(_viewport),
    pixelScale: _basePixelScale(_viewport) * _transform.scale,
    rotation: _transform.rotation,
  );

  @override
  Future<Uint8List> capture() async {
    final c = _camera;
    if (c == null || !c.value.isInitialized) {
      throw StateError('camera not ready');
    }
    final shot = await c.takePicture();
    final bytes = await shot.readAsBytes();
    return composeArPhotoInBackground(
      ArPhotoRequest(
        photoBytes: bytes,
        viewport: _viewport,
        placement: placement,
        spritePng: widget.standee.spritePng,
        auraPng: widget.standee.auraPng,
        sparkles: widget.effects.sparkles,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        final p = placement;
        final layer = StandeeSprite.layerSize(widget.standee, p.pixelScale);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (_) => _transform.begin(),
          onScaleUpdate: (d) => setState(
            () => _transform.update(
              scaleFactor: d.scale,
              rotationDelta: d.pointerCount >= 2 ? d.rotation : 0,
              panDelta: d.focalPointDelta,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _preview(context),
              Positioned(
                left: p.anchor.dx - layer.width / 2,
                top: p.anchor.dy - layer.height,
                width: layer.width,
                height: layer.height,
                child: Transform.rotate(
                  angle: p.rotation,
                  alignment: Alignment.bottomCenter,
                  child: StandeeSprite(
                    standee: widget.standee,
                    pixelScale: p.pixelScale,
                    sparkles: widget.effects.sparkles,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.paddingOf(context).top + 80,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hintVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: const Center(
                      child: ArHintBubble(
                        text: ArStrings.simpleAr,
                        subText: ArStrings.simpleHint,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _preview(BuildContext context) {
    if (widget.cameraBuilder != null) return widget.cameraBuilder!(context);
    final c = _camera;
    if (_error != null) {
      return const ColoredBox(
        color: Color(0xFF8EC5FC),
        child: Center(
          child: Icon(Icons.no_photography, size: 64, color: Colors.white70),
        ),
      );
    }
    if (c == null || !c.value.isInitialized || c.value.previewSize == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // previewSize is reported in landscape; the app shows it in portrait.
    final ps = c.value.previewSize!;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: math.min(ps.width, ps.height),
          height: math.max(ps.width, ps.height),
          child: CameraPreview(c),
        ),
      ),
    );
  }
}
