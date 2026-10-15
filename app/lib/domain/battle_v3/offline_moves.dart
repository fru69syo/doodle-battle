/// Offline move generator (no cloud consent, or an AI slot was rejected):
/// deterministic from the image hash. docs/GAME_DESIGN_V2.md §5.7.
library;

import 'genome.dart';
import 'moves.dart';
import 'rng.dart';
import 'spec.dart';

const Map<Attr, List<String>> _prefix = {
  Attr.gu: ['ごつごつ', 'どすん', 'ぐるぐる', 'がっちり', 'ドカン'],
  Attr.choki: ['シャキーン', 'ちょきちょき', 'ビュン', 'とげとげ', 'スパッと'],
  Attr.pa: ['ふわふわ', 'ぱあっと', 'きらきら', 'ひらひら', 'もくもく'],
  Attr.none: ['にこにこ', 'ぽかぽか', 'わくわく', 'のびのび', 'ぴかぴか'],
};
const Map<MoveKind, List<String>> _noun = {
  MoveKind.physical: ['パンチ', 'キック', 'タックル', 'ずつき'],
  MoveKind.special: ['ビーム', 'ボール', 'ウェーブ', 'スター'],
  MoveKind.heal: ['ヒール', 'おひるね', 'げんき'],
  MoveKind.buff: ['パワー', 'がんばる', 'きあい'],
  MoveKind.debuff: ['こちょこちょ', 'にらめっこ'],
  MoveKind.status: ['ねばねば', 'ビリビリ'],
  MoveKind.shield: ['バリア', 'まもり'],
};
const Map<Attr, List<String>> _attrColours = {
  Attr.gu: ['red', 'orange', 'black'],
  Attr.choki: ['yellow', 'cyan', 'purple'],
  Attr.pa: ['green', 'pink', 'blue', 'rainbow'],
  Attr.none: ['white', 'pink', 'yellow'],
};

T _pick<T>(Mulberry32 r, List<T> xs) => xs[r.nextInt(xs.length)];

String _name(Mulberry32 r, Attr a, MoveKind k) {
  final n = _pick(r, _noun[k]!);
  final p = _pick(r, _prefix[a]!);
  final s = '$p$n';
  return s.length <= 10 ? s : n;
}

/// Largest power (multiple of 5) that fits; null if even the minimum does not.
Move? _maxPower(V3Spec s, Move m, int budget) {
  for (var p = kMaxPower; p >= 40; p -= 5) {
    final c = m.copyWith(power: p);
    if (movePoints(s, c) <= budget) return c;
  }
  return null;
}

