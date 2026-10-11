import 'dart:ui';

/// Background props scattered on the ground (drawn with the fighters, by
/// depth).
enum PropKind { flower, stone, bush, tuft, shell, snowman, candy, cactus, mushroom, star }

/// Tree-line silhouettes behind the arena.
enum TreeKind { round, pine, palm, lollipop, cactus, none }

/// Falling / floating ambient particles.
enum Ambient { none, snow, petals, bubbles, stars, embers }

/// A kid-friendly stage look. Plain data so new themes are cheap.
class StageTheme {
  const StageTheme({
    required this.id,
    required this.name,
    required this.skyTop,
    required this.skyBottom,
    required this.farHill,
    required this.nearHill,
    required this.ground,
    required this.stripe,
    required this.arena,
    required this.trees,
    required this.treeColor,
    required this.props,
    this.sun = const Color(0xFFFFE066),
    this.moon = false,
    this.ambient = Ambient.none,
    this.hillOutline = const Color(0x553A6B35),
    this.water = false,
  });

  final String id;

  /// Hiragana name (stage select, debug).
  final String name;
  final Color skyTop, skyBottom, farHill, nearHill, ground, stripe, arena;
  final TreeKind trees;
  final Color treeColor;
  final List<PropKind> props;
  final Color sun;

  /// Night: a moon and stars instead of the sun.
  final bool moon;
  final Ambient ambient;
  final Color hillOutline;

  /// Sea instead of near hills (beach).
  final bool water;

  static const meadow = StageTheme(
    id: 'meadow',
    name: 'くさはら',
    skyTop: Color(0xFF8FD3FF),
    skyBottom: Color(0xFFDDF3FF),
    farHill: Color(0xFFA7D99A),
    nearHill: Color(0xFF7CC576),
    ground: Color(0xFF8ED36B),
    stripe: Color(0xFF9FDC7C),
    arena: Color(0x55F3E2A9),
    trees: TreeKind.round,
    treeColor: Color(0xFF4FAF5A),
    props: [PropKind.flower, PropKind.stone, PropKind.bush, PropKind.tuft],
    ambient: Ambient.petals,
  );

  static const forest = StageTheme(
    id: 'forest',
    name: 'もり',
    skyTop: Color(0xFF9ED8E8),
    skyBottom: Color(0xFFE6F6EC),
    farHill: Color(0xFF6FAE7A),
    nearHill: Color(0xFF4E9A5C),
    ground: Color(0xFF6BBE5A),
    stripe: Color(0xFF79C866),
    arena: Color(0x55C9A66B),
    trees: TreeKind.pine,
    treeColor: Color(0xFF2F7D46),
    props: [PropKind.mushroom, PropKind.stone, PropKind.bush, PropKind.tuft],
  );

  static const beach = StageTheme(
    id: 'beach',
    name: 'うみ',
    skyTop: Color(0xFF6EC6FF),
    skyBottom: Color(0xFFE3F7FF),
    farHill: Color(0xFFB5E3F5),
    nearHill: Color(0xFF3FA9E0),
    ground: Color(0xFFF3DFA2),
    stripe: Color(0xFFF7E7B6),
    arena: Color(0x44FFFFFF),
    trees: TreeKind.palm,
    treeColor: Color(0xFF3DAA5C),
    props: [PropKind.shell, PropKind.stone, PropKind.star, PropKind.shell],
    ambient: Ambient.bubbles,
    water: true,
  );

  static const desert = StageTheme(
    id: 'desert',
    name: 'さばく',
    skyTop: Color(0xFFFFB86B),
    skyBottom: Color(0xFFFFE9B8),
    farHill: Color(0xFFF2C27B),
    nearHill: Color(0xFFE6A85C),
    ground: Color(0xFFF0CF8C),
    stripe: Color(0xFFF5DAA3),
    arena: Color(0x44FFFFFF),
    trees: TreeKind.cactus,
    treeColor: Color(0xFF5BAA55),
    props: [PropKind.cactus, PropKind.stone, PropKind.stone, PropKind.tuft],
    sun: Color(0xFFFFF0A0),
    hillOutline: Color(0x55A0602A),
  );

  static const snow = StageTheme(
    id: 'snow',
    name: 'ゆきやま',
    skyTop: Color(0xFFA9D2F5),
    skyBottom: Color(0xFFEFF6FF),
    farHill: Color(0xFFE2EDF8),
    nearHill: Color(0xFFCADDF0),
    ground: Color(0xFFF4F8FF),
    stripe: Color(0xFFE8F0FB),
    arena: Color(0x33A9C8E8),
    trees: TreeKind.pine,
    treeColor: Color(0xFF3E8E6A),
    props: [PropKind.snowman, PropKind.stone, PropKind.tuft, PropKind.star],
    ambient: Ambient.snow,
    hillOutline: Color(0x557A9CC0),
  );

  static const candy = StageTheme(
    id: 'candy',
    name: 'おかしのくに',
    skyTop: Color(0xFFFFB3DA),
    skyBottom: Color(0xFFFFEAF5),
    farHill: Color(0xFFFFD1E8),
    nearHill: Color(0xFFC9A0F0),
    ground: Color(0xFFFFE1A8),
    stripe: Color(0xFFFFEBC4),
    arena: Color(0x44FFFFFF),
    trees: TreeKind.lollipop,
    treeColor: Color(0xFFFF6FB0),
    props: [PropKind.candy, PropKind.star, PropKind.candy, PropKind.flower],
    ambient: Ambient.stars,
    hillOutline: Color(0x55A0507A),
  );

  static const night = StageTheme(
    id: 'night',
    name: 'よぞら',
    skyTop: Color(0xFF1E2A5C),
    skyBottom: Color(0xFF4B5BA6),
    farHill: Color(0xFF34407A),
    nearHill: Color(0xFF2A3466),
    ground: Color(0xFF4C7A5A),
    stripe: Color(0xFF568565),
    arena: Color(0x33FFF3B0),
    trees: TreeKind.round,
    treeColor: Color(0xFF2E5A44),
    props: [PropKind.mushroom, PropKind.stone, PropKind.star, PropKind.tuft],
    sun: Color(0xFFFFF6C8),
    moon: true,
    ambient: Ambient.stars,
    hillOutline: Color(0x55141A33),
  );

  static const volcano = StageTheme(
    id: 'volcano',
    name: 'かざん',
    skyTop: Color(0xFFFF8A65),
    skyBottom: Color(0xFFFFD3B0),
    farHill: Color(0xFF8D6E63),
    nearHill: Color(0xFF6D4C41),
    ground: Color(0xFFB08A6E),
    stripe: Color(0xFFBC977B),
    arena: Color(0x44FFE0B2),
    trees: TreeKind.none,
    treeColor: Color(0xFF5D4037),
    props: [PropKind.stone, PropKind.stone, PropKind.tuft, PropKind.star],
    sun: Color(0xFFFFE082),
    ambient: Ambient.embers,
    hillOutline: Color(0x55301810),
  );

  static const all = [meadow, forest, beach, desert, snow, candy, night, volcano];

  /// The stage look of world 1–10 (one-player mode: 3 stages per world).
  /// Worlds 9 and 10 revisit the first lands at night / in candy colours.
  static StageTheme forWorld(int world) => switch (world) {
    1 => meadow,
    2 => forest,
    3 => beach,
    4 => desert,
    5 => snow,
    6 => candy,
    7 => volcano,
    8 => night,
    9 => forest,
    10 => candy,
    _ => meadow,
  };

  static StageTheme byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => meadow);
}
