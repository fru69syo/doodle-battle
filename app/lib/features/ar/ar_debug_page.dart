import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../../domain/element_type.dart';
import '../../domain/battle_v3/battle_v3.dart';
import 'ar_effects.dart';
import 'ar_support.dart';
import 'ar_view_screen.dart';
import 'glb/standee_glb.dart';
import 'sample_cutout.dart';

/// Debug entry for the AR feature: builds a sample character from a
/// procedurally drawn doodle and opens [ArViewScreen].
///
/// Route to it from a debug menu, e.g.
/// `GoRoute(path: '/debug/ar', builder: (_, _) => const ArDebugPage())`.
class ArDebugPage extends StatefulWidget {
  const ArDebugPage({super.key});

  @override
  State<ArDebugPage> createState() => _ArDebugPageState();
}

class _ArDebugPageState extends State<ArDebugPage> {
  int _level = 1;
  ElementType _element = ElementType.fire;
  bool _forceSimple = false;
  String _support = '…';
  String _glbInfo = '';

  @override
  void initState() {
    super.initState();
    checkArSupport().then((s) {
      if (mounted) setState(() => _support = s.name);
    });
  }

  Future<CharacterV2> _sampleCharacter() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ar_debug_sample.png');
    await file.writeAsBytes(buildSampleCutoutPng(), flush: true);
    return CharacterV2(
      id: 'debug-ar',
      name: 'らくがきくん',
      imagePath: file.path,
      imageHash: 'debug0000000000000000',
      legacyElement: _element,
      energy10: 700,
      skill10: 200,
      features: const FeatureVector({}),
      createdAt: DateTime(2026, 1, 1),
      level: _level,
    );
  }

  Future<void> _open() async {
    final character = await _sampleCharacter();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArViewScreen(
          character: character,
          dependencies: ArViewDependencies(
            platform: _forceSimple ? const _NoArPlatform() : const ArPlatform(),
          ),
        ),
      ),
    );
  }

  Future<void> _inspect() async {
    final character = await _sampleCharacter();
    final png = await File(character.imagePath).readAsBytes();
    final sw = Stopwatch()..start();
    final r = await buildStandeeGlbInBackground(
      png,
      options: StandeeGlbOptions(effects: ArEffects.forCharacter(character)),
    );
    sw.stop();
    if (!mounted) return;
    setState(
      () => _glbInfo =
          'GLB ${(r.glb.length / 1024).toStringAsFixed(1)} KB, '
          '${(r.widthMeters * 100).toStringAsFixed(1)}×'
          '${(r.heightMeters * 100).toStringAsFixed(1)} cm, '
          'texture ${r.spriteWidth}×${r.spriteHeight}, ${sw.elapsedMilliseconds} ms',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AR デバッグ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('checkArSupport(): $_support'),
          const SizedBox(height: 16),
          Text('レベル: $_level（Lv10 オーラ / Lv20 きらきら）'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Lv1')),
              ButtonSegment(value: 10, label: Text('Lv10')),
              ButtonSegment(value: 20, label: Text('Lv20')),
            ],
            selected: {_level},
            onSelectionChanged: (s) => setState(() => _level = s.first),
          ),
          const SizedBox(height: 16),
          DropdownButton<ElementType>(
            value: _element,
            items: [
              for (final e in ElementType.values)
                DropdownMenuItem(
                  value: e,
                  child: Text('${e.label} (${e.name})'),
                ),
            ],
            onChanged: (e) => setState(() => _element = e ?? _element),
          ),
          SwitchListTile(
            title: const Text('かんたん AR を つかう（ARCore を むし）'),
            value: _forceSimple,
            onChanged: (v) => setState(() => _forceSimple = v),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _open,
            icon: const Icon(Icons.view_in_ar),
            label: const Text('AR を ひらく'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _inspect,
            child: const Text('GLB を つくって しらべる'),
          ),
          if (_glbInfo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_glbInfo),
            ),
        ],
      ),
    );
  }
}

class _NoArPlatform extends ArPlatform {
  const _NoArPlatform();

  @override
  Future<ArSupport> checkArSupport() async => ArSupport.unsupported;
}
