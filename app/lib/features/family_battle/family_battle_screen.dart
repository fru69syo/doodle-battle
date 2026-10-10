import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/character_picture.dart';
import '../../domain/battle/battle.dart';
import '../battle_ui/battle_arena.dart';
import '../battle_ui/battle_display.dart';
import '../battle_ui/cpu_battle_screen.dart' show battleStepProvider;
import '../battle_ui/move_labels.dart';
import 'family_battle_session.dart';
import 'family_setup.dart';
import 'family_theme.dart';

/// Where the hot-seat flow is.
enum FamilyPhase {
  /// 「〇〇の ばん！ △△は みないでね」 until the picker taps.
  cover,

  /// The picker chooses a move.
  pick,

  /// The resolved turn is being animated (both watch).
  animating,

  /// Winner shown.
  finished,
}

/// Loads the spec, then runs a [FamilyBattleSession].
class FamilyBattleScreen extends ConsumerWidget {
  const FamilyBattleScreen({super.key, required this.config});
  final FamilyBattleConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(battleSpecProvider).value;
    if (spec == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return _FamilyBattleView(
      session: FamilyBattleSession(
        spec: spec,
        config: config,
        seed: ref.read(randomProvider).nextInt(1 << 32),
      ),
    );
  }
}

class _FamilyBattleView extends ConsumerStatefulWidget {
  const _FamilyBattleView({required this.session});
  final FamilyBattleSession session;

  @override
  ConsumerState<_FamilyBattleView> createState() => _FamilyBattleViewState();
}

class _FamilyBattleViewState extends ConsumerState<_FamilyBattleView> {
  late final FamilyBattleSession _s = widget.session;
  late final FamilyBattleConfig _c = _s.config;
  late final BattleDisplay _d = _displayFor();
  FamilyPhase _phase = FamilyPhase.cover;

  BattleDisplay _displayFor() {
    FighterDisplay f(Side side) {
      final c = _c.player(side).character;
      final st = _s.state.fighter(side);
      return FighterDisplay(
        name: _c.fighterName(side),
        level: st.level,
        element: c.element,
        maxHp: st.maxHp,
        hp: st.hp,
        elementMoveName: c.elementMoveName,
        specialMoveName: c.specialMoveName,
      );
    }

    return BattleDisplay(a: f(Side.a), b: f(Side.b))
      ..message = '${_c.a.label} たい ${_c.b.label}！';
  }

  String _moveName(Side side, BattleAction a) =>
      characterMoveLabel(_c.player(side).character, a);

  Future<void> _onMove(BattleAction action) async {
    if (_phase != FamilyPhase.pick) return;
    final events = _s.pick(action);
    if (events == null) {
      // Side a has chosen secretly: hand the device to side b.
      setState(() => _phase = FamilyPhase.cover);
      return;
    }
    setState(() => _phase = FamilyPhase.animating);
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
      await Future<void>.delayed(step);
      if (mounted) setState(() => _phase = FamilyPhase.finished);
    } else {
      setState(() => _phase = FamilyPhase.cover);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picker = _s.picker;
    final body = switch (_phase) {
      FamilyPhase.cover => _Cover(
        player: _c.player(picker).label,
        other: _c.player(picker.other).label,
        colour: familyColour(picker),
        turn: _s.state.turn + 1,
        onContinue: () => setState(() => _phase = FamilyPhase.pick),
      ),
      FamilyPhase.finished => _Result(
        config: _c,
        winner: _s.winner!,
        onRematch: () =>
            context.pushReplacement(Routes.familyBattle, extra: _c),
        onChangeMembers: () => context.pop(),
        onExit: () => context.go(Routes.home),
      ),
      FamilyPhase.pick || FamilyPhase.animating => _Arena(
        session: _s,
        display: _d,
        picker: _phase == FamilyPhase.pick ? picker : null,
        onMove: _onMove,
      ),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('かぞくで たいせん')),
      body: SafeArea(child: body),
    );
  }
}

