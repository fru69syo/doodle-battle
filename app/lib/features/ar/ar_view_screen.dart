import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import 'ar_effects.dart';
import 'ar_support.dart';
import 'capture/photo_saver.dart';
import 'glb/standee_glb.dart';
import 'native/arcore_stage.dart';
import 'simple_ar/simple_ar_stage.dart';
import 'widgets/ar_overlays.dart';

/// Which experience the screen shows.
enum ArMode {
  preparing,
  needCamera,
  offerInstall,
  installing,
  ar,
  simple,
  error,
}

/// Initial mode once the camera permission is granted.
ArMode decideArMode(ArSupport support, {required bool allowInstallPrompt}) =>
    switch (support) {
      ArSupport.supported => ArMode.ar,
      ArSupport.needsInstall =>
        allowInstallPrompt ? ArMode.offerInstall : ArMode.simple,
      ArSupport.unsupported || ArSupport.unknown => ArMode.simple,
    };

/// Injection points (tests, and UI-team configuration).
class ArViewDependencies {
  const ArViewDependencies({
    this.platform = const ArPlatform(),
    this.photoSaver = const PhotoSaver(),
    this.readImage,
    this.glbDirectory,
    this.simpleCameraBuilder,
  });

  final ArPlatform platform;
  final PhotoSaver photoSaver;

  /// Reads the cut-out PNG. Defaults to `File(path).readAsBytes()`.
  final Future<Uint8List> Function(String path)? readImage;

  /// Where generated GLBs are written. Defaults to `<tmp>/ar`.
  final Future<Directory> Function()? glbDirectory;

  /// Replaces the camera preview of かんたん AR (tests).
  final WidgetBuilder? simpleCameraBuilder;
}

/// Shows [character] in the real world (SPEC §6).
///
/// ARCore (plane detection, tap to place, pinch/twist, idle hop, evolution
/// effects) when available, otherwise 「かんたん AR」 (camera preview +
/// sprite). The shutter saves a photo to the gallery.
class ArViewScreen extends StatefulWidget {
  const ArViewScreen({
    super.key,
    required this.character,
    this.allowArCoreInstallPrompt = true,
    this.onBack,
    this.dependencies = const ArViewDependencies(),
  });

  final CharacterV2 character;

  /// Offer installing "Google Play Services for AR" when the device supports
  /// ARCore but it is missing (opens the Play Store). PM decision; see
  /// docs/AR.md.
  final bool allowArCoreInstallPrompt;

  /// Back button handler; defaults to `Navigator.maybePop`.
  final VoidCallback? onBack;

  final ArViewDependencies dependencies;

  @override
  State<ArViewScreen> createState() => _ArViewScreenState();
}

class _ArViewScreenState extends State<ArViewScreen> {
  ArMode _mode = ArMode.preparing;
  ArSupport _support = ArSupport.unknown;
  CameraPermission _permission = CameraPermission.denied;
  StandeeGlb? _standee;
  String? _glbPath;
  late final ArEffects _effects = ArEffects.forCharacter(widget.character);
  final _stageKey = GlobalKey();
  bool _busy = false;
  bool _flash = false;
  AppLifecycleListener? _lifecycle;

