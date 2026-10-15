/**
 * Offline move generator (no cloud consent / rejected AI slot),
 * deterministic from the image hash. Bit-exact port of
 * app/lib/domain/battle_v3/offline_moves.dart (GAME_DESIGN_V2 §5.7).
 */
import type { Genome } from './genome';
import {
  ATK_FORMULAS,
  type AtkFormula,
  barBudget,
  fitToBudget,
  kindOf,
  makeMove,
  MAX_POWER,
  type Move,
  type MoveKind,
  movePoints,
  type SecondaryType,
  withBars,
} from './moves';
import { deriveSeed, Mulberry32 } from './rng';
import { type Attr, beatenBy, beats, idiv, Stat, type V3Spec } from './spec';

const PREFIX: Record<Attr, readonly string[]> = {
  gu: ['ごつごつ', 'どすん', 'ぐるぐる', 'がっちり', 'ドカン'],
  choki: ['シャキーン', 'ちょきちょき', 'ビュン', 'とげとげ', 'スパッと'],
  pa: ['ふわふわ', 'ぱあっと', 'きらきら', 'ひらひら', 'もくもく'],
  none: ['にこにこ', 'ぽかぽか', 'わくわく', 'のびのび', 'ぴかぴか'],
};
const NOUN: Record<MoveKind, readonly string[]> = {
  physical: ['パンチ', 'キック', 'タックル', 'ずつき'],
  special: ['ビーム', 'ボール', 'ウェーブ', 'スター'],
  heal: ['ヒール', 'おひるね', 'げんき'],
  buff: ['パワー', 'がんばる', 'きあい'],
  debuff: ['こちょこちょ', 'にらめっこ'],
  status: ['ねばねば', 'ビリビリ'],
  shield: ['バリア', 'まもり'],
};
const ATTR_COLOURS: Record<Attr, readonly string[]> = {
  gu: ['red', 'orange', 'black'],
  choki: ['yellow', 'cyan', 'purple'],
  pa: ['green', 'pink', 'blue', 'rainbow'],
  none: ['white', 'pink', 'yellow'],
};

const pick = <T>(r: Mulberry32, xs: readonly T[]): T => xs[r.nextInt(xs.length)]!;

function moveName(r: Mulberry32, a: Attr, k: MoveKind): string {
  const n = pick(r, NOUN[k]);
  const p = pick(r, PREFIX[a]);
  const s = `${p}${n}`;
  return s.length <= 10 ? s : n;
}

function maxPower(s: V3Spec, m: Move, budget: number): Move | null {
  for (let p = MAX_POWER; p >= 40; p -= 5) {
    const c = { ...m, power: p };
    if (movePoints(s, c) <= budget) return c;
  }
  return null;
}

function bestFormula(st: readonly number[], physical: boolean): AtkFormula {
  let best: AtkFormula | undefined;
  let bestV = -1;
  for (const f of ATK_FORMULAS) {
    if (f.physical !== physical) continue;
    const v = st[f.a]! * f.pa + st[f.b]! * f.pb;
    if (v > bestV) {
      bestV = v;
      best = f;
    }
  }
  return best!;
}

/**
 * The four slot moves; `stream` 12 normally, 14 for the rebirth set. Bars
 * per slot grow with the max bars M (default the genome's): 1; (M+1)/2
 * (support up to max(2, (M+1)/2)); charged max(2, M−1) or multi max(2, M−2);
 * ひっさつ M.
 */
