import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../data/app_state.dart';
import '../ar/sample_cutout.dart';
import 'battle/battle_3d_screen.dart';
import 'battle/battle_stage.dart';
import 'samples.dart';
import 'viewer/character_viewer_screen.dart';

/// Debug entry for the v2.0 3D tech spike (route `/debug/3d`, debug builds
/// only). See docs/V2_3D_TECH.md.
class Spike3dDebugPage extends ConsumerStatefulWidget {
  const Spike3dDebugPage({super.key});

  @override
  ConsumerState<Spike3dDebugPage> createState() => _Spike3dDebugPageState();
}

class _Spike3dDebugPageState extends ConsumerState<Spike3dDebugPage> {
  late Uint8List _player = buildLargeSampleCutoutPng();
  String _playerLabel = 'サンプル（512px）';
  bool _low = false;

  late final Uint8List _cpu = buildSampleCutoutPng();

  @override
  Widget build(BuildContext context) {
    final gpu = flutterGpuAvailable();
    final characters = ref.watch(charactersProvider).value ?? const [];
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    final quality = _low ? StageQuality.low : const StageQuality();
    return Scaffold(
      appBar: AppBar(title: const Text('3D spike (debug)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Flutter GPU: ${gpu ? 'OK' : 'つかえない（2D にフォールバック）'}'),
          const SizedBox(height: 8),
          Text('きみのキャラ: $_playerLabel'),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('サンプル'),
                onPressed: () => setState(() {
                  _player = buildLargeSampleCutoutPng();
                  _playerLabel = 'サンプル（512px）';
                }),
              ),
              for (final c in characters.take(8))
                ActionChip(
                  label: Text(c.name),
                  onPressed: () async {
                    final bytes = await _loadCutout(c.imagePath);
                    if (bytes == null || !mounted) return;
                    setState(() {
                      _player = bytes;
                      _playerLabel = c.name;
                    });
                  },
                ),
            ],
          ),
          SwitchListTile(
            title: const Text('ひくい がしつ（かげ・はいけい なし）'),
            value: _low,
            onChanged: (v) => setState(() => _low = v),
          ),
          const Divider(),
          FilledButton(
            onPressed: () => open(
              Battle3DScreen(
                playerPng: _player,
                cpuPng: _cpu,
                quality: quality,
              ),
            ),
            child: const Text('3D バトル'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => open(
              Battle3DScreen(
                playerPng: _player,
                cpuPng: _cpu,
                cpuSimplified: true,
                quality: quality,
              ),
            ),
            child: const Text('3D バトル（あいては しょぼキャラ）'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => open(CharacterViewerScreen(png: _player)),
            child: const Text('3D ビューア'),
          ),
        ],
      ),
    );
  }

  /// Stored cut-outs are ≤512 px PNGs; downscale defensively.
  Future<Uint8List?> _loadCutout(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final im = img.decodePng(bytes);
      if (im == null) return null;
      if (im.width <= 512 && im.height <= 512) return bytes;
      return img.encodePng(
        img.copyResize(
          im,
          width: im.width >= im.height ? 512 : null,
          height: im.height > im.width ? 512 : null,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
