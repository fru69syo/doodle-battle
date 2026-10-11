/**
 * Real-time ATB battle at a fixed 10 Hz tick, integer maths only.
 * Bit-exact port of app/lib/domain/battle_v3/engine.dart
 * (docs/GAME_DESIGN_V2.md §6, docs/BATTLE_V3.md).
 *
 * The server (Cloud Run realtime) runs one `Battle` per match: queue each
 * client's `{slot}` with `queueInput`, call `step()` every 100 ms with AI
 * controllers for ghosts / disconnected players, broadcast the returned
 * events and periodically `stateHash()`.
 */
import { autoPickNormal } from './ai';
import { maxHpOf } from './genome';
import {
  DEBUFF_SECONDARY_TICKS,
  kindOf,
  type Move,
  moveFromJson,
  moveToJson,
  type StatusKind,
  statusOf,
} from './moves';
import { deriveSeed, fnv1a32, Mulberry32 } from './rng';
import { type Attr, beats, idiv, Stat, type StatIndex, STATS, typePct, type V3Spec } from './spec';

export interface FighterSetup {
  /** Ten stats in Stat order (already at the battle level). */
  stats: number[];
  attr: Attr;
  /** Unlocked moves only (1..4). */
  moves: Move[];
  label?: string;
}

export function setupToJson(f: FighterSetup): Record<string, unknown> {
  return { stats: f.stats, attribute: f.attr, moves: f.moves.map(moveToJson) };
}

export function setupFromJson(j: Record<string, unknown>): FighterSetup {
  return {
    stats: [...(j.stats as number[])],
    attr: j.attribute as Attr,
    moves: (j.moves as Record<string, unknown>[]).map(moveFromJson),
    label: (j.label as string | undefined) ?? '',
  };
}

export type Phase = 'charging' | 'ready' | 'casting';
const PHASES: readonly Phase[] = ['charging', 'ready', 'casting'];

export class Fighter {
  readonly stats: number[];
  readonly maxHp: number;
  hp: number;
  /** centi-SP (0..10000). */
  sp: number;
  gauge = 0;
  phase: Phase = 'charging';
  readyTicks = 0;
  castSlot = -1;
  castLeft = 0;
  /** Pre-selected / submitted move (さきどり). */
  queued: number | null = null;
  readonly cooldowns: number[];
  readonly stages: number[] = new Array<number>(10).fill(0);
  readonly stageTicks: number[] = new Array<number>(10).fill(0);
  poisonTicks = 0;
  paralyzeTicks = 0;
  shieldPct = 0;
  shieldTicks = 0;
  healUses = 0;
  actions = 0;
  autoPicks = 0;

  constructor(
    s: V3Spec,
    readonly setup: FighterSetup,
  ) {
    this.stats = [...setup.stats];
    this.maxHp = maxHpOf(s, setup.stats);
    this.hp = this.maxHp;
    this.sp = s.spStartCenti;
    this.cooldowns = new Array<number>(setup.moves.length).fill(0);
  }

  get moves(): Move[] {
    return this.setup.moves;
  }

  get attr(): Attr {
    return this.setup.attr;
  }

  usable(slot: number): boolean {
    return (
      Number.isInteger(slot) &&
      slot >= 0 &&
      slot < this.moves.length &&
      this.cooldowns[slot] === 0 &&
      this.sp >= this.moves[slot]!.spCost * 100
    );
  }

  decisionTicksLeft(s: V3Spec): number {
    return this.phase === 'ready' ? s.decisionTicks - this.readyTicks : s.decisionTicks;
  }

  snapshot(): Record<string, unknown> {
    return {
      hp: this.hp,
      sp: this.sp,
      gauge: this.gauge,
      phase: this.phase,
      readyTicks: this.readyTicks,
      castSlot: this.castSlot,
      castLeft: this.castLeft,
      queued: this.queued,
      cooldowns: [...this.cooldowns],
      stages: [...this.stages],
      stageTicks: [...this.stageTicks],
      poisonTicks: this.poisonTicks,
      paralyzeTicks: this.paralyzeTicks,
      shieldPct: this.shieldPct,
      shieldTicks: this.shieldTicks,
      healUses: this.healUses,
      actions: this.actions,
      autoPicks: this.autoPicks,
    };
  }

