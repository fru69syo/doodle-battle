import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';
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

/// Online rated battle (SPEC §7.2): registration (server review) →
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

  // A report made during the battle waits for the server's `end`: the
  // match record it is checked against is written when the match is settled.
  (String, ReportReason)? _heldReport;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void dispose() {
    _sendHeldReport();
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

  bool _reregistered = false;

  /// The server does not know the snapshot (e.g. a v1 snapshot after the
  /// v2 switch): register again via schema 2, silently, once.
  Future<void> _onSessionChanged() async {
    final s = _session;
    if (s == null || !mounted) return;
    final code = s.errorCode;
    if (s.phase == RealtimePhase.failed &&
        (code == 'NOT_FOUND' || code == 'NOT_OWNER') &&
        !_reregistered) {
      _reregistered = true;
      _session = null;
      unawaited(Future<void>.microtask(s.dispose));
      _c = await ref.read(onlineRegistrationProvider).forgetSnapshot(_c);
      await _register();
      return;
    }
    setState(() {});
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
      ..addListener(() => unawaited(_onSessionChanged()));
    _session = s;
    setState(() => _step = _Step.online);
    unawaited(s.start());
  }

  void _onMatch(MatchMsg m) {
    if (_feed != null && _feed!.match.matchId == m.matchId) return; // resumed
    _feed = OnlineFeed(m)
      ..onMyAction = () {
        // The move went out (さきどり used, or the server's おまかせ).
        if (mounted && _pending != null) setState(() => _pending = null);
      };
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

  void _onSnap(SnapMsg m) => _feed?.addSnap(m);

  void _onSel(SelMsg m) {
    if (!m.accepted && m.reason == 'unusable') {
      setState(() => _pending = null); // let the child pick again
    }
  }

  void _onEnd(EndMsg m) {
    _feed?.finish(m.winner);
    _sendHeldReport(); // the match record exists now
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

  void _setOmakase(bool on) {
    setState(() {
      _omakase = on;
      if (on) _pending = null; // the server drops a pending さきどり too
    });
    _session?.setOmakase(on);
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

  /// Report button for the opponent's character (SPEC §9.4). Not for a
  /// mirror ghost (that is the child's own character).
  Widget _foeReport() {
    final m = _session?.match;
    final id = m?.fighters[1 - m.you].snapshotId;
    if (id == null || id == _c.onlineId) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        key: const Key('online-report'),
        iconSize: 28,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(_reported ? Icons.flag : Icons.flag_outlined),
        onPressed: _reported ? null : () => unawaited(_report(id)),
      ),
    );
  }

  Future<void> _report(String snapshotId) async {
    final reason = await pickReportReason(context);
    if (reason == null || !mounted) return;
    setState(() => _reported = true);
    if (_session?.end != null) {
      await _sendReport(snapshotId, reason);
    } else {
      _heldReport = (snapshotId, reason);
    }
    if (mounted) await showReportThanks(context);
  }

  void _sendHeldReport() {
    final r = _heldReport;
    if (r == null) return;
    _heldReport = null;
    unawaited(_sendReport(r.$1, r.$2));
  }

  Future<void> _sendReport(String snapshotId, ReportReason reason) async {
    try {
      await ref.read(backendApiProvider).reportCharacter(snapshotId, reason);
    } on Object {
      // Offline / refused: the child was already thanked; nothing to tell.
    }
  }

  Widget _controls() {
    final feed = _feed!;
    final v = feed.view(0);
    final me = feed.fighter(0);
    final moves = feed.moves[0];
    return BattleControls(
      moves: [for (final (i, mv) in moves.indexed) moveButtonData(mv, i)],
      selected: _pending,
      bars: me.bars,
      full: me.full,
      casting: v?.casting ?? false,
      omakase: _omakase,
      onOmakase: _setOmakase,
      onTap: _select,
      // Dimmed until the bars are there (the server keeps the さきどり);
      // a move above the max bars can never be picked.
      usable: (i) => me.bars >= moves[i].bars,
      queueable: (i) => moves[i].bars <= me.maxBars,
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
