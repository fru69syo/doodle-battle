/// Base battle stats of a character. All values are non-negative integers.
///
/// `hp` is the raw stat; the HP shown in battle is defined by the battle spec.
class Stats {
  const Stats({
    required this.hp,
    required this.atk,
    required this.def,
    required this.spd,
  });

  final int hp;
  final int atk;
  final int def;
  final int spd;

  int get total => hp + atk + def + spd;

  Stats copyWith({int? hp, int? atk, int? def, int? spd}) => Stats(
    hp: hp ?? this.hp,
    atk: atk ?? this.atk,
    def: def ?? this.def,
    spd: spd ?? this.spd,
  );

  Map<String, Object?> toJson() => {
    'hp': hp,
    'atk': atk,
    'def': def,
    'spd': spd,
  };

  factory Stats.fromJson(Map<String, Object?> json) => Stats(
    hp: json['hp']! as int,
    atk: json['atk']! as int,
    def: json['def']! as int,
    spd: json['spd']! as int,
  );

  @override
  bool operator ==(Object other) =>
      other is Stats &&
      other.hp == hp &&
      other.atk == atk &&
      other.def == def &&
      other.spd == spd;

  @override
  int get hashCode => Object.hash(hp, atk, def, spd);

  @override
  String toString() => 'Stats(hp: $hp, atk: $atk, def: $def, spd: $spd)';
}

/// Which stat a "パワーのたね" was spent on.
enum StatKind { hp, atk, def, spd }