  restore(j: Record<string, unknown>): void {
    const n = (k: string) => j[k] as number;
    const set = (dst: number[], k: string) => (j[k] as number[]).forEach((v, i) => (dst[i] = v));
    this.hp = n('hp');
    this.sp = n('sp');
    this.gauge = n('gauge');
    this.phase = j.phase as Phase;
    this.readyTicks = n('readyTicks');
    this.castSlot = n('castSlot');
    this.castLeft = n('castLeft');
    this.queued = (j.queued as number | null | undefined) ?? null;
    set(this.cooldowns, 'cooldowns');
    set(this.stages, 'stages');
    set(this.stageTicks, 'stageTicks');
    this.poisonTicks = n('poisonTicks');
    this.paralyzeTicks = n('paralyzeTicks');
    this.shieldPct = n('shieldPct');
    this.shieldTicks = n('shieldTicks');
    this.healUses = n('healUses');
    this.actions = n('actions');
    this.autoPicks = n('autoPicks');
  }
}

export type EventValue = number | string;

/** Renderer event (types and keys: see engine.dart `BattleEvent`). */
export interface BattleEvent {
  tick: number;
  type: string;
  data: Record<string, EventValue>;
}

/** Canonical line `"<tick> <type> k=v,..."`, keys sorted. */
export function eventLine(e: BattleEvent): string {
  const keys = Object.keys(e.data).sort();
  return `${e.tick} ${e.type} ${keys.map((k) => `${k}=${e.data[k]}`).join(',')}`;
}

export function eventsHash(events: readonly BattleEvent[]): number {
  return fnv1a32(events.map(eventLine).join('\n'));
}

/** Returns a slot, or null to keep waiting (timeout auto-picks). */
export type Controller = (battle: Battle, side: number) => number | null;
export type AutoPicker = (battle: Battle, side: number, rng: Mulberry32) => number;

/** Raw triangle multiplier (%) of a move attribute against a defender. */
export function typeChart(move: Attr, defender: Attr, s: V3Spec): number {
  if (move === 'none' || defender === 'none') return 100;
  if (beats(move) === defender) return s.typeAdvantagePct;
  if (beats(defender) === move) return s.typeDisadvantagePct;
  return 100;
}

export class Battle {
  readonly fighters: [Fighter, Fighter];
  rng: Mulberry32;
  readonly aiRng: [Mulberry32, Mulberry32];
  readonly events: BattleEvent[] = [];
  private tickEvents: BattleEvent[] = [];
  tick = 0;
  winner: number | null = null;
  endReason: string | null = null;
  readonly autoPick: AutoPicker;
  readonly recordEvents: boolean;

  constructor(
    readonly spec: V3Spec,
    a: FighterSetup,
    b: FighterSetup,
    readonly seed: number,
    opts: { autoPick?: AutoPicker; recordEvents?: boolean } = {},
  ) {
    this.fighters = [new Fighter(spec, a), new Fighter(spec, b)];
    for (const f of this.fighters) {
      if (f.moves.length < 1 || f.moves.length > 4) throw new RangeError('a fighter needs 1..4 moves');
    }
    this.rng = new Mulberry32(deriveSeed(seed, 0));
    this.aiRng = [new Mulberry32(deriveSeed(seed, 1)), new Mulberry32(deriveSeed(seed, 2))];
    this.autoPick = opts.autoPick ?? autoPickNormal;
    this.recordEvents = opts.recordEvents ?? true;
  }

  get finished(): boolean {
    return this.winner !== null;
  }

