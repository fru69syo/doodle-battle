import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/app_state.dart';
import '../../domain/character_v2.dart';
import '../battle_stage/battle_stage.dart';
import '../battle_stage/stage_overlay.dart';
import '../battle_ui/atb_parts.dart';
import '../battle_ui/battle_outcome.dart';
import '../puppet/character_puppet.dart';
import '../puppet/puppet_builder.dart';
import '../puppet/puppet_look.dart';
import '../puppet/rig/character_rig.dart';
import 'online_registration.dart';
import 'realtime/online_feed.dart';
import 'realtime/realtime_client.dart';
import 'realtime/realtime_messages.dart';
import 'report_sheet.dart';

/// Picture used when the opponent's picture can not be loaded.
const kOnlineFallbackPicture = 'assets/cpu/cpu_stickman.png';

enum _Step { registering, rejected, online }

/// Online rated battle (SPEC §12.5): registration (server review) →
/// WebSocket matchmaking (a ghost when nobody is found; the same searching
/// animation either way) → server-driven ATB battle → result.
class OnlineBattleScreen extends ConsumerStatefulWidget {
  const OnlineBattleScreen({super.key, required this.character});
  final CharacterV2 character;

  @override
  ConsumerState<OnlineBattleScreen> createState() => _OnlineBattleScreenState();
}

class _OnlineBattleScreenState extends ConsumerState<OnlineBattleScreen> {
  late CharacterV2 _c = widget.character;
  _Step _step = _Step.registering;
  String _message = '';
  List<String> _presets = const [];

  RealtimeSession? _session;
  OnlineFeed? _feed;
  BattleStageController? _controller;
  List<AtbSide>? _sides;
  bool _finishing = false;

