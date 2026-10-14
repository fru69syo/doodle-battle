/// Shared pieces of every v2 battle screen (single-player, online, family):
/// move buttons from engine moves, the feed wrapper (test time scale, drawn
/// effects) and the stage + status panels layout.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/battle_v3/battle_v3.dart';
import '../../domain/character_v2_view.dart';
import '../battle_stage/battle_stage.dart';
import '../battle_stage/stage_overlay.dart';
import '../puppet/puppet_builder.dart';

/// Multiplies battle time (tests run battles faster; 1 in the app).
final battleTimeScaleProvider = Provider<double>((ref) => 1);

/// Button data of an engine move. Slot 4 (ひっさつ) is gold.
MoveButtonData moveButtonData(Move m, int slot) => MoveButtonData(
  name: moveDisplayName(m),
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

/// Wraps a [StageFeed]: scales time ([battleTimeScaleProvider]) and marks
/// the slots whose effect the child drew (docs/LOOP.md) so the stage flies
/// their drawing.
class AtbFeed implements StageFeed {
  AtbFeed(this.inner, {this.timeScale = 1});

  final StageFeed inner;
  final double timeScale;

  /// side → slots with a drawn effect (set once the pictures loaded).
  Map<int, Set<int>> drawnSlots = const {};

  @override
  List<StageEvent> advance(double dt) => [
    for (final e in inner.advance(dt * timeScale))
      if (e is StageAction && (drawnSlots[e.side]?.contains(e.slot) ?? false))
        StageAction(
          side: e.side,
          slot: e.slot,
          move: StageMove(
            name: e.move.name,
            kind: e.move.kind,
            vfx: e.move.vfx,
            colour: e.move.colour,
            hits: e.move.hits,
            special: e.move.special,
            drawnEffect: true,
          ),
          hits: e.hits,
          outcomes: e.outcomes,
        )
      else
        e,
  ];

  @override
  StageFighterState fighter(int side) => inner.fighter(side);
}

/// Decodes drawn effect PNGs for [BattleStage.drawnEffects].
Future<Map<int, ui.Image>> decodeDrawnEffects(Map<int, Uint8List> pngs) async {
  final out = <int, ui.Image>{};
  for (final e in pngs.entries) {
    try {
      final codec = await ui.instantiateImageCodec(e.value);
      out[e.key] = (await codec.getNextFrame()).image;
      codec.dispose();
    } on Object {
      // A broken drawing falls back to the normal effect.
    }
  }
  return out;
}

/// One side as the overlay shows it.
class AtbSide {
  const AtbSide({
    required this.name,
    required this.level,
    required this.puppet,
  });
  final String name;
  final int level;
  final PuppetSpec puppet;
}

/// The 2.5D stage with both status panels on top and [bottom] (controls or
/// result) at the bottom. [top] sits above the panels (close button; the
/// second family player's controls, upside down).
class AtbStageLayout extends StatelessWidget {
  const AtbStageLayout({
    super.key,
    required this.controller,
    required this.sides,
    required this.bottom,
    this.top,
    this.drawnEffects = const {},
    this.autoStart = true,
    this.quality,
    this.playerSide = 0,
  });

  final BattleStageController controller;
  final List<AtbSide> sides;

  /// Rebuilt with the controller (every frame while the battle runs).
  final WidgetBuilder bottom;
  final WidgetBuilder? top;
  final Map<int, ui.Image> drawnEffects;
  final bool autoStart;
  final StageQuality? quality;

  /// Highlighted panel (-1: none, e.g. family battles).
  final int playerSide;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      BattleStage(
        controller: controller,
        fighters: [for (final s in sides) s.puppet],
        drawnEffects: drawnEffects,
        autoStart: autoStart,
        quality: quality,
      ),
      ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SafeArea(
          child: Column(
            children: [
              ?top?.call(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Row(
                  children: [
                    for (var i = 0; i < 2; i++) ...[
                      if (i == 1) const SizedBox(width: 8),
                      Expanded(
                        child: FighterStatusPanel(
                          key: Key('panel-$i'),
                          name: sides[i].name,
                          level: sides[i].level,
                          hp: controller.shownHp(i),
                          state: controller.state(i),
                          isPlayer: i == playerSide,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: bottom(context),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// The player's controls over a local engine feed ([BattleV3Feed]-like):
/// さきどり taps, the 5 s ring, おまかせ. Rebuilt with the controller.
class LocalControls extends StatelessWidget {
  const LocalControls({
    super.key,
    required this.engine,
    required this.side,
    required this.selected,
    required this.choiceLeft,
    required this.omakase,
    required this.onOmakase,
    required this.onTap,
  });

  final Battle engine;
  final int side;
  final int? selected;
  final double? choiceLeft;
  final bool omakase;
  final ValueChanged<bool> onOmakase;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final f = engine.fighters[side];
    return BattleControls(
      moves: [for (final (i, m) in f.moves.indexed) moveButtonData(m, i)],
      selected: selected,
      choiceLeft: choiceLeft,
      decisionSeconds: engine.spec.decisionTicks / engine.spec.tickHz,
      casting: f.phase == Phase.casting,
      omakase: omakase,
      onOmakase: onOmakase,
      onTap: onTap,
      usable: f.usable,
      cooldownSeconds: (i) => f.cooldowns[i] / engine.spec.tickHz,
    );
  }
}
