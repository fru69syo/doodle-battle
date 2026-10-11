import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/app_state.dart';
import 'battle/battle_25d_screen.dart';
import 'battle/battle_session25.dart';
import 'editor/joint_editor_screen.dart';
import 'editor/rig_edit.dart';
import 'samples25d.dart';

/// Debug entry for the v2.0 2.5D spike (route `/debug/25d`, debug builds
/// only). See docs/V2_25D_TECH.md.
class Spike25dDebugPage extends ConsumerStatefulWidget {
  const Spike25dDebugPage({super.key});

  @override
  ConsumerState<Spike25dDebugPage> createState() => _Spike25dDebugPageState();
}

class _Spike25dDebugPageState extends ConsumerState<Spike25dDebugPage> {
  Uint8List _player = sample25dPng(Sample25d.hero);
  String _playerLabel = 'hero';
  Sample25d _cpu = Sample25d.dog;
  bool _cpuBloomer = false;
  int _level = 12;
  bool _low = false;
  RigStore? _store;

  @override
  void initState() {
    super.initState();
    getApplicationDocumentsDirectory().then((d) {
      if (mounted) setState(() => _store = FileRigStore(d));
    });
  }

  String get _hash => sha256.convert(_player).toString().substring(0, 16);

  @override
  Widget build(BuildContext context) {
    final characters = ref.watch(charactersProvider).value ?? const [];
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: const Text('2.5D spike (debug)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('きみのキャラ: $_playerLabel'),
          Wrap(
            spacing: 8,
            children: [
              for (final s in Sample25d.values)
                ActionChip(
                  label: Text(s.name),
                  onPressed: () => setState(() {
                    _player = sample25dPng(s);
                    _playerLabel = s.name;
                  }),
                ),
              for (final c in characters.take(8))
                ActionChip(
                  label: Text(c.name),
                  onPressed: () async {
                    try {
                      final bytes = await File(c.imagePath).readAsBytes();
                      if (!mounted) return;
                      setState(() {
                        _player = bytes;
                        _playerLabel = c.name;
                      });
                    } catch (_) {}
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('あいて: ${_cpu.name}'),
          Wrap(
            spacing: 8,
            children: [
              for (final s in Sample25d.values)
                ChoiceChip(
                  label: Text(s.name),
                  selected: _cpu == s,
                  onSelected: (_) => setState(() => _cpu = s),
                ),
            ],
          ),
          SwitchListTile(
            title: const Text('あいては かくし（Lv49 までは シンプル）'),
            value: _cpuBloomer,
            onChanged: (v) => setState(() => _cpuBloomer = v),
          ),
          SwitchListTile(
            title: Text('Lv $_level（Lv50: でんせつ・わざ 4 つ）'),
            value: _level >= 50,
            onChanged: (v) => setState(() => _level = v ? 50 : 12),
          ),
          SwitchListTile(
            title: const Text('ひくい がしつ（ふるい たんまつ）'),
            value: _low,
            onChanged: (v) => setState(() => _low = v),
          ),
          const Divider(),
          FilledButton(
            onPressed: () async {
              final rig = await _store?.load(_hash);
              open(
                Battle25dScreen(
                  player: Side25(
                    png: _player,
                    name: 'きみ',
                    level: _level,
                    rig: rig,
                    genomeSeed: 11,
                  ),
                  cpu: Side25(
                    png: sample25dPng(_cpu),
                    name: _cpu.name,
                    level: _level,
                    bloomer: _cpuBloomer,
                    genomeSeed: 5,
                  ),
                  lowQuality: _low,
                ),
              );
            },
            child: const Text('2.5D バトル'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _store == null
                ? null
                : () => open(
                    JointEditorScreen(
                      png: _player,
                      imageHash: _hash,
                      store: _store!,
                    ),
                  ),
            child: const Text('うごく ところを なおす（ジョイント エディタ）'),
          ),
        ],
      ),
    );
  }
}
