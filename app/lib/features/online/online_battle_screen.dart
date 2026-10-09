import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/character_picture.dart';
import '../../core/widgets/element_badge.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';
import '../../domain/battle/battle.dart';
import '../../domain/character.dart';
import '../battle_ui/battle_arena.dart';
import '../battle_ui/battle_display.dart';
import '../battle_ui/battle_outcome.dart';
import '../battle_ui/cpu_battle_screen.dart' show battleStepProvider;
import '../battle_ui/move_labels.dart';
import 'report_sheet.dart';

/// Turn time limit (SPEC §5).
const onlineTurnSeconds = 20;

/// Poll interval while waiting for the opponent (docs/BACKEND.md §5).
final matchPollProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// Server-resolved online battle (SPEC §5): listens to `matches/{id}`,
/// animates each turn log, `submitAction` with a 20 s timer.
class OnlineBattleScreen extends ConsumerStatefulWidget {
  const OnlineBattleScreen({
    super.key,
    required this.matchId,
    required this.character,
  });

  final String matchId;
  final Character character;

  @override
  ConsumerState<OnlineBattleScreen> createState() => _OnlineBattleScreenState();
}

class _OnlineBattleScreenState extends ConsumerState<OnlineBattleScreen> {
  StreamSubscription<MatchSnapshot>? _sub;
  MatchSnapshot? _m;
  BattleDisplay? _d;
  Uint8List? _oppImage;
  int _shownTurn = 0;
  int _remaining = onlineTurnSeconds;
  bool _submitted = false;
  bool _animating = false;
  bool _finished = false;
  Timer? _ticker;
  Timer? _poll;
  final _queue = <MatchSnapshot>[];

  BackendApi get _api => ref.read(backendApiProvider);

  @override
  void initState() {
    super.initState();
    _sub = _api.watchMatch(widget.matchId).listen(_onSnapshot, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  void _onSnapshot(MatchSnapshot m) {
    _queue.add(m);
    if (!_animating) _drain();
  }

  Future<void> _drain() async {
    _animating = true;
    while (_queue.isNotEmpty && mounted) {
      await _apply(_queue.removeAt(0));
    }
    _animating = false;
    if (mounted) setState(() {});
  }

  Future<void> _apply(MatchSnapshot m) async {
    if (_d == null) {
      _d = _initialDisplay(m);
      _shownTurn = m.turn - 1;
      _loadOpponentImage(m.opponent);
    } else {
      // Animate every newly resolved turn log.
      final last = m.isOver ? m.turn : m.turn - 1;
      for (var t = _shownTurn + 1; t <= last; t++) {
        await _animateTurn(m, t);
      }
      _shownTurn = last > _shownTurn ? last : _shownTurn;
    }
    _syncView(m);
    final newTurn = _m == null || m.turn != _m!.turn;
    _m = m;
    if (m.isOver) return _finish(m);
    if (newTurn) _startTurn();
    if (mounted) setState(() {});
  }

  BattleDisplay _initialDisplay(MatchSnapshot m) {
    FighterDisplay f(Side s) {
      final o = m.sides[s]!;
      final v = m.view[s];
      return FighterDisplay(
        name: o.characterName,
        level: o.level,
        element: o.element,
        maxHp: v?.maxHp ?? o.stats.hp * 3,
        hp: v?.hp ?? o.stats.hp * 3,
        gauge: v?.gauge ?? 0,
        elementMoveName: o.elementMoveName,
        specialMoveName: o.specialMoveName,
      );
    }

    return BattleDisplay(a: f(Side.a), b: f(Side.b))
      ..message = '${m.opponent.characterName}と たいせん！';
  }

  void _syncView(MatchSnapshot m) {
    for (final s in Side.values) {
      final v = m.view[s];
      if (v == null) continue;
      _d![s]
        ..hp = v.hp
        ..maxHp = v.maxHp
        ..gauge = v.gauge
        ..fainted = v.hp <= 0;
    }
  }

  Future<void> _animateTurn(MatchSnapshot m, int turn) async {
    List<BattleEvent> events;
    try {
      events = await _api.turnEvents(widget.matchId, turn);
    } on BackendException {
      return;
    }
    final spec = await ref.read(battleSpecProvider.future);
    final step = ref.read(battleStepProvider);
    for (final e in events) {
      final wait = applyBattleEvent(
        _d!,
        e,
        texts: spec.texts,
        step: step,
        moveName: (side, a) => moveLabel(
          a,
          element: _d![side].element,
          elementMoveName: _d![side].elementMoveName,
          specialMoveName: _d![side].specialMoveName,
        ),
      );
      if (!mounted) return;
      setState(() {});
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }

  Future<void> _loadOpponentImage(OnlineFighter o) async {
    final path = o.imagePath;
    if (path == null) return;
    final bytes = await _api.loadSnapshotImage(path);
    if (mounted && bytes != null) setState(() => _oppImage = bytes);
  }

  void _startTurn() {
    _submitted = false;
    _remaining = onlineTurnSeconds;
    _poll?.cancel();
    _ticker?.cancel();
    _d!.message = 'どうする？ （${_m!.turn}ターンめ）';
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = _remaining > 0 ? _remaining - 1 : 0);
      if (_remaining == 0) {
        _ticker?.cancel();
        _pollNow(); // lets the server resolve the timeout (たいあたり)
        _startPolling();
      }
    });
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(ref.read(matchPollProvider), (_) => _pollNow());
  }