  // Controls state.
  int? _pending;
  bool _omakase = false;
  bool _wasReady = false;
  final _readyClock = Stopwatch();

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _session?.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() => _step = _Step.registering);
    final r = await ref.read(onlineRegistrationProvider).ensureRegistered(_c);
    if (!mounted) return;
    switch (r) {
      case RegistrationOk(:final character):
        _c = character;
        _connect();
      case RegistrationRejected(:final message, :final presetNames):
        setState(() {
          _step = _Step.rejected;
          _message = message;
          _presets = presetNames;
        });
    }
  }

  Future<void> _usePreset(String name) async {
    _c = await ref.read(onlineRegistrationProvider).rename(_c, name);
    await _register();
  }

  void _connect() {
    final backend = ref.read(backendApiProvider);
    final s = RealtimeSession(
      url: Uri.parse(ref.read(realtimeUrlProvider)),
      connect: ref.read(realtimeConnectorProvider),
      auth: backend.realtimeAuth,
      snapshotId: _c.onlineId!,
      backoff: ref.read(realtimeBackoffProvider),
    );
    s
      ..onMatch = _onMatch
      ..onEvents = ((m) => _feed?.addEvents(m))
      ..onSnap = _onSnap
      ..onSel = _onSel
      ..onEnd = _onEnd
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _session = s;
    setState(() => _step = _Step.online);
    unawaited(s.start());
  }

  void _onMatch(MatchMsg m) {
    if (_feed != null && _feed!.match.matchId == m.matchId) return; // resumed
    _feed = OnlineFeed(m);
    unawaited(_buildStage(m));
  }

  Future<void> _buildStage(MatchMsg m) async {
    final me = m.fighters[m.you], foe = m.fighters[1 - m.you];
    final mine = await characterPuppetSpec(ref.read, _c);
    final foePng = await _foePicture(foe);
    if (!mounted || mine == null) return;
    final feed = _feed!;
    setState(() {
      _sides = [
        AtbSide(name: _c.name, level: me.level, puppet: mine),
        AtbSide(
          name: foe.displayName.isEmpty
              ? foe.characterName
              : '${foe.characterName}（${foe.displayName}）',
          level: foe.level,
          puppet: PuppetSpec(
            png: foePng,
            rig: CharacterRig.fromBlob(foe.rig),
            look: PuppetLook.of(level: foe.level),
          ),
        ),
      ];
      _controller = BattleStageController(
        feed: AtbFeed(feed, timeScale: ref.read(battleTimeScaleProvider)),
        seed: m.matchId.hashCode & 0x7fffffff,
        theme: StageTheme.forWorld(1 + m.matchId.hashCode.abs() % 8),
      )..addListener(_onStage);
    });
  }

  Future<Uint8List> _foePicture(FighterInfo foe) async {
    final path = foe.imagePath;
    if (path != null) {
      final png = await ref.read(backendApiProvider).loadSnapshotImage(path);
      if (png != null) return png;
    }
    return ref.read(assetBytesProvider(kOnlineFallbackPicture).future);
  }

  void _onSnap(SnapMsg m) {
    final feed = _feed;
    if (feed == null) return;
    feed.addSnap(m);
    final v = feed.view(0);
    if (v == null) return;
    if (_wasReady && !v.ready) _pending = null; // the move went out
    if (v.ready && !_wasReady) {
      _readyClock
        ..reset()
        ..start();
    }
    _wasReady = v.ready;
    if (v.ready && _omakase && _pending == null) _select(_omakasePick(v));
  }

  void _onSel(SelMsg m) {
    if (!m.accepted && m.reason == 'unusable') {
      setState(() => _pending = null); // let the child pick again
    }
  }

  void _onEnd(EndMsg m) {
    _feed?.finish(m.winner);
    if (m.reason == 'aborted' || _controller == null) {
      unawaited(_showResult(m));
    }
  }

  void _onStage() {
    final c = _controller;
    final end = _session?.end;
    if (c != null && c.over && end != null) unawaited(_showResult(end));
  }

  Future<void> _showResult(EndMsg m) async {
    if (_finishing) return;
    _finishing = true;
    final rewards = ref.read(battleRewardsProvider);
    final outcome = m.reason == 'aborted'
        ? BattleOutcome(
            characterId: _c.id,
            won: false,
            xpGained: 0,
            levelBefore: _c.level,
            levelAfter: _c.level,
            online: true,
            aborted: true,
          )
        : await rewards.applyOnlineResult(
                player: ref.read(characterByIdProvider(_c.id)) ?? _c,
                matchId: m.matchId,
                xp: m.xp,
                won: m.outcome == 'win',
                badge: m.badge,
                badgeUp: m.badgeUp,
              ) ??
              BattleOutcome(
                characterId: _c.id,
                won: m.outcome == 'win',
                xpGained: 0,
                levelBefore: _c.level,
                levelAfter: _c.level,
                online: true,
                badge: m.badge,
              );
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) context.pushReplacement(Routes.battleResult, extra: outcome);
  }

  int _omakasePick(SideView v) {
    final moves = _feed!.moves[0];
    var best = 0;
    for (var i = 0; i < moves.length; i++) {
      if (v.sp >= moves[i].spCost * 100 &&
          moves[i].spCost >= moves[best].spCost) {
        best = i;
      }
    }
    return best;
  }

  void _select(int slot) {
    setState(() => _pending = slot);
    _session?.select(slot);
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (_step == _Step.registering) {
      return const _Waiting(
        key: Key('online-registering'),
        text: 'キャラを しんさ しているよ…',
      );
    }
    if (_step == _Step.rejected) {
      return _Problem(
        message: _message,
        presets: _presets,
        onPreset: _usePreset,
      );
    }
    if (s == null) return const _Waiting(text: '');
    switch (s.phase) {
      case RealtimePhase.failed:
        return _Problem(
          message: s.error ?? 'うまく いかなかったよ',
          offerSinglePlayer: true,
          characterId: _c.id,
        );
      case RealtimePhase.connecting || RealtimePhase.searching:
        return const _Waiting(
          key: Key('online-waiting'),
          text: 'あいてを さがしているよ…',
        );
      case RealtimePhase.battle || RealtimePhase.ended:
        final c = _controller, sides = _sides;
        if (c == null || sides == null) {
          return const _Waiting(key: Key('online-starting'), text: 'はじまるよ！');
        }
        return Scaffold(
          body: AtbStageLayout(
            controller: c,
            sides: sides,
            top: (_) => _foeReport(),
            bottom: (_) => c.over ? const SizedBox(height: 120) : _controls(),
          ),
        );
    }
  }

  Widget _foeReport() {
    final m = _session?.match;
    final id = m?.fighters[1 - m.you].snapshotId;
    if (id == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        key: const Key('online-report'),
        iconSize: 28,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.flag_outlined),
        onPressed: () => showReportSheet(context, ref, id),
      ),
    );
  }

  Widget _controls() {
    final feed = _feed!;
    final v = feed.view(0);
    final ready = v?.ready ?? false;
    final m = feed.match;
    final total = (m.decisionTicks + 3) / m.tickHz;
    final left = ready && !_omakase
        ? (total - _readyClock.elapsedMilliseconds / 1000).clamp(0.0, total)
        : null;
    final moves = feed.moves[0];
    return BattleControls(
      moves: [for (final (i, mv) in moves.indexed) moveButtonData(mv, i)],
      selected: _pending,
      choiceLeft: left,
      decisionSeconds: total,
      casting: v?.casting ?? false,
      omakase: _omakase,
      onOmakase: (on) => setState(() {
        _omakase = on;
        if (on && ready && _pending == null) _select(_omakasePick(v!));
      }),
      onTap: _select,
      usable: (i) => v == null || v.sp >= moves[i].spCost * 100,
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('オンライン たいせん')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(strokeWidth: 10),
          ),
          const SizedBox(height: 24),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            key: const Key('online-cancel'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
            label: const Text('やめる'),
          ),
        ],
      ),
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.message,
    this.presets = const [],
    this.onPreset,
    this.offerSinglePlayer = false,
    this.characterId,
  });
  final String message;
  final List<String> presets;
  final ValueChanged<String>? onPreset;
  final bool offerSinglePlayer;
  final String? characterId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('オンライン たいせん')),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.sentiment_neutral,
                size: 72,
                color: AppColors.secondary,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                key: const Key('online-message'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in presets)
                    ActionChip(
                      key: Key('online-preset-$n'),
                      label: Text(n, style: const TextStyle(fontSize: 20)),
                      onPressed: () => onPreset?.call(n),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (offerSinglePlayer && characterId != null) ...[
                FilledButton.icon(
                  key: const Key('online-single'),
                  icon: const Icon(Icons.sports_martial_arts),
                  onPressed: () =>
                      context.pushReplacement(Routes.stages(characterId!)),
                  label: const Text('ひとりで あそぶ'),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
                label: const Text('もどる'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
