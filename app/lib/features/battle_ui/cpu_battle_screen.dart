import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../data/app_state.dart';
import '../../domain/battle_v3/battle_v3.dart';
import '../../domain/character_v2.dart';
import '../../domain/cosmetics.dart';
import '../../domain/cpu_roster_v2.dart';
import '../battle_stage/adapters/battle_v3_feed.dart';
import '../battle_stage/battle_stage.dart';
import '../../data/drawing_loop_storage.dart';
import '../puppet/character_puppet.dart';
import '../puppet/puppet_builder.dart';
import '../puppet/puppet_look.dart';
import 'atb_parts.dart';
import 'battle_outcome.dart';

/// Loads what a single-player battle needs (once), then shows
/// [CpuBattleView].
class CpuBattleScreen extends ConsumerStatefulWidget {
  const CpuBattleScreen({
    super.key,
    required this.characterId,
    required this.stage,
  });
  final String characterId;
  final int stage;

  @override
  ConsumerState<CpuBattleScreen> createState() => _CpuBattleScreenState();
}

class _CpuBattleScreenState extends ConsumerState<CpuBattleScreen> {
  CpuBattleView? _view;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final chars = await ref.read(charactersProvider.future);
    final player = chars.where((c) => c.id == widget.characterId).firstOrNull;
    if (player == null) return;
    final roster = await ref.read(cpuRosterV2Provider.future);
    final st = stageAt(widget.stage.clamp(1, 100));
    final cpu = roster.byId[st.cpuId];
    if (cpu == null) return;
    final cpuPng = await ref.read(assetBytesProvider(cpu.asset).future);
    final spec = await characterPuppetSpec(ref.read, player);
    final progress = await ref.read(progressProvider.future);
    if (!mounted || spec == null) return;
    setState(
      () => _view = CpuBattleView(
        player: player,
        playerPuppet: spec,
        cpuPuppet: PuppetSpec(
          png: cpuPng,
          look: PuppetLook.of(level: st.cpuLevel),
        ),
        cpuName: cpu.name,
        stage: st,
        roster: roster,
        omakase: progress.omakase,
        seed: ref.read(randomProvider).nextInt(1 << 32),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      _view ?? const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// A real-time ATB battle against the stage's CPU on the 2.5D stage. The
/// child only picks moves (さきどり while the gauge fills, 5 s ring, おまかせ).
class CpuBattleView extends ConsumerStatefulWidget {
  const CpuBattleView({
    super.key,
    required this.player,
    required this.playerPuppet,
    required this.cpuPuppet,
    required this.cpuName,
    required this.stage,
    required this.roster,
    required this.omakase,
    required this.seed,
  });

  final CharacterV2 player;
  final PuppetSpec playerPuppet, cpuPuppet;
  final String cpuName;
  final Stage stage;
  final CpuRosterV2 roster;
  final bool omakase;
  final int seed;

  @override
  ConsumerState<CpuBattleView> createState() => _CpuBattleViewState();
}

class _CpuBattleViewState extends ConsumerState<CpuBattleView> {
  static const _spec = V3Spec();
  late final Battle _engine = Battle(
    _spec,
    widget.player.battleSetup(),
    widget.roster.stageFighter(widget.stage),
    seed: widget.seed,
  );
  late final BattleV3Feed _feed = BattleV3Feed(
    _engine,
    alwaysAuto: widget.omakase,
    cpu: aiController(tier: widget.stage.tier),
  );
  late final BattleStageController _controller;
  Map<int, ui.Image> _drawn = const {};
  late final AtbFeed _atbFeed;
  bool _finishing = false;

  /// The stage starts once the drawn effects are known.
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _atbFeed = AtbFeed(_feed, timeScale: ref.read(battleTimeScaleProvider));
    _controller = BattleStageController(
      feed: _atbFeed,
      theme: StageTheme.forWorld(widget.stage.world),
      seed: widget.seed,
    )..addListener(_onChange);
    unawaited(_loadDrawnEffects());
  }

  /// The child's drawn ぞくせいわざ / ひっさつ effects (docs/LOOP.md §5).
  Future<void> _loadDrawnEffects() async {
    try {
      await _loadDrawnEffectsInner();
    } on Object {
      // Default effects.
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _loadDrawnEffectsInner() async {
    final store = ref.read(drawingLoopStorageProvider);
    final pngs = <DrawnMove, Uint8List>{};
    for (final e in widget.player.cosmetics.effects.entries) {
      final png = await store.readAsset(widget.player.id, e.value);
      if (png != null) pngs[e.key] = png;
    }
    if (pngs.isEmpty) return;
    final images = await decodeDrawnEffects({
      0: pngs[DrawnMove.element] ?? pngs[DrawnMove.special]!,
    });
    if (!mounted || images.isEmpty) return;
    _atbFeed.drawnSlots = {
      0: {
        if (pngs.containsKey(DrawnMove.element)) 0,
        if (pngs.containsKey(DrawnMove.special)) 3,
      },
    };
    _drawn = images;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  void _onChange() {
    if (_controller.over && !_finishing) _finish();
  }

  Future<void> _finish() async {
    _finishing = true;
    final won = _controller.winner == 0;
    final me = _engine.fighters[0];
    final outcome = await ref
        .read(battleRewardsProvider)
        .applyCpuResult(
          player: widget.player,
          stage: widget.stage.stage,
          won: won,
          stars: stageStars(
            won: won,
            hp: me.hp,
            maxHp: me.maxHp,
            ticks: _engine.tick,
          ),
        );
    // Let the K.O. sink in.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) context.pushReplacement(Routes.battleResult, extra: outcome);
  }

  void _setOmakase(bool on) {
    setState(() {
      _feed.alwaysAuto = on;
      _feed.cancelTap();
    });
    unawaited(ref.read(progressProvider.notifier).setOmakase(on));
  }

  @override
  Widget build(BuildContext context) {
    final theme = StageTheme.forWorld(widget.stage.world);
    if (!_ready) {
      return Scaffold(
        backgroundColor: theme.skyBottom,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: theme.ground,
      body: AtbStageLayout(
        controller: _controller,
        drawnEffects: _drawn,
        sides: [
          AtbSide(
            name: widget.player.name,
            level: widget.player.level,
            puppet: widget.playerPuppet,
          ),
          AtbSide(
            name: widget.cpuName,
            level: widget.stage.cpuLevel,
            puppet: widget.cpuPuppet,
            // A world's boss (stage 10) is drawn bigger; visual only.
            size: widget.stage.boss ? kBossSize : 1,
          ),
        ],
        top: (_) => Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            key: const Key('battle-close'),
            iconSize: 32,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        bottom: (_) => _controller.over
            ? const SizedBox(height: 120)
            : LocalControls(
                engine: _engine,
                side: 0,
                selected: _feed.pending,
                choiceLeft: _feed.choiceLeft,
                omakase: _feed.alwaysAuto,
                onOmakase: _setOmakase,
                onTap: (i) => setState(() => _feed.tap(i)),
              ),
      ),
    );
  }
}
