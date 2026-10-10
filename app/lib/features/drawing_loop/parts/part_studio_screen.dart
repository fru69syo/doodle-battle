import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/kid_dialogs.dart';
import '../../../data/app_state.dart';
import '../../../data/drawing_loop_storage.dart';
import '../../../domain/character.dart';
import '../../../domain/cosmetics.dart';
import '../display_image.dart';
import '../loop_capture.dart';
import '../loop_labels.dart';
import '../odai/odai_controller.dart';
import '../odai/stamp_card.dart';
import 'part_editor.dart';
import 'part_geometry.dart';

enum _Phase { loading, intro, analyzing, pickType, place, saving, done }

/// パーツを かきたす: draw a part on paper → photo → choose what it is →
/// place it (drag / pinch / twist) → save. Without [addNew] it edits the
/// existing parts (move, resize, rotate, front/back, remove).
///
/// The base drawing is never changed: the parts list and the part PNGs are
/// stored separately and the display picture is re-composited from them.
class PartStudioScreen extends ConsumerStatefulWidget {
  const PartStudioScreen({
    super.key,
    required this.characterId,
    this.addNew = false,
  });

  final String characterId;
  final bool addNew;

  @override
  ConsumerState<PartStudioScreen> createState() => _PartStudioScreenState();
}

class _PartStudioScreenState extends ConsumerState<PartStudioScreen> {
  _Phase _phase = _Phase.loading;
  Uint8List? _base;
  int _baseW = 1, _baseH = 1;
  final _parts = <PlacedPart>[];
  final _removed = <String>{};
  int? _selected;
  Uint8List? _cutout;

