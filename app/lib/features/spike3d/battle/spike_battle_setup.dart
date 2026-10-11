import 'atb.dart';

/// Placeholder fighters for the prototype (stats are not balanced; the
/// game-design team owns the real 10-stat model, SPEC §12.3).
AtbBattle spikeBattle({
  int seed = 1,
  int playerAgi = 14,
  int cpuAgi = 12,
  int moveCount = 4,
}) {
  const moves = [
    SpikeMove('ぽかぽかパンチ', power: 30),
    SpikeMove('ぐるぐるキック', power: 38),
    SpikeMove('きらきらビーム', power: 45),
    SpikeMove('どっすんアタック', power: 55),
  ];
  return AtbBattle([
    SpikeFighter(
      name: 'ぷっくり',
      maxHp: 220,
      agi: playerAgi,
      str: 20,
      def: 16,
      moves: moves.take(moveCount).toList(),
    ),
    SpikeFighter(
      name: 'あおまる',
      maxHp: 200,
      agi: cpuAgi,
      str: 18,
      def: 15,
      moves: moves.take(2).toList(),
    ),
  ], seed: seed);
}