  /** Submits a move for `side` (used when ready; replaces an older one). */
  queueInput(side: number, slot: number): void {
    if (!this.finished) this.fighters[side]!.queued = slot;
  }

  clearInput(side: number): void {
    this.fighters[side]!.queued = null;
  }

  private ev(type: string, data: Record<string, EventValue>): void {
    const e: BattleEvent = { tick: this.tick, type, data };
    this.tickEvents.push(e);
    if (this.recordEvents) this.events.push(e);
  }

  /** Effective stat with buff stages. */
  eff(side: number, st: StatIndex): number {
    const f = this.fighters[side]!;
    const v = f.stats[st]!;
    const n = f.stages[st]!;
    const d = this.spec.stageDen;
    const r = n >= 0 ? idiv(v * (d + n), d) : idiv(v * d, d - n);
    return r < 1 ? 1 : r;
  }

  /** base·(100(x+y) + w(x−y)) / (100(x+y)). */
  rel(base: number, x: number, y: number, weightPct: number): number {
    const sum = x + y;
    if (sum <= 0) return base;
    return idiv(base * (100 * sum + weightPct * (x - y)), 100 * sum);
  }

  fillRate(side: number): number {
    let r = this.rel(this.spec.gaugeFillPerTick, this.eff(side, Stat.agi), this.eff(1 - side, Stat.agi), this.spec.agiWeightPct);
    if (this.fighters[side]!.paralyzeTicks > 0) r = idiv(r * this.spec.paralyzeFillPct, 100);
    return r;
  }

  heatPct(): number {
    const s = this.spec;
    return this.tick <= s.heatUpStartTick ? 100 : 100 + s.heatUpPctPerSecond * idiv(this.tick - s.heatUpStartTick, s.tickHz);
  }

  run(ca: Controller | null = null, cb: Controller | null = null): number {
    while (!this.finished) this.step(ca, cb);
    return this.winner!;
  }

