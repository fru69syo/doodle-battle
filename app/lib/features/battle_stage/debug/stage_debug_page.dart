import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/app_state.dart';
import '../../draw_canvas/draw_canvas_screen.dart';
import '../../puppet/editor/joint_editor_screen.dart';
import '../../puppet/samples.dart';
import '../battle_stage.dart';
import 'demo_battle.dart';

/// Debug entry for the 2.5D puppets and stage (route `/debug/25d`, debug
/// builds only). See docs/PUPPET.md.
class StageDebugPage extends ConsumerStatefulWidget {
  const StageDebugPage({super.key});

  @override
  ConsumerState<StageDebugPage> createState() => _StageDebugPageState();
}

class _StageDebugPageState extends ConsumerState<StageDebugPage> {
  Uint8List _player = samplePng(Sample.hero);
  String _playerLabel = 'hero';
  Sample _cpu = Sample.dog;
  bool _cpuBloomer = false;
  int _level = 12;
  bool _low = false;
  StageTheme _theme = StageTheme.meadow;

  @override
  Widget build(BuildContext context) {
    final characters = ref.watch(charactersProvider).value ?? const [];
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: const Text('2.5D puppets (debug)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('きみのキャラ: $_playerLabel'),
          Wrap(
            spacing: 8,
            children: [
              for (final s in Sample.values)
                ActionChip(
                  label: Text(s.name),
                  onPressed: () => setState(() {
                    _player = samplePng(s);
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
                    } on Object {
                      // Missing file: keep the current picture.
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('あいて: ${_cpu.name}'),
          Wrap(
            spacing: 8,
            children: [
              for (final s in Sample.values)
                ChoiceChip(
                  label: Text(s.name),
                  selected: _cpu == s,
                  onSelected: (_) => setState(() => _cpu = s),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('ステージ'),
          Wrap(
            spacing: 8,
            children: [
              for (final t in StageTheme.all)
                ChoiceChip(
                  label: Text(t.name),
                  selected: _theme == t,
                  onSelected: (_) => setState(() => _theme = t),
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
            onPressed: () => open(
              DemoBattleScreen(
                player: DemoSide(
                  png: _player,
                  name: 'きみ',
                  level: _level,
                  genomeSeed: 11,
                ),
                cpu: DemoSide(
                  png: samplePng(_cpu),
                  name: _cpu.name,
                  level: _level,
                  lateBloomer: _cpuBloomer,
                  genomeSeed: 5,
                ),
                theme: _theme,
                quality: _low ? StageQuality.low : null,
              ),
            ),
            child: const Text('2.5D バトル'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => open(
              JointEditorScreen(
                characterId: 'debug',
                png: _player,
                firstTime: true,
              ),
            ),
            child: const Text('うごく ところを なおす（ジョイント エディタ）'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => open(const DrawCanvasScreen()),
            child: const Text('アプリで かく（お絵かきツール）'),
          ),
        ],
      ),
    );
  }
}
