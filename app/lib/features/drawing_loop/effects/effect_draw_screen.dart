import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/character_picture.dart';
import '../../../core/widgets/kid_dialogs.dart';
import '../../../data/app_state.dart';
import '../../../data/drawing_loop_storage.dart';
import '../../../domain/battle/battle.dart';
import '../../../domain/character.dart';
import '../../../domain/cosmetics.dart';
import '../../battle_ui/move_labels.dart';
import '../display_image.dart';
import '../loop_capture.dart';
import '../loop_labels.dart';
import '../odai/odai_controller.dart';
import '../odai/stamp_card.dart';
import 'move_effect_layer.dart';

enum _Phase { intro, analyzing, preview, saving, done }

/// わざを かく: draw what flies out of the ぞくせいわざ / ひっさつ, photo it,
/// watch it fly, keep it. Purely visual (same power, same rules).
class EffectDrawScreen extends ConsumerStatefulWidget {
  const EffectDrawScreen({
    super.key,
    required this.characterId,
    required this.move,
  });

  final String characterId;
  final DrawnMove move;

  @override
  ConsumerState<EffectDrawScreen> createState() => _EffectDrawScreenState();
}

class _EffectDrawScreenState extends ConsumerState<EffectDrawScreen> {
  _Phase _phase = _Phase.intro;
  Uint8List? _cutout;
  int _tick = 0;

  Future<void> _capture() async {
    setState(() => _phase = _Phase.analyzing);
    final r = await captureLoopDrawing(ref);
    if (!mounted) return;
    switch (r) {
      case LoopCaptured(:final cutoutPng):
        setState(() {
          _cutout = cutoutPng;
          _phase = _Phase.preview;
          _tick++;
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

  Future<void> _save(Character c) async {
    setState(() => _phase = _Phase.saving);
    final store = ref.read(drawingLoopStorageProvider);
    final now = ref.read(clockProvider)().microsecondsSinceEpoch;
    final name = 'fx_${widget.move.name}_$now';
    await store.writeAsset(c.id, name, _cutout!);
    final old = c.cosmetics.effects[widget.move];
    if (old != null) await store.deleteAsset(c.id, old);
    await ref
        .read(charactersProvider.notifier)
        .save(
          c.copyWith(
            cosmetics: c.cosmetics.copyWith(
              effects: {...c.cosmetics.effects, widget.move: name},
            ),
          ),
        );
    final badge = await completeActiveOdai(
      ref.read,
      kind: StampKind.effect,
      characterId: c.id,
    );
    if (!mounted) return;
    setState(() => _phase = _Phase.done);
    if (badge != null) await showOdaiStampMessage(context, badge);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(characterByIdProvider(widget.characterId));
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final action = battleActionOf(widget.move);
    final moveName = characterMoveLabel(c, action);
    return Scaffold(
      appBar: AppBar(title: Text('「$moveName」の えを かく')),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.analyzing => const LoopBusy(),
          _Phase.saving => const LoopBusy(text: 'しまっているよ…'),
          _Phase.done => const LoopDone(),
          _Phase.intro => LoopCaptureIntro(
            icon: widget.move == DrawnMove.special
                ? Icons.star
                : defaultEffectIcon(c.element, action),
            color: widget.move == DrawnMove.special
                ? AppColors.purple
                : AppColors.element(c.element),
            title: '「$moveName」で とびだす ものを かこう',
            hint: widget.move == DrawnMove.special
                ? 'ひっさつわざで とんでいく、すごい ものを かいてね（ほし・ビーム・おおきな ひのたま など）'
                : 'あいてに むかって とんでいく ものを かいてね（ひのたま・みずしぶき・はっぱ・いなずま など）',
            onCapture: _capture,
          ),
          _Phase.preview => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'こんなふうに とんでいくよ！',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _PreviewStage(
                character: c,
                action: action,
                effect: _cutout!,
                tick: _tick,
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  key: const Key('effect-replay'),
                  icon: const Icon(Icons.replay),
                  label: const Text('もういちど みる'),
                  onPressed: () => setState(() => _tick++),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('effect-save'),
                icon: const Icon(Icons.check_circle),
                label: const Text('これに する！'),
                onPressed: () => _save(c),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('effect-retake'),
                icon: const Icon(Icons.photo_camera),
                label: const Text('かきなおす'),
                onPressed: _capture,
              ),
            ],
          ),
        },
      ),
    );
  }
}

/// Small stage: the character bottom-left, a target top-right, and the
/// drawn effect flying between them (same animation as in battle).
class _PreviewStage extends StatelessWidget {
  const _PreviewStage({
    required this.character,
    required this.action,
    required this.effect,
    required this.tick,
  });

  final Character character;
  final BattleAction action;
  final Uint8List effect;
  final int tick;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 4 / 3,
    child: LayoutBuilder(
      builder: (context, box) {
        final from = Offset(70, box.maxHeight - 70);
        final to = Offset(box.maxWidth - 60, 60);
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEFF7FF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              Positioned(
                left: from.dx - 55,
                top: from.dy - 55,
                child: CharacterPicture(character: character, size: 110),
              ),
              Positioned(
                left: to.dx - 40,
                top: to.dy - 40,
                child: const Icon(
                  Icons.adjust,
                  size: 80,
                  color: AppColors.danger,
                ),
              ),
              Positioned.fill(
                child: MoveEffectLayer(
                  key: const Key('effect-preview'),
                  cue: MoveEffectCue(side: Side.a, move: action, tick: tick),
                  centerOf: (s) => s == Side.a ? from : to,
                  elementOf: (_) => character.element,
                  drawn: {
                    Side.a: {action: effect},
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