  /** One tick (normative order, see engine.dart). Returns its events. */
  step(ca: Controller | null = null, cb: Controller | null = null): BattleEvent[] {
    this.tickEvents = [];
    if (this.finished) return [];
    const s = this.spec;
    this.tick++;
    if (this.tick === s.heatUpStartTick + 1) this.ev('heatUp', {});
    // 1. timers
    for (let i = 0; i < 2 && !this.finished; i++) {
      const f = this.fighters[i]!;
      for (let k = 0; k < f.cooldowns.length; k++) if (f.cooldowns[k]! > 0) f.cooldowns[k]!--;
      for (let k = 0; k < 10; k++) {
        if (f.stageTicks[k]! > 0 && --f.stageTicks[k]! === 0) {
          f.stages[k] = 0;
          this.ev('expire', { side: i, kind: STATS[k]! });
        }
      }
      if (f.shieldTicks > 0 && --f.shieldTicks === 0) {
        f.shieldPct = 0;
        this.ev('expire', { side: i, kind: 'shield' });
      }
      if (f.paralyzeTicks > 0 && --f.paralyzeTicks === 0) this.ev('expire', { side: i, kind: 'paralyze' });
      if (f.poisonTicks > 0) {
        f.poisonTicks--;
        if (f.poisonTicks % s.tickHz === 0) {
          const d = idiv(f.maxHp * s.poisonMillePerSecond, 1000);
          this.hurt(i, d < 1 ? 1 : d, 'dot', {});
        }
        if (f.poisonTicks === 0 && !this.finished) this.ev('expire', { side: i, kind: 'poison' });
      }
    }
    if (this.finished) return [...this.tickEvents];
    // 2. SP regen
    for (let i = 0; i < 2; i++) {
      const f = this.fighters[i]!;
      const r = this.rel(s.spRegenCentiPerTick, f.stats[Stat.sp]!, this.fighters[1 - i]!.stats[Stat.sp]!, s.spWeightPct);
      const v = f.sp + r;
      f.sp = v > s.spMaxCenti ? s.spMaxCenti : v;
    }
    // 3. gauges
    for (let i = 0; i < 2; i++) {
      const f = this.fighters[i]!;
      if (f.phase !== 'charging') continue;
      f.gauge += this.fillRate(i);
      if (f.gauge >= s.gaugeMax) {
        f.gauge = s.gaugeMax;
        f.phase = 'ready';
        f.readyTicks = 0;
        this.ev('ready', { side: i });
      }
    }
    // 4. decisions
    const due: number[] = [];
    for (let i = 0; i < 2; i++) {
      const f = this.fighters[i]!;
      if (f.phase === 'casting') {
        if (--f.castLeft <= 0) due.push(i);
        continue;
      }
      if (f.phase !== 'ready') continue;
      let slot: number | null = null;
      const q = f.queued;
      if (q !== null) {
        f.queued = null;
        if (f.usable(q)) slot = q;
        else this.ev('inputIgnored', { side: i, slot: q });
      }
      if (slot === null) {
        const c = i === 0 ? ca : cb;
        const x = c ? c(this, i) : null;
        if (x !== null && f.usable(x)) slot = x;
      }
      let auto = 0;
      if (slot === null) {
        f.readyTicks++;
        if (f.readyTicks < s.decisionTicks) continue;
        slot = this.autoPick(this, i, this.aiRng[i]!);
        f.autoPicks++;
        auto = 1;
      }
      const m = f.moves[slot]!;
      f.sp -= m.spCost * 100;
      f.castSlot = slot;
      f.readyTicks = 0; // only meaningful while ready
      f.actions++;
      this.ev('select', { side: i, slot, cast: m.castTicks, auto });
      if (m.castTicks > 0) {
        f.phase = 'casting';
        f.castLeft = m.castTicks;
      } else {
        due.push(i);
      }
    }
    // 5. resolutions
    if (due.length === 2 && this.rng.nextInt(2) === 1) due.reverse();
    for (const i of due) {
      if (this.finished) break;
      this.resolve(i);
    }
    // 6. hard cap
    if (!this.finished && this.tick >= s.hardCapTick) {
      const [fa, fb] = this.fighters;
      const l = fa.hp * fb.maxHp;
      const r = fb.hp * fa.maxHp;
      this.end(l > r ? 0 : r > l ? 1 : this.rng.nextInt(2), 'timeUp');
    }
    return [...this.tickEvents];
  }

  private end(w: number, reason: string): void {
    this.winner = w;
    this.endReason = reason;
    for (const f of this.fighters) f.queued = null;
    this.ev('end', { winner: w, reason });
  }

  private hurt(side: number, amount: number, type: string, extra: Record<string, EventValue>): void {
    const f = this.fighters[side]!;
    f.hp = f.hp - amount < 0 ? 0 : f.hp - amount;
    this.ev(type, { ...extra, target: side, amount, hp: f.hp });
    if (f.hp === 0 && !this.finished) {
      this.ev('faint', { side });
      this.end(1 - side, 'ko');
    }
  }

