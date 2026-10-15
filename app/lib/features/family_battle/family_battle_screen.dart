import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/character_picture.dart';
import '../../data/drawing_loop_storage.dart';
import '../../domain/battle_v3/battle_v3.dart';
import '../../domain/cosmetics.dart';
import '../battle_stage/adapters/battle_v3_feed.dart';
import '../battle_stage/battle_stage.dart';
import '../battle_ui/atb_parts.dart';
import '../puppet/character_puppet.dart';
import '../puppet/puppet_builder.dart';
import 'family_setup.dart';
import 'family_theme.dart';

/// かぞくで たいせん on one device (docs/FAMILY.md), real-time ATB: あか
/// (side a) plays from the bottom, あお (side b) from the top with its
/// buttons turned towards the player sitting opposite. Each side has its
/// own さきどり, 5 s ring and おまかせ. Levels via [familyBattleLevel]; no
/// XP is given (practice battles).
class FamilyBattleScreen extends ConsumerStatefulWidget {
  const FamilyBattleScreen({super.key, required this.config});
  final FamilyBattleConfig config;

  @override
  ConsumerState<FamilyBattleScreen> createState() => _FamilyBattleScreenState();
}

class _FamilyBattleScreenState extends ConsumerState<FamilyBattleScreen> {
  static const _spec = V3Spec();
  late final FamilyBattleConfig _c = widget.config;
  late final int _seed = ref.read(randomProvider).nextInt(1 << 32);
  late final Battle _engine = Battle(
    _spec,
    _c.setup(FamilySide.a),
    _c.setup(FamilySide.b),
    seed: _seed,
  );
  final _auto = omakaseController();

  /// おまかせ for あお (the feed's own flag is あか's).
  bool _autoB = false;
  late final BattleV3Feed _feed = BattleV3Feed(
    _engine,
    // Side b is a person too: no CPU; null = keep filling (no timer).
    cpu: (b, side) => _autoB ? _auto(b, side) : null,
  );
  late final AtbFeed _atb = AtbFeed(
    _feed,
    timeScale: ref.read(battleTimeScaleProvider),
  );
  late final BattleStageController _controller = BattleStageController(
    feed: _atb,
    seed: _seed,
    theme: StageTheme.candy,
  );
  List<PuppetSpec>? _puppets;
  Map<int, ui.Image> _drawn = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final specs = [
      for (final s in FamilySide.values)
        await characterPuppetSpec(ref.read, _c.player(s).character),
    ];
    // Both players' drawn ぞくせいわざ effects (docs/LOOP.md §5).
    final store = ref.read(drawingLoopStorageProvider);
    final pngs = <int, Uint8List>{};
    final slots = <int, Set<int>>{};
    for (final s in FamilySide.values) {
      final ch = _c.player(s).character;
      final asset =
          ch.cosmetics.effects[DrawnMove.element] ??
          ch.cosmetics.effects[DrawnMove.special];
      if (asset == null) continue;
      final png = await store.readAsset(ch.id, asset);
      if (png == null) continue;
      pngs[s.index] = png;
      slots[s.index] = {
        if (ch.cosmetics.effects.containsKey(DrawnMove.element)) 0,
        if (ch.cosmetics.effects.containsKey(DrawnMove.special)) 3,
      };
    }
    final images = pngs.isEmpty
        ? const <int, ui.Image>{}
        : await decodeDrawnEffects(pngs);
    if (!mounted || specs.any((s) => s == null)) return;
    _atb.drawnSlots = {
      for (final e in slots.entries)
        if (images.containsKey(e.key)) e.key: e.value,
    };
    setState(() {
      _drawn = images;
      _puppets = specs.cast<PuppetSpec>();
    });
  }

  void _tap(int side, int slot) {
    if (side == 0) {
      setState(() => _feed.tap(slot));
      return;
    }
    final f = _engine.fighters[1];
    if (_engine.finished || _autoB || f.phase == Phase.casting) return;
    if (!f.canQueue(slot)) return;
    setState(() => _engine.queueInput(1, slot));
  }

  void _omakase(int side, bool on) => setState(() {
    if (side == 0) {
      _feed.alwaysAuto = on;
      _feed.cancelTap();
    } else {
      _autoB = on;
      _engine.clearInput(1);
      _engine.fighters[1].aiPlan = null;
    }
  });

  Widget _controls(int side) => Container(
    key: Key('family-controls-${FamilySide.values[side].name}'),
    decoration: BoxDecoration(
      border: Border.all(
        color: familyColour(FamilySide.values[side]),
        width: 4,
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: LocalControls(
      engine: _engine,
      side: side,
      selected: _engine.fighters[side].queued,
      omakase: side == 0 ? _feed.alwaysAuto : _autoB,
      onOmakase: (on) => _omakase(side, on),
      onTap: (slot) => _tap(side, slot),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final puppets = _puppets;
    if (puppets == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final winner = _controller.winner;
        if (winner != null) {
          return Scaffold(
            appBar: AppBar(title: const Text('かぞくで たいせん')),
            body: SafeArea(
              child: _Result(
                config: _c,
                winner: FamilySide.values[winner],
                onRematch: () =>
                    context.pushReplacement(Routes.familyBattle, extra: _c),
                onChangeMembers: () => context.pop(),
                onExit: () => context.go(Routes.home),
              ),
            ),
          );
        }
        return Scaffold(
          body: AtbStageLayout(
            controller: _controller,
            drawnEffects: _drawn,
            playerSide: -1,
            sides: [
              for (final s in FamilySide.values)
                AtbSide(
                  name: '${_c.player(s).label}: ${_c.fighterName(s)}',
                  level: _c.battleLevel(s),
                  puppet: puppets[s.index],
                ),
            ],
            top: (_) => Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: RotatedBox(quarterTurns: 2, child: _controls(1)),
            ),
            bottom: (_) => _controls(0),
          ),
        );
      },
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.config,
    required this.winner,
    required this.onRematch,
    required this.onChangeMembers,
    required this.onExit,
  });

  final FamilyBattleConfig config;
  final FamilySide winner;
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
          style: TextButton.styleFrom(minimumSize: const Size(120, 48)),
          onPressed: onExit,
          child: const Text('おわる', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }
}