  ArViewDependencies get _deps => widget.dependencies;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _start();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final standeeFuture = _prepareStandee();
    final supportFuture = _deps.platform.checkArSupport();
    _permission = await _deps.platform.requestCameraPermission();
    _support = await supportFuture;
    final ok = await standeeFuture;
    if (!mounted) return;
    if (!ok) {
      setState(() => _mode = ArMode.error);
    } else if (_permission != CameraPermission.granted) {
      setState(() => _mode = ArMode.needCamera);
    } else {
      setState(
        () => _mode = decideArMode(
          _support,
          allowInstallPrompt: widget.allowArCoreInstallPrompt,
        ),
      );
    }
  }

  Future<bool> _prepareStandee() async {
    try {
      final c = widget.character;
      final png = await (_deps.readImage ?? _readFile)(c.imagePath);
      final standee = await buildStandeeGlbInBackground(
        png,
        options: StandeeGlbOptions(effects: _effects),
      );
      final dir = await (_deps.glbDirectory ?? _defaultGlbDir)();
      final hash = c.imageHash.length > 16
          ? c.imageHash.substring(0, 16)
          : c.imageHash;
      final file = File(
        '${dir.path}/standee_${hash}_${c.stage.name}_${c.element.name}.glb',
      );
      await file.writeAsBytes(standee.glb, flush: true);
      _standee = standee;
      _glbPath = file.path;
      return true;
    } catch (e, st) {
      debugPrint('AR: failed to prepare standee: $e\n$st');
      return false;
    }
  }

  static Future<Uint8List> _readFile(String path) => File(path).readAsBytes();

  static Future<Directory> _defaultGlbDir() async {
    final tmp = await getTemporaryDirectory();
    return Directory('${tmp.path}/ar').create(recursive: true);
  }

  Future<void> _retryCamera() async {
    _permission = await _deps.platform.requestCameraPermission();
    if (!mounted) return;
    if (_permission == CameraPermission.granted) {
      setState(
        () => _mode = decideArMode(
          _support,
          allowInstallPrompt: widget.allowArCoreInstallPrompt,
        ),
      );
    } else {
      setState(() {});
    }
  }

  Future<void> _install() async {
    final r = await _deps.platform.requestArCoreInstall();
    if (!mounted) return;
    setState(
      () => _mode = switch (r) {
        ArInstallResult.installed => ArMode.ar,
        ArInstallResult.requested => ArMode.installing,
        _ => ArMode.simple,
      },
    );
  }

  Future<void> _onResume() async {
    if (_mode == ArMode.installing) {
      final r = await _deps.platform.requestArCoreInstall(userRequested: false);
      if (!mounted) return;
      setState(
        () => _mode = switch (r) {
          ArInstallResult.installed => ArMode.ar,
          ArInstallResult.requested => ArMode.installing,
          _ => ArMode.simple,
        },
      );
    } else if (_mode == ArMode.needCamera) {
      // The user may have granted the permission in the system settings.
      // Only check here: the permission dialog itself pauses/resumes the
      // activity, so requesting again would loop.
      final now = await _deps.platform.checkCameraPermission();
      if (now == CameraPermission.granted) _permission = now;
      if (mounted && _permission == CameraPermission.granted) {
        setState(
          () => _mode = decideArMode(
            _support,
            allowInstallPrompt: widget.allowArCoreInstallPrompt,
          ),
        );
      }
    }
  }

  void _onSessionFailed(String message) {
    debugPrint('AR: session failed ($message), falling back');
    if (!mounted || _mode != ArMode.ar) return;
    setState(() => _mode = ArMode.simple);
    _toast(ArStrings.switchedToSimple);
  }

  Future<void> _shoot() async {
    final source = _stageKey.currentState;
    if (source is! ArCaptureSource || _busy) return;
    setState(() {
      _busy = true;
      _flash = true;
    });
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _flash = false);
    });
    try {
      final jpeg = await (source as ArCaptureSource).capture();
      final r = await _deps.photoSaver.save(jpeg);
      _toast(switch (r) {
        SaveResult.saved => ArStrings.saved,
        SaveResult.noPermission => ArStrings.saveNoPermission,
        SaveResult.noSpace => ArStrings.saveNoSpace,
        SaveResult.failed => ArStrings.saveFailed,
      });
    } catch (e) {
      debugPrint('AR: capture failed: $e');
      _toast(ArStrings.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, textAlign: TextAlign.center),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _back() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canShoot = _mode == ArMode.ar || _mode == ArMode.simple;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _body(context),
          ShutterFlash(visible: _flash),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  top: 12,
                  child: ArRoundButton(
                    icon: Icons.arrow_back_rounded,
                    label: ArStrings.back,
                    onPressed: _back,
                  ),
                ),
                if (_mode == ArMode.ar ||
                    (_mode == ArMode.simple && _support == ArSupport.supported))
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _ModeChip(
                      label: _mode == ArMode.ar
                          ? ArStrings.simpleAr
                          : ArStrings.realAr,
                      onTap: () => setState(
                        () => _mode = _mode == ArMode.ar
                            ? ArMode.simple
                            : ArMode.ar,
                      ),
                    ),
                  ),
                if (canShoot)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: Center(
                      child: ShutterButton(onPressed: _shoot, busy: _busy),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_mode) {
      case ArMode.preparing:
      case ArMode.installing:
        return const _Message(
          icon: CircularProgressIndicator(color: Colors.white),
          text: ArStrings.preparing,
        );
      case ArMode.error:
        return const _Message(
          icon: Icon(
            Icons.sentiment_dissatisfied,
            size: 64,
            color: Colors.white,
          ),
          text: ArStrings.imageError,
        );
      case ArMode.needCamera:
        return _Message(
          icon: const Icon(Icons.photo_camera, size: 64, color: Colors.white),
          text: ArStrings.cameraNeeded,
          actions: [
            if (_permission == CameraPermission.permanentlyDenied)
              FilledButton(
                onPressed: _deps.platform.openAppSettings,
                child: const Text(ArStrings.openSettings),
              )
            else
              FilledButton(
                onPressed: _retryCamera,
                child: const Text(ArStrings.cameraAskAgain),
              ),
          ],
        );
      case ArMode.offerInstall:
        return _Message(
          icon: const Icon(Icons.view_in_ar, size: 64, color: Colors.white),
          text: ArStrings.installTitle,
          actions: [
            FilledButton(
              onPressed: _install,
              child: const Text(ArStrings.installYes),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => setState(() => _mode = ArMode.simple),
              child: const Text(ArStrings.installNo),
            ),
          ],
        );
      case ArMode.ar:
        return ArCoreStage(
          key: _stageKey,
          glbPath: _glbPath!,
          onSessionFailed: _onSessionFailed,
        );
      case ArMode.simple:
        return SimpleArStage(
          key: _stageKey,
          standee: _standee!,
          effects: _effects,
          cameraBuilder: _deps.simpleCameraBuilder,
        );
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actions = const [],
  });

  final Widget icon;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF3A4A6B),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 20),
              Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              for (final a in actions) ...[const SizedBox(height: 16), a],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.swap_horiz, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
