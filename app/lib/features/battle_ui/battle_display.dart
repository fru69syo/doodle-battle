import '../../domain/battle/battle.dart';
import '../../domain/element_type.dart';

/// Mutable view model of one fighter while events are animated.
class FighterDisplay {
  FighterDisplay({
    required this.name,
    required this.level,
    required this.element,
    required this.maxHp,
    required this.hp,
    this.gauge = 0,
    this.elementMoveName,
    this.specialMoveName,
  });

  final String name;
  final int level;
  final ElementType element;
  final String? elementMoveName;
  final String? specialMoveName;
  int maxHp;
  int hp;
  int gauge;
  bool guarding = false;
  bool fainted = false;

  /// Incremented to trigger the hit-shake / attack-hop animations.
  int shakeTick = 0;
  int hopTick = 0;

  /// Last damage number shown above the fighter (re-shown on [damageTick]).
  int? lastDamage;
  int damageTick = 0;
}

/// Everything the arena shows.
class BattleDisplay {
  BattleDisplay({required FighterDisplay a, required FighterDisplay b})
    : fighters = {Side.a: a, Side.b: b};

  final Map<Side, FighterDisplay> fighters;
  String message = '';

  /// Big banner (e.g. 「こうかは ばつぐんだ！」), cleared on the next message.
  String? banner;

  FighterDisplay operator [](Side s) => fighters[s]!;

  /// Syncs numbers from an authoritative state (start / resync).
  void syncFrom(BattleState s) {
    for (final side in Side.values) {
      final f = s.fighter(side);
      this[side]
        ..maxHp = f.maxHp
        ..hp = f.hp
        ..gauge = f.gauge
        ..fainted = f.fainted;
    }
  }
}

/// Applies [e] to [d] and returns how long the UI should pause afterwards.
/// [texts] are the battle spec's kid messages; [moveName] labels a move.
Duration applyBattleEvent(
  BattleDisplay d,
  BattleEvent e, {
  required Map<String, String> texts,
  required String Function(Side side, BattleAction move) moveName,
  required Duration step,
}) {
  String name(Side s) => d[s].name;
  void say(String m) {
    d.message = m;
    d.banner = null;
  }

  switch (e) {
    case TurnStartEvent():
      for (final f in d.fighters.values) {
        f.guarding = false;
      }
      return Duration.zero;
    case TimeoutEvent(:final side):
      say('${name(side)}: ${texts['timeout'] ?? 'じかんぎれ！'}');
    case SpecialNotReadyEvent(:final side):
      say('${name(side)}: ${texts['specialNotReady'] ?? 'ゲージが たりない！'}');
    case GuardEvent(:final side, :final weakened):
      d[side].guarding = true;
      say(
        weakened
            ? '${name(side)}の まもる！ ${texts['guardWeakened'] ?? ''}'
            : '${name(side)}の まもる！ ${texts['guard'] ?? ''}',
      );
    case MoveEvent(:final side, :final move):
      d[side].hopTick++;
      say('${name(side)}の ${moveName(side, move)}！');
    case MissEvent():
      say(texts['miss'] ?? 'でも はずれた！');
    case CritEvent():
      say(texts['crit'] ?? 'きゅうしょに あたった！');
    case EffectivenessEvent(:final text):
      d.banner = text;
      return step;
    case DamageEvent(:final target, :final amount, :final hp):
      final f = d[target]
        ..hp = hp
        ..lastDamage = amount
        ..damageTick += 1
        ..shakeTick += 1;
      if (f.hp < 0) f.hp = 0;
      return step * 0.7;
    case GaugeEvent(:final side, :final value):
      d[side].gauge = value;
      return Duration.zero;
    case FaintEvent(:final side):
      d[side].fainted = true;
      say('${name(side)}は ${texts['faint'] ?? 'たおれた！'}');
    case BattleEndEvent():
      return Duration.zero;
  }
  return step;
}
