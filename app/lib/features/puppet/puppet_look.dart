/// How a character's puppet looks, derived from its level and the hidden
/// late-bloomer flag (GAME_DESIGN_V2 §4.4). The flag itself never reaches
/// widgets: callers turn it into a [PuppetLook] at the engine boundary and
/// only the look travels on.
class PuppetLook {
  const PuppetLook({this.simple = false, this.legend = false});

  /// Level at which every character becomes でんせつ and the hidden late
  /// bloomer is rebuilt (GAME_DESIGN_V2 §4.4, `V2Spec.rebirthLevel`).
  static const legendLevel = 50;

  /// Three flat colours, rounded shape, body-only rig (squash / hop /
  /// wobble), half effects. Only the hidden late bloomer before Lv50.
  final bool simple;

  /// Gold でんせつ aura and 1.4× effects: every character from Lv50, so the
  /// late bloomer's rebuild is indistinguishable from everyone's evolution.
  final bool legend;

  static PuppetLook of({required int level, bool lateBloomer = false}) =>
      PuppetLook(
        simple: lateBloomer && level < legendLevel,
        legend: level >= legendLevel,
      );

  /// Effect intensity for the stage (particles, size, shake).
  double get fxScale => simple ? 0.5 : (legend ? 1.4 : 1.0);

  @override
  bool operator ==(Object other) =>
      other is PuppetLook && other.simple == simple && other.legend == legend;

  @override
  int get hashCode => Object.hash(simple, legend);
}