export function generateOfflineMoves(
  s: V3Spec,
  g: Genome,
  opts: { moveFactorPct: number; stream?: number; attr?: Attr | null; maxBars?: number | null },
): Move[] {
  const stream = opts.stream ?? 12;
  const cap = opts.maxBars ?? (stream === 14 ? g.maxBarsAt(s.rebirthLevel) : g.maxBarsAt(1));
  const target = (bars: number) => (bars < cap ? bars : cap);
  const r = new Mulberry32(deriveSeed(g.seed, stream));
  const st = stream === 14 && g.rebirthBase !== null ? g.rebirthBase : g.base;
  const physical = st[Stat.str]! >= st[Stat.intl]!;
  const own: Attr = opts.attr ?? g.attr;
  const formula = bestFormula(st, physical);
  const kindD: MoveKind = physical ? 'physical' : 'special';
  const dmgTpl = (multi: boolean) => (physical ? (multi ? 'combo' : 'strike') : multi ? 'barrage' : 'blast');
  const vfxFor = (k: MoveKind): string => {
    switch (k) {
      case 'physical':
        return pick(r, ['punch', 'slash', 'spiral', 'burst']);
      case 'special':
        return pick(r, ['beam', 'orb', 'wave', 'stars', 'sparks']);
      case 'heal':
        return pick(r, ['hearts', 'glow', 'bubbles']);
      case 'shield':
        return 'shield';
      default:
        return pick(r, ['glow', 'stars', 'bubbles', 'leaves', 'rain']);
    }
  };
  const factor = opts.moveFactorPct;

  const damage = (
    bars: number,
    a: Attr,
    o: { multi?: boolean; cast?: number; cd?: number; acc?: number; sec?: SecondaryType; secChance?: number } = {},
  ): Move => {
    const multi = o.multi ?? false;
    // Draw order = Dart constructor argument order: name, vfx, colour, hits.
    const name = moveName(r, a, kindD);
    const vfx = vfxFor(kindD);
    const colour = pick(r, ATTR_COLOURS[a]);
    const hits = multi ? 2 + r.nextInt(2) : 1;
    const base = makeMove({
      template: dmgTpl(multi),
      attr: a,
      name,
      vfx,
      colour,
      atkFormula: formula,
      power: 40,
      hits,
      accuracy: o.acc ?? 100,
      castTicks: o.cast ?? 0,
      cooldownTicks: o.cd ?? 0,
      secondary: o.sec ?? 'none',
      secondaryChance: o.secChance ?? 0,
      secondaryStat: physical ? Stat.def : Stat.res,
    });
    const m = maxPower(s, base, barBudget(s, target(bars), factor)) ?? { ...base, secondary: 'none' as const };
    return withBars(s, m, factor);
  };

  const roll1 = r.nextInt(100);
  const m0 =
    roll1 < 30
      ? damage(1, own, { acc: 90 })
      : roll1 < 50
        ? damage(1, own, { sec: 'debuff', secChance: 20 })
        : damage(1, own);

  const cover = beatenBy(beatenBy(own)!)!;
  const roll2 = r.nextInt(100);
  let m1: Move;
  const half = idiv(cap + 1, 2);
  if (roll2 < 35) {
    m1 = damage(half, cover, { cd: 30 });
  } else if (roll2 < 65) {
    const sec: SecondaryType = r.nextInt(2) === 0 ? 'poison' : 'paralyze';
    m1 = damage(half, 'none', { sec, secChance: 30 });
  } else {
    m1 = withBars(s, support(s, r, st, own, barBudget(s, half < 2 ? 2 : half, factor), vfxFor), factor);
  }

  const roll3 = r.nextInt(100);
  const m2 =
    roll3 < 50
      ? damage(cap > 2 ? cap - 1 : 2, roll3 < 25 ? own : cover, { cast: 6, cd: 40 })
      : damage(cap > 4 ? cap - 2 : 2, beats(own) === m1.attr ? own : 'none', { multi: true, cd: 30 });

  const m3 = damage(5, 'none', { cast: 12, cd: 80 });
  return [m0, m1, m2, m3];
}

function support(
  s: V3Spec,
  r: Mulberry32,
  st: readonly number[],
  own: Attr,
  budget: number,
  vfxFor: (k: MoveKind) => string,
): Move {
  const w = [st[Stat.intl]!, st[Stat.def]! + st[Stat.vit]!, st[Stat.luk]! * 2, st[Stat.str]! + st[Stat.intl]!];
  const total = w.reduce((a, b) => a + b, 0);
  let x = r.nextInt(total);
  let k = 0;
  while (x >= w[k]!) {
    x -= w[k]!;
    k++;
  }
  const physical = st[Stat.str]! >= st[Stat.intl]!;
  let m: Move;
  switch (k) {
    case 0:
      m = makeMove({ template: 'heal', attr: 'none', healPct: 40, cooldownTicks: 100 });
      break;
    case 1:
      m = makeMove({ template: 'barrier', attr: 'none', shieldPct: 60, durationTicks: 40, cooldownTicks: 60 });
      break;
    case 2:
      m = makeMove({
        template: r.nextInt(2) === 0 ? 'poison' : 'paralyze',
        attr: beats(own)!,
        chance: 100,
        accuracy: 90,
        cooldownTicks: 60,
      });
      break;
    default:
      m = makeMove({
        template: 'power_up',
        attr: 'none',
        stat: physical ? Stat.str : Stat.intl,
        stages: 2,
        durationTicks: 120,
        cooldownTicks: 120,
      });
  }
  const fitted = fitToBudget(s, m, budget) ?? m;
  const name = moveName(r, fitted.attr, kindOf(fitted));
  const vfx = vfxFor(kindOf(fitted));
  const colour = pick(r, ATTR_COLOURS[fitted.attr]);
  return { ...fitted, name, vfx, colour };
}