/// Hides the screen while the device changes hands.
class _Cover extends StatelessWidget {
  const _Cover({
    required this.player,
    required this.other,
    required this.colour,
    required this.turn,
    required this.onContinue,
  });

  final String player;
  final String other;
  final Color colour;
  final int turn;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('family-cover'),
    color: colour,
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$turn ターンめ',
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
        const SizedBox(height: 12),
        Text(
          '$playerの ばん！',
          key: const Key('family-cover-title'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        const Icon(Icons.visibility_off, color: Colors.white, size: 72),
        const SizedBox(height: 12),
        Text(
          '$otherは みないでね',
          key: const Key('family-cover-hint'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 40),
        FilledButton(
          key: const Key('family-cover-continue'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: colour,
            minimumSize: const Size(240, 72),
          ),
          onPressed: onContinue,
          child: Text('$playerが タップ'),
        ),
      ],
    ),
  );
}

/// Both fighters (あお top, あか bottom) and, while picking, the picker's
/// moves in their team colour.
class _Arena extends StatelessWidget {
  const _Arena({
    required this.session,
    required this.display,
    required this.picker,
    required this.onMove,
  });

  final FamilyBattleSession session;
  final BattleDisplay display;

  /// Null while the turn animates.
  final Side? picker;
  final ValueChanged<BattleAction> onMove;

  @override
  Widget build(BuildContext context) {
    final c = session.config;
    final p = picker;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _TeamTag(side: Side.b, label: c.b.label),
                  BattleArena(
                    display: display,
                    gaugeMax: session.spec.gauge.max,
                    pictures: {
                      Side.a: CharacterPicture(
                        character: c.a.character,
                        size: 130,
                      ),
                      Side.b: CharacterPicture(
                        character: c.b.character,
                        size: 120,
                      ),
                    },
                  ),
                  _TeamTag(side: Side.a, label: c.a.label),
                ],
              ),
            ),
          ),
          if (p != null) ...[
            Text(
              '${c.player(p).label}: わざを えらんでね',
              key: const Key('family-pick-title'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: familyColour(p),
              ),
            ),
            MoveButtons(
              labels: (a) => characterMoveLabel(c.player(p).character, a),
              enabled: true,
              specialReady: session.specialReady(p),
              onMove: onMove,
            ),
          ] else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TeamTag extends StatelessWidget {
  const _TeamTag({required this.side, required this.label});
  final Side side;
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: side == Side.a ? Alignment.centerLeft : Alignment.centerRight,
    child: Container(
      key: Key('family-tag-${side.name}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: familyColour(side),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Winner, then 「もういちど」 / 「メンバーを かえる」 / 「おわる」. No XP.
class _Result extends StatelessWidget {
  const _Result({
    required this.config,
    required this.winner,
    required this.onRematch,
    required this.onChangeMembers,
    required this.onExit,
  });

  final FamilyBattleConfig config;
  final Side winner;
  final VoidCallback onRematch;
  final VoidCallback onChangeMembers;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final w = config.player(winner);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.emoji_events, size: 72, color: AppColors.gold),
        Text(
          '${w.label}の かち！',
          key: const Key('family-result-title'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: familyColour(winner),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: CharacterPicture(character: w.character, size: 180)),
        const SizedBox(height: 8),
        Text(
          config.fighterName(winner),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          'ふたりとも よく がんばったね！',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('family-rematch'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          icon: const Icon(Icons.replay),
          label: const Text('もういちど'),
          onPressed: onRematch,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('family-change'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          icon: const Icon(Icons.people),
          label: const Text('メンバーを かえる'),
          onPressed: onChangeMembers,
        ),
        const SizedBox(height: 12),
        TextButton(
          key: const Key('family-exit'),
          onPressed: onExit,
          child: const Text('おわる', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }
}