  Future<void> _pollNow() async {
    try {
      await _api.pollMatch(widget.matchId);
    } on BackendException {
      // the match listener delivers the outcome
    }
  }

  Future<void> _onMove(BattleAction action) async {
    final m = _m;
    if (m == null || _submitted || m.isOver) return;
    setState(() {
      _submitted = true;
      _d!.message = 'あいての こうどうを まっているよ…';
    });
    try {
      await _api.submitAction(widget.matchId, m.turn, action);
    } on BackendException catch (e) {
      if (e.code == BackendCodes.illegalAction) {
        setState(() => _submitted = false);
        return;
      }
      await _pollNow();
    }
    _startPolling();
  }

  Future<void> _finish(MatchSnapshot m) async {
    if (_finished) return;
    _finished = true;
    _ticker?.cancel();
    _poll?.cancel();
    final mine = m.result[m.mySide];
    if (m.status == MatchStatus.aborted || mine == null) {
      if (!mounted) return;
      await showKidMessage(context, 'たいせんが ちゅうしに なったよ');
      if (mounted) context.go(Routes.home);
      return;
    }
    final spec = await ref.read(battleSpecProvider.future);
    final player =
        ref.read(characterByIdProvider(widget.character.id)) ??
        widget.character;
    final outcome = await ref
        .read(battleRewardsProvider)
        .applyOnlineResult(
          spec: spec,
          player: player,
          matchId: m.id,
          xp: mine.xp,
          outcome: mine.outcome,
        );
    await Future<void>.delayed(ref.read(battleStepProvider));
    if (!mounted) return;
    if (outcome == null) {
      context.go(Routes.home);
    } else {
      context.pushReplacement(Routes.battleResult, extra: outcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final d = _d;
    final spec = ref.watch(battleSpecProvider).value;
    if (m == null || d == null || spec == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final me = m.mySide;
    return Scaffold(
      appBar: AppBar(
        title: Text(m.opponent.displayName ?? 'オンライン'),
        actions: [
          IconButton(
            key: const Key('report'),
            tooltip: 'おしらせ する',
            icon: const Icon(Icons.flag, color: AppColors.danger),
            onPressed: () =>
                showReportSheet(context, ref, m.opponent.snapshotId),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _TurnTimer(remaining: _remaining, waiting: _submitted),
              Expanded(
                child: SingleChildScrollView(
                  child: BattleArena(
                    display: d,
                    gaugeMax: spec.gauge.max,
                    playerSide: me,
                    pictures: {
                      me: CharacterPicture(
                        character: widget.character,
                        size: 140,
                      ),
                      me.other: _OpponentPicture(
                        fighter: m.opponent,
                        bytes: _oppImage,
                      ),
                    },
                  ),
                ),
              ),
              MoveButtons(
                labels: (a) => characterMoveLabel(widget.character, a),
                enabled: !_submitted && !_animating && !m.isOver,
                specialReady: d[me].gauge >= spec.gauge.max,
                onMove: _onMove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnTimer extends StatelessWidget {
  const _TurnTimer({required this.remaining, required this.waiting});
  final int remaining;
  final bool waiting;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.timer, size: 28),
      const SizedBox(width: 6),
      Text(
        waiting ? 'まってね' : 'のこり $remainingびょう',
        key: const Key('turn-timer'),
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: remaining <= 5 ? AppColors.danger : AppColors.ink,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: LinearProgressIndicator(
          value: remaining / onlineTurnSeconds,
          minHeight: 10,
          color: remaining <= 5 ? AppColors.danger : AppColors.secondary,
        ),
      ),
    ],
  );
}

class _OpponentPicture extends StatelessWidget {
  const _OpponentPicture({required this.fighter, required this.bytes});
  final OnlineFighter fighter;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) => EvolutionFrame(
    stage: fighter.evolution,
    color: AppColors.element(fighter.element),
    size: 120,
    child: bytes == null
        ? Icon(
            elementIcon(fighter.element),
            size: 64,
            color: AppColors.element(fighter.element),
          )
        : Image.memory(bytes!, fit: BoxFit.contain),
  );
}
