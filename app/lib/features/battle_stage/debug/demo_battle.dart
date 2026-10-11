import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../domain/battle/rng.dart';
import '../../../domain/battle_v2/battle_v2.dart';
import '../../../domain/battle_v2/sim_v2.dart'
    show randomBloomer, randomKid, setupAt;
import '../../puppet/puppet_builder.dart';
import '../../puppet/puppet_look.dart';
import '../adapters/battle_v2_feed.dart';
import '../battle_stage.dart';
import '../stage_overlay.dart';

/// One side of a demo battle (debug page, render tests, perf tests).
class DemoSide {
  const DemoSide({
    required this.png,
    required this.name,
    this.level = 12,
    this.lateBloomer = false,
    this.rigJson,
    this.genomeSeed = 1,
  });
  final Uint8List png;
  final String name;
  final int level;

  /// Hidden late bloomer: only turned into a [PuppetLook] here.
  final bool lateBloomer;
  final String? rigJson;
  final int genomeSeed;

  PuppetLook get look => PuppetLook.of(level: level, lateBloomer: lateBloomer);

  PuppetSpec puppet({PuppetQuality quality = PuppetQuality.high}) =>
      PuppetSpec(png: png, rigJson: rigJson, look: look, quality: quality);
}

/// The prototype v3 engine set up for two demo sides.
AtbBattle demoEngine(List<DemoSide> sides, {int seed = 7}) {
  const spec = V2Spec();
  final setups = <FighterSetupV2>[];
  for (final s in sides) {
    final r = Mulberry32(s.genomeSeed);
    final g = s.lateBloomer ? randomBloomer(spec, r) : randomKid(spec, r);
    final base = setupAt(spec, g, s.level);
    setups.add(
      FighterSetupV2(
        stats: base.stats,
        attr: base.attr,
        moves: base.moves,
        label: s.name,
      ),
    );
  }
  return newBattle(spec, setups[0], setups[1], seed: seed, recordEvents: true);
}

MoveButtonData moveButtonOf(MoveV2 m, int slot) => MoveButtonData(
  name: m.name.isEmpty ? m.template : m.name,
  tint: slot == 3
      ? MoveTint.special
      : switch (m.attr) {
          Attr.gu => MoveTint.gu,
          Attr.choki => MoveTint.choki,
          Attr.pa => MoveTint.pa,
          Attr.none => MoveTint.none,
        },
  spCost: m.spCost,
  icon: moveIconFor(m.vfx),
);

/// A complete one-player battle screen on the production widgets: the
/// stage, the two status panels and the controls. Debug route and tests;
/// the integration team builds the real screens from the same parts.
class DemoBattleScreen extends StatefulWidget {
  const DemoBattleScreen({
    super.key,
    required this.player,
    required this.cpu,
    this.seed = 7,
    this.theme = StageTheme.meadow,
    this.quality,
    this.autoStart = true,
  });

  final DemoSide player, cpu;
  final int seed;
  final StageTheme theme;
  final StageQuality? quality;
  final bool autoStart;

  @override
  State<DemoBattleScreen> createState() => DemoBattleScreenState();
}

class DemoBattleScreenState extends State<DemoBattleScreen> {
  late final BattleV2Feed feed = BattleV2Feed(
    demoEngine([widget.player, widget.cpu], seed: widget.seed),
  );
  late final controller = BattleStageController(
    feed: feed,
    theme: widget.theme,
    seed: widget.seed,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sides = [widget.player, widget.cpu];
    return Scaffold(
      backgroundColor: widget.theme.ground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          BattleStage(
            controller: controller,
            fighters: [for (final s in sides) s.puppet()],
            quality: widget.quality,
            autoStart: widget.autoStart,
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    child: Row(
                      children: [
                        for (var i = 0; i < 2; i++) ...[
                          if (i == 1) const SizedBox(width: 8),
                          Expanded(
                            child: FighterStatusPanel(
                              name: sides[i].name,
                              level: sides[i].level,
                              hp: controller.shownHp(i),
                              state: controller.state(i),
                              isPlayer: i == 0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: controller.over ? _result() : _controls(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    final f = feed.engine.fighters[0];
    return BattleControls(
      moves: [for (final (i, m) in f.moves.indexed) moveButtonOf(m, i)],
      selected: feed.pending,
      choiceLeft: feed.choiceLeft,
      decisionSeconds: feed.decisionSeconds,
      casting: f.phase == Phase.casting,
      omakase: feed.alwaysAuto,
      onOmakase: (v) => setState(() {
        feed.alwaysAuto = v;
        feed.pending = null;
      }),
      onTap: (i) => setState(() => feed.tap(i)),
      usable: feed.usable,
      cooldownSeconds: (i) => f.cooldowns[i] / 10,
    );
  }

  Widget _result() {
    final win = controller.winner == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            win ? 'かち！' : 'まけちゃった…',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: win ? const Color(0xFFFF6B35) : const Color(0xFF1F1A3D),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('もどる'),
          ),
        ],
      ),
    );
  }
}
