import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/widgets/character_picture.dart';
import '../../data/app_state.dart';
import '../../domain/battle/battle.dart';
import '../../domain/character.dart';
import '../drawing_loop/display_image.dart';
import 'battle_arena.dart';
import 'battle_display.dart';
import 'battle_outcome.dart';
import 'cpu_display.dart';
import 'cpu_battle_session.dart';
import 'move_labels.dart';

/// Pause after each animated battle message (tests shorten it).
final battleStepProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 900),
);

/// Loads what a CPU battle needs, then shows [_CpuBattleView].
class CpuBattleScreen extends ConsumerWidget {
  const CpuBattleScreen({
    super.key,
    required this.characterId,
    required this.stage,
  });
  final String characterId;
  final int stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(battleSpecProvider).value;
    final roster = ref.watch(cpuRosterProvider).value;
    final player = ref.watch(characterByIdProvider(characterId));
    if (spec == null || roster == null || player == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final stageRow = spec.cpu.stage(stage);
    final cpu = cpuDisplayCharacter(roster[stageRow.cpuId], stageRow);
    return _CpuBattleView(
      session: CpuBattleSession(
        spec: spec,
        player: player,
        cpu: cpu,
        stage: stageRow,
        roster: roster,
        seed: ref.read(randomProvider).nextInt(1 << 32),
      ),
    );
  }
}

class _CpuBattleView extends ConsumerStatefulWidget {
  const _CpuBattleView({required this.session});
  final CpuBattleSession session;

  @override
  ConsumerState<_CpuBattleView> createState() => _CpuBattleViewState();
}

class _CpuBattleViewState extends ConsumerState<_CpuBattleView> {
  late final CpuBattleSession _s = widget.session;
  late final BattleDisplay _d = _displayFor(_s);
  bool _animating = false;

  static BattleDisplay _displayFor(CpuBattleSession s) {
    FighterDisplay f(Character c, FighterState st) => FighterDisplay(
      name: c.name,
      level: c.level,
      element: c.element,
      maxHp: st.maxHp,
      hp: st.hp,
      elementMoveName: c.elementMoveName,
      specialMoveName: c.specialMoveName,
    );
    return BattleDisplay(a: f(s.player, s.state.a), b: f(s.cpu, s.state.b))
      ..message = '${s.cpu.name}が あらわれた！ どうする？';
  }

  String _moveName(Side side, BattleAction a) =>
      characterMoveLabel(side == Side.a ? _s.player : _s.cpu, a);

  Future<void> _onMove(BattleAction action) async {
    if (_animating || _s.isOver) return;
    setState(() => _animating = true);
    final events = _s.playTurn(action);
    final step = ref.read(battleStepProvider);
    for (final e in events) {
      final wait = applyBattleEvent(
        _d,
        e,
        texts: _s.spec.texts,
        moveName: _moveName,
        step: step,
      );
      if (!mounted) return;
      setState(() {});
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    if (!mounted) return;
    if (_s.isOver) {
      await _finish();
    } else {
      setState(() {
        _animating = false;
        _d.message = 'どうする？';
      });
    }
  }

  Future<void> _finish() async {
    setState(
      () => _d.message = _s.playerWon ? 'やったー！ かった！' : 'まけちゃった… つぎは がんばろう！',
    );
    final outcome = await ref
        .read(battleRewardsProvider)
        .applyCpuResult(
          spec: _s.spec,
          player: _s.player,
          stage: _s.stage,
          won: _s.playerWon,
        );
    await Future<void>.delayed(ref.read(battleStepProvider));
    if (mounted) context.pushReplacement(Routes.battleResult, extra: outcome);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('ステージ ${_s.stage.stage}')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: BattleArena(
                  display: _d,
                  gaugeMax: _s.spec.gauge.max,
                  pictures: {
                    Side.a: CharacterPicture(character: _s.player, size: 140),
                    Side.b: CharacterPicture(character: _s.cpu, size: 120),
                  },
                  effectImages: {Side.a: watchMoveEffects(ref, _s.player)},
                ),
              ),
            ),
            MoveButtons(
              labels: (a) => characterMoveLabel(_s.player, a),
              enabled: !_animating && !_s.isOver,
              specialReady: _s.specialReady,
              onMove: _onMove,
            ),
          ],
        ),
      ),
    ),
  );
}