  private resolve(i: number): void {
    const s = this.spec;
    const f = this.fighters[i]!;
    const slot = f.castSlot;
    const m = f.moves[slot]!;
    f.phase = 'charging';
    f.gauge = 0;
    f.castSlot = -1;
    f.cooldowns[slot] = m.cooldownTicks;
    this.ev('moveStart', { side: i, slot, template: m.template, attr: m.attr });
    const t = 1 - i;
    switch (kindOf(m)) {
      case 'physical':
      case 'special':
        this.damageMove(i, t, m);
        break;
      case 'heal': {
        const steps = s.healDecaySteps;
        const decay = steps[f.healUses < steps.length ? f.healUses : steps.length - 1]!;
        f.healUses++;
        const intl = this.eff(i, Stat.intl);
        const str = this.eff(i, Stat.str);
        const scale = 75 + idiv(50 * intl, intl + str);
        const heat = this.heatPct();
        const fade = heat >= 200 ? 0 : 200 - heat;
        let amt = idiv(idiv(f.maxHp * m.healPct * scale * decay, 1000000) * fade, 100);
        if (f.hp + amt > f.maxHp) amt = f.maxHp - f.hp;
        f.hp += amt;
        this.ev('heal', { side: i, amount: amt, hp: f.hp, source: 'move' });
        break;
      }
      case 'buff':
        this.stage(i, m.stat, m.stages, m.durationTicks);
        break;
      case 'debuff':
        if (this.hits(i, t, m.accuracy)) this.stage(t, m.stat, -m.stages, m.durationTicks);
        else this.ev('miss', { side: i, target: t, n: 0 });
        break;
      case 'status':
        if (this.hits(i, t, m.accuracy)) this.tryStatus(i, t, statusOf(m)!, m.chance);
        else this.ev('miss', { side: i, target: t, n: 0 });
        break;
      case 'shield':
        f.shieldPct = m.shieldPct;
        f.shieldTicks = m.durationTicks;
        this.ev('shield', { side: i, pct: m.shieldPct, ticks: m.durationTicks });
        break;
    }
  }

  private stage(side: number, st: StatIndex, delta: number, ticks: number): void {
    const f = this.fighters[side]!;
    const max = this.spec.maxStage;
    let n = f.stages[st]! + delta;
    n = n < -max ? -max : n > max ? max : n;
    f.stages[st] = n;
    f.stageTicks[st] = ticks;
    this.ev('stage', { side, stat: STATS[st]!, stage: n, ticks });
  }

  /** Hit chance (%), clamped to [hitMinPct, 100]. */
  hitChance(a: number, d: number, acc: number): number {
    const dex = this.eff(a, Stat.dex);
    const eva = idiv(this.eff(d, Stat.agi) + this.eff(d, Stat.luk), 2);
    const sum = dex + eva;
    let hit = idiv(acc * sum + this.spec.hitSkewPct * (dex - eva), sum);
    if (hit < this.spec.hitMinPct) hit = this.spec.hitMinPct;
    if (hit > 100) hit = 100;
    return hit;
  }

  private hits(a: number, d: number, acc: number): boolean {
    return this.rng.nextInt(100) < this.hitChance(a, d, acc);
  }

  /** Crit chance (‰). */
  critMille(a: number, d: number, critBonus: number): number {
    const la = this.eff(a, Stat.luk);
    const ld = this.eff(d, Stat.luk);
    const critNum = this.spec.critBaseMille * (la + ld) + this.spec.critLukMille * (la - ld);
    return (critNum <= 0 ? 0 : idiv(critNum, la + ld)) + critBonus * 10;
  }

  private tryStatus(a: number, d: number, k: StatusKind, chance: number): void {
    const s = this.spec;
    const p = this.rel(chance, this.eff(a, Stat.luk), this.eff(d, Stat.vit), s.statusLukSkewPct);
    if (this.rng.nextInt(100) >= p) {
      this.ev('statusFail', { target: d, status: k });
      return;
    }
    const f = this.fighters[d]!;
    const ticks = k === 'poison' ? s.poisonTicks : s.paralyzeTicks;
    if (k === 'poison') f.poisonTicks = ticks;
    else f.paralyzeTicks = ticks;
    this.ev('status', { target: d, status: k, ticks });
  }

  typePctAgainst(m: Move, d: number): number {
    return typePct(this.spec, typeChart(m.attr, this.fighters[d]!.attr, this.spec));
  }

  /** Damage of one hit before RNG, crit, shield and heat. */
  baseHitDamage(a: number, d: number, m: Move): number {
    const fa = m.atkFormula;
    let atk = idiv(this.eff(a, fa.a) * fa.pa + this.eff(a, fa.b) * fa.pb, 100);
    if (atk < 1) atk = 1;
    const def = this.eff(d, kindOf(m) === 'physical' ? Stat.def : Stat.res);
    const perHit = idiv(m.power, m.hits);
    const raw = idiv(idiv(perHit * 2 * atk * atk, atk + def), 100);
    return idiv(raw * this.spec.damageScalePct * this.typePctAgainst(m, d), 10000);
  }