/// Generates the four slot moves (locked slots are generated too — they are
/// revealed at Lv10 / Lv50). [stream] 12 normally, 14 for the bloomer's
/// rebirth set. Each move aims at a cost in bars that grows with the
/// character's max bars `M` ([maxBars], default the genome's): slot 1: 1;
/// slot 2: coverage or status damage (M+1)/2, support up to
/// max(2, (M+1)/2);
/// slot 3: charged max(2, M−1) or multi-hit max(2, M−2); ひっさつ: M.
List<Move> generateOfflineMoves(
  V3Spec s,
  Genome g, {
  required int moveFactorPct,
  int stream = 12,
  Attr? attr,
  int? maxBars,
}) {
  final cap =
      maxBars ?? (stream == 14 ? g.maxBarsAt(s.rebirthLevel) : g.maxBarsAt(1));
  int target(int bars) => bars < cap ? bars : cap;
  int budgetFor(int bars) => barBudget(s, target(bars), moveFactorPct);
  final r = Mulberry32(deriveSeed(g.seed, stream));
  // The rebirth set (stream 14) is shaped by the reborn stats.
  final st = stream == 14 && g.rebirthBase != null ? g.rebirthBase! : g.base;
  final physical = st[Stat.str.index] >= st[Stat.intl.index];
  final own = attr ?? g.attr;
  final formula = _bestFormula(st, physical);
  final kindD = physical ? MoveKind.physical : MoveKind.special;
  String dmgTpl(bool multi) =>
      physical ? (multi ? 'combo' : 'strike') : (multi ? 'barrage' : 'blast');
  String vfxFor(MoveKind k) => switch (k) {
    MoveKind.physical => _pick(r, ['punch', 'slash', 'spiral', 'burst']),
    MoveKind.special => _pick(r, ['beam', 'orb', 'wave', 'stars', 'sparks']),
    MoveKind.heal => _pick(r, ['hearts', 'glow', 'bubbles']),
    MoveKind.shield => 'shield',
    _ => _pick(r, ['glow', 'stars', 'bubbles', 'leaves', 'rain']),
  };

  Move damage(
    int bars,
    Attr a, {
    bool multi = false,
    int cast = 0,
    int cd = 0,
    int acc = 100,
    SecondaryType sec = SecondaryType.none,
    int secChance = 0,
  }) {
    final base = Move(
      template: dmgTpl(multi),
      attr: a,
      name: _name(r, a, kindD),
      vfx: vfxFor(kindD),
      colour: _pick(r, _attrColours[a]!),
      atkFormula: formula,
      power: 40,
      hits: multi ? 2 + r.nextInt(2) : 1,
      accuracy: acc,
      castTicks: cast,
      cooldownTicks: cd,
      secondary: sec,
      secondaryChance: secChance,
      secondaryStat: physical ? Stat.def : Stat.res,
    );
    final m =
        _maxPower(s, base, budgetFor(bars)) ??
        base.copyWith(secondary: SecondaryType.none);
    return withBars(s, m, moveFactorPct);
  }

  // Slot 1: いつもの わざ (1 bar).
  final roll1 = r.nextInt(100);
  final m0 = roll1 < 30
      ? damage(1, own, acc: 90)
      : roll1 < 50
      ? damage(1, own, sec: SecondaryType.debuff, secChance: 20)
      : damage(1, own);

  // Slot 2: coverage or support.
  final cover = own.beatenBy!.beatenBy!; // beats what beats me
  final roll2 = r.nextInt(100);
  final Move m1;
  final half = (cap + 1) ~/ 2;
  if (roll2 < 35) {
    m1 = damage(half, cover, cd: 30);
  } else if (roll2 < 65) {
    m1 = damage(
      half,
      Attr.none,
      sec: r.nextInt(2) == 0 ? SecondaryType.poison : SecondaryType.paralyze,
      secChance: 30,
    );
  } else {
    m1 = withBars(
      s,
      _support(
        s,
        r,
        st,
        own,
        barBudget(s, half < 2 ? 2 : half, moveFactorPct),
        vfxFor,
      ),
      moveFactorPct,
    );
  }

  // Slot 3 (Lv10): strong move.
  final roll3 = r.nextInt(100);
  final m2 = roll3 < 50
      ? damage(cap > 2 ? cap - 1 : 2, roll3 < 25 ? own : cover, cast: 6, cd: 40)
      : damage(
          cap > 4 ? cap - 2 : 2,
          own.beats == m1.attr ? own : Attr.none,
          multi: true,
          cd: 30,
        );

  // Slot 4 (Lv50): ひっさつ, neutral, as many bars as the character holds.
  final m3 = damage(5, Attr.none, cast: 12, cd: 80);
  return [m0, m1, m2, m3];
}

Move _support(
  V3Spec s,
  Mulberry32 r,
  List<int> st,
  Attr own,
  int budget,
  String Function(MoveKind) vfxFor,
) {
  final w = [
    st[Stat.intl.index], // heal
    st[Stat.def.index] + st[Stat.vit.index], // barrier
    st[Stat.luk.index] * 2, // status
    st[Stat.str.index] + st[Stat.intl.index], // buff
  ];
  final total = w.fold<int>(0, (a, b) => a + b);
  var x = r.nextInt(total);
  var k = 0;
  while (x >= w[k]) {
    x -= w[k];
    k++;
  }
  final physical = st[Stat.str.index] >= st[Stat.intl.index];
  final Move m = switch (k) {
    0 => Move(
      template: 'heal',
      attr: Attr.none,
      healPct: 40,
      cooldownTicks: 100,
    ),
    1 => const Move(
      template: 'barrier',
      attr: Attr.none,
      shieldPct: 60,
      durationTicks: 40,
      cooldownTicks: 60,
    ),
    2 => Move(
      template: r.nextInt(2) == 0 ? 'poison' : 'paralyze',
      attr: own.beats!,
      chance: 100,
      accuracy: 90,
      cooldownTicks: 60,
    ),
    _ => Move(
      template: 'power_up',
      attr: Attr.none,
      stat: physical ? Stat.str : Stat.intl,
      stages: 2,
      durationTicks: 120,
      cooldownTicks: 120,
    ),
  };
  final fitted = fitToBudget(s, m, budget) ?? m;
  return fitted.copyWith(
    name: _name(r, fitted.attr, fitted.kind),
    vfx: vfxFor(fitted.kind),
    colour: _pick(r, _attrColours[fitted.attr]!),
  );
}

AtkFormula _bestFormula(List<int> st, bool physical) {
  AtkFormula? best;
  var bestV = -1;
  for (final f in AtkFormula.values) {
    if (f.physical != physical) continue;
    final v = st[f.a.index] * f.pa + st[f.b.index] * f.pb;
    if (v > bestV) {
      bestV = v;
      best = f;
    }
  }
  return best!;
}
