/// Route paths (see docs/UI.md for the route map).
abstract final class Routes {
  static const splash = '/splash';
  static const setup = '/setup';
  static const home = '/';
  static const draw = '/draw';
  static const birth = '/birth';
  static const naming = '/birth/name';
  static const zukan = '/zukan';
  static String character(String id) => '/zukan/$id';
  static String characterAr(String id) => '/zukan/$id/ar';

  /// 「うごく ところを なおそう」 joint editor (docs/PUPPET.md §3);
  /// [first]: right after birth (skippable, then the character page).
  static String characterJoints(String id, {bool first = false}) =>
      '/zukan/$id/joints${first ? '?first=1' : ''}';

  /// Drawing loop (docs/LOOP.md): move the parts / draw a new part / draw
  /// a move effect (`move` = `DrawnMove.name`), and the おだい calendar.
  static String characterParts(String id) => '/zukan/$id/parts';
  static String characterNewPart(String id) => '/zukan/$id/parts/new';
  static String characterEffect(String id, String move) =>
      '/zukan/$id/effect/$move';
  static const odai = '/odai';
  static const battle = '/battle';
  /// Single-player: the 10 worlds, then the 10 stages of one world.
  static String stages(String characterId) => '/battle/$characterId/stages';
  static String world(String characterId, int world) =>
      '/battle/$characterId/world/$world';
  static String cpuBattle(String characterId, int stage) =>
      '/battle/$characterId/stage/$stage';
  static const battleResult = '/battle/result';
  static const online = '/online';
  static String onlineQueue(String characterId) => '/online/queue/$characterId';
  static const parent = '/parent';

  /// かぞくで たいせん (docs/FAMILY.md): setup, then the hot-seat battle
  /// (`extra`: FamilyBattleConfig).
  static const family = '/family';
  static const familyBattle = '/family/battle';

  /// キャラカード: choose up to 9 from the ずかん, then preview / print.
  static const cardSelect = '/zukan/cards';
  static String cardPrint(Iterable<String> ids) =>
      '/zukan/cards/print?ids=${ids.map(Uri.encodeQueryComponent).join(',')}';

  /// 2.5D puppets / stage debug page (debug builds only),
  /// `features/battle_stage/debug/`.
  static const debug25d = '/debug/25d';
}