  Character? get _character =>
      ref.read(characterByIdProvider(widget.characterId));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = _character;
    final base = c == null
        ? null
        : await ref.read(characterRepositoryProvider).readImage(c.id);
    if (!mounted) return;
    if (c == null || base == null) {
      context.pop();
      return;
    }
    final store = ref.read(drawingLoopStorageProvider);
    for (final p in c.cosmetics.parts) {
      final png = await store.readAsset(c.id, p.assetName);
      if (png == null) continue;
      final (w, h) = pngSize(png);
      _parts.add(
        PlacedPart(
          id: p.id,
          type: p.type,
          png: png,
          width: w,
          height: h,
          transform: p.transform,
        ),
      );
    }
    final (bw, bh) = pngSize(base);
    if (!mounted) return;
    if (widget.addNew && _parts.length >= partSlotsFor(c.level)) {
      await showKidMessage(
        context,
        'いまは これいじょう つけられないよ。レベルが あがると パーツが ふえるよ',
        icon: Icons.lock,
      );
      if (mounted) context.pop();
      return;
    }
    setState(() {
      _base = base;
      _baseW = bw;
      _baseH = bh;
      _selected = _parts.isEmpty ? null : _parts.length - 1;
      _phase = widget.addNew ? _Phase.intro : _Phase.place;
    });
  }

  Future<void> _capture() async {
    setState(() => _phase = _Phase.analyzing);
    final r = await captureLoopDrawing(ref);
    if (!mounted) return;
    switch (r) {
      case LoopCaptured(:final cutoutPng):
        setState(() {
          _cutout = cutoutPng;
          _phase = _Phase.pickType;
        });
      case LoopRejected(:final message):
        setState(() => _phase = _Phase.intro);
        await showKidMessage(context, message, icon: Icons.edit);
      case LoopUnreadable():
        setState(() => _phase = _Phase.intro);
        await showKidMessage(
          context,
          unreadableMessage,
          icon: Icons.photo_camera,
        );
      case LoopCancelled():
        setState(() => _phase = _Phase.intro);
    }
  }

  void _pickType(PartType type) {
    final png = _cutout!;
    final (w, h) = pngSize(png);
    final sameType = _parts.where((p) => p.type == type).length;
    final now = ref.read(clockProvider)().microsecondsSinceEpoch;
    setState(() {
      _parts.add(
        PlacedPart(
          id: 'p$now',
          type: type,
          png: png,
          width: w,
          height: h,
          transform: defaultPlacement(type, index: sameType),
          isNew: true,
        ),
      );
      _selected = _parts.length - 1;
      _cutout = null;
      _phase = _Phase.place;
    });
  }

  void _update(int i, PartTransform t) =>
      setState(() => _parts[i].transform = t.clamped());

  void _nudge({double scale = 1, double rotate = 0, bool flipLayer = false}) {
    final i = _selected;
    if (i == null) return;
    final t = _parts[i].transform;
    _update(
      i,
      t.copyWith(
        scale: t.scale * scale,
        rotation: t.rotation + rotate,
        behind: flipLayer ? !t.behind : t.behind,
      ),
    );
  }

  Future<void> _remove() async {
    final i = _selected;
    if (i == null) return;
    final ok = await askKid(
      context,
      'この ${partLabel(_parts[i].type)} を はずす？',
      yesLabel: 'はずす',
      noLabel: 'やめる',
      icon: Icons.layers_clear,
    );
    if (!ok || !mounted) return;
    setState(() {
      final p = _parts.removeAt(i);
      if (!p.isNew) _removed.add(p.id);
      _selected = _parts.isEmpty ? null : _parts.length - 1;
    });
  }

  Future<void> _save() async {
    final c = _character;
    if (c == null) return;
    setState(() => _phase = _Phase.saving);
    final store = ref.read(drawingLoopStorageProvider);
    for (final p in _parts.where((p) => p.isNew)) {
      await store.writeAsset(c.id, 'part_${p.id}', p.png);
    }
    for (final id in _removed) {
      await store.deleteAsset(c.id, 'part_$id');
    }
    final updated = c.copyWith(
      cosmetics: c.cosmetics.copyWith(
        parts: [
          for (final p in _parts)
            CharacterPart(id: p.id, type: p.type, transform: p.transform),
        ],
      ),
    );
    await ref.read(charactersProvider.notifier).save(updated);
    // Render (and cache) the new look before going back.
    final display = ref.read(displayImageServiceProvider);
    if (_parts.isEmpty) {
      await display.clearCache(c.id);
    } else {
      await display.displayImageFor(updated);
    }
    final badge = _parts.any((p) => p.isNew)
        ? await completeActiveOdai(
            ref.read,
            kind: StampKind.part,
            characterId: c.id,
          )
        : null;
    if (!mounted) return;
    setState(() => _phase = _Phase.done);
    if (badge != null) await showOdaiStampMessage(context, badge);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.addNew ? 'パーツを かきたす' : 'パーツを うごかす';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.loading => const LoopBusy(text: 'じゅんびちゅう…'),
          _Phase.analyzing => const LoopBusy(),
          _Phase.saving => const LoopBusy(text: 'くっつけているよ…'),
          _Phase.done => const LoopDone(),
          _Phase.intro => LoopCaptureIntro(
            icon: Icons.add_reaction,
            title: 'かみに パーツを かこう',
            hint: 'ぼうし・つばさ・つの・しっぽ・もちもの・かざり… すきな パーツを 1つ かいてね',
            onCapture: _capture,
          ),
          _Phase.pickType => _TypePicker(cutout: _cutout!, onPick: _pickType),
          _Phase.place => _placeView(),
        },
      ),
    );
  }

  Widget _placeView() {
    final sel = _selected;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'ゆびで うごかしてね。2ほんの ゆびで おおきさと むきを かえられるよ',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 8),
        PartPlacementCanvas(
          basePng: _base!,
          baseWidth: _baseW,
          baseHeight: _baseH,
          parts: _parts,
          selected: sel,
          onSelect: (i) => setState(() => _selected = i),
          onChanged: _update,
        ),
        const SizedBox(height: 8),
        if (_parts.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              for (var i = 0; i < _parts.length; i++)
                ChoiceChip(
                  key: Key('part-chip-$i'),
                  avatar: Icon(partIcon(_parts[i].type)),
                  label: Text(partLabel(_parts[i].type)),
                  selected: sel == i,
                  onSelected: (_) => setState(() => _selected = i),
                ),
            ],
          ),
        if (sel != null) ...[
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              _Tool(
                key: const Key('part-smaller'),
                icon: Icons.zoom_out,
                label: 'ちいさく',
                onTap: () => _nudge(scale: 1 / 1.15),
              ),
              _Tool(
                key: const Key('part-bigger'),
                icon: Icons.zoom_in,
                label: 'おおきく',
                onTap: () => _nudge(scale: 1.15),
              ),
              _Tool(
                key: const Key('part-rotate-left'),
                icon: Icons.rotate_left,
                label: 'まわす',
                onTap: () => _nudge(rotate: -math.pi / 12),
              ),
              _Tool(
                key: const Key('part-rotate-right'),
                icon: Icons.rotate_right,
                label: 'まわす',
                onTap: () => _nudge(rotate: math.pi / 12),
              ),
              _Tool(
                key: const Key('part-layer'),
                icon: Icons.flip_to_back,
                label: _parts[sel].transform.behind ? 'まえに' : 'うしろに',
                onTap: () => _nudge(flipLayer: true),
              ),
              _Tool(
                key: const Key('part-remove'),
                icon: Icons.layers_clear,
                label: 'はずす',
                color: AppColors.danger,
                onTap: _remove,
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('part-save'),
          icon: const Icon(Icons.check_circle),
          label: const Text('できた！'),
          onPressed: _save,
        ),
      ],
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.secondary,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 72,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ),
  );
}

class _TypePicker extends StatelessWidget {
  const _TypePicker({required this.cutout, required this.onPick});
  final Uint8List cutout;
  final ValueChanged<PartType> onPick;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Center(
        child: Container(
          width: 160,
          height: 160,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Image.memory(cutout, fit: BoxFit.contain),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'なにを かいたの？',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final t in PartType.values)
            Material(
              color: const Color(0xFFFFF1C9),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                key: Key('part-type-${t.name}'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => onPick(t),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(partIcon(t), size: 40, color: AppColors.primary),
                    const SizedBox(height: 4),
                    Text(
                      partLabel(t),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