  private damageMove(a: number, d: number, m: Move): void {
    const s = this.spec;
    const pct = this.typePctAgainst(m, d);
    if (pct !== 100) this.ev('effective', { side: a, target: d, pct });
    let landed = 0;
    let total = 0;
    const tf = this.fighters[d]!;
    for (let h = 0; h < m.hits && !this.finished; h++) {
      const hit = this.hits(a, d, m.accuracy);
      const crit = this.rng.nextInt(1000) < this.critMille(a, d, m.critBonus);
      const variance = s.varianceMinPct + this.rng.nextInt(s.varianceSpan);
      if (!hit) {
        this.ev('miss', { side: a, target: d, n: h });
        continue;
      }
      let dmg = this.baseHitDamage(a, d, m);
      if (crit) dmg = idiv(dmg * s.critMultiplierPct, 100);
      dmg = idiv(dmg * variance, 100);
      if (tf.shieldPct > 0) dmg = idiv(dmg * (100 - tf.shieldPct), 100);
      dmg = idiv(dmg * this.heatPct(), 100);
      if (dmg < 1) dmg = 1;
      landed++;
      total += dmg;
      this.hurt(d, dmg, 'hit', { side: a, n: h, crit: crit ? 1 : 0, pct });
    }
    if (landed === 0 || this.finished) return;
    switch (m.secondary) {
      case 'poison':
        this.tryStatus(a, d, 'poison', m.secondaryChance);
        break;
      case 'paralyze':
        this.tryStatus(a, d, 'paralyze', m.secondaryChance);
        break;
      case 'debuff':
        if (this.rng.nextInt(100) < m.secondaryChance) this.stage(d, m.secondaryStat, -1, DEBUFF_SECONDARY_TICKS);
        break;
      case 'drain': {
        const f = this.fighters[a]!;
        let h = idiv(total * m.drainPct, 100);
        if (f.hp + h > f.maxHp) h = f.maxHp - f.hp;
        f.hp += h;
        this.ev('heal', { side: a, amount: h, hp: f.hp, source: 'drain' });
        break;
      }
      default:
        break;
    }
  }

  snapshot(): Record<string, unknown> {
    return {
      tick: this.tick,
      rng: this.rng.state,
      aiRng: [this.aiRng[0].state, this.aiRng[1].state],
      winner: this.winner,
      endReason: this.endReason,
      fighters: this.fighters.map((f) => f.snapshot()),
    };
  }

  restore(j: Record<string, unknown>): void {
    this.tick = j.tick as number;
    this.rng = new Mulberry32(j.rng as number);
    const ai = j.aiRng as number[];
    this.aiRng[0] = new Mulberry32(ai[0]!);
    this.aiRng[1] = new Mulberry32(ai[1]!);
    this.winner = (j.winner as number | null | undefined) ?? null;
    this.endReason = (j.endReason as string | null | undefined) ?? null;
    const fs = j.fighters as Record<string, unknown>[];
    this.fighters[0].restore(fs[0]!);
    this.fighters[1].restore(fs[1]!);
  }

  /** FNV-1a of the canonical state (periodic desync check). */
  stateHash(): number {
    const parts: string[] = [`${this.tick}`, `${this.rng.state}`];
    for (const f of this.fighters) {
      parts.push(
        [
          f.hp,
          f.sp,
          f.gauge,
          PHASES.indexOf(f.phase),
          f.readyTicks,
          f.castSlot,
          f.castLeft,
          ...f.cooldowns,
          ...f.stages,
          ...f.stageTicks,
          f.poisonTicks,
          f.paralyzeTicks,
          f.shieldPct,
          f.shieldTicks,
          f.healUses,
        ].join(','),
      );
    }
    return fnv1a32(parts.join('|'));
  }
}

