import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../draw_canvas/canvas_analysis.dart';
import '../puppet_store.dart';
import '../rig/limb_hints.dart';
import 'joint_editor_screen.dart';

/// Route page `/zukan/:id/joints` (`?first=1` right after birth): loads the
/// character's cut-out, stored rig and drawing-tool strokes, then shows the
/// joint editor. After birth, done / skip continue to the character page.
class CharacterJointsPage extends ConsumerStatefulWidget {
  const CharacterJointsPage({
    super.key,
    required this.characterId,
    this.firstTime = false,
  });

  final String characterId;
  final bool firstTime;

  @override
  ConsumerState<CharacterJointsPage> createState() =>
      _CharacterJointsPageState();
}

class _CharacterJointsPageState extends ConsumerState<CharacterJointsPage> {
  Uint8List? _png;
  String? _rig;
  List<HintStroke>? _strokes;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final png = await ref
        .read(characterRepositoryProvider)
        .readImage(widget.characterId);
    final store = ref.read(puppetStoreProvider);
    final rig = await store.loadRigJson(widget.characterId);
    final strokes = hintStrokesFromRecord(
      await store.loadStrokesJson(widget.characterId),
    );
    if (!mounted) return;
    setState(() {
      _png = png;
      _rig = rig;
      _strokes = strokes;
      _missing = png == null;
    });
  }

  void _finish() {
    if (widget.firstTime) {
      context.go(Routes.character(widget.characterId));
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.character(widget.characterId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_missing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish();
      });
    }
    final png = _png;
    if (png == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return JointEditorScreen(
      characterId: widget.characterId,
      png: png,
      strokes: _strokes,
      initialRigJson: _rig,
      firstTime: widget.firstTime,
      onFinished: (_) => _finish(),
    );
  }
}
