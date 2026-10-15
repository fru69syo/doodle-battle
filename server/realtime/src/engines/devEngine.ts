/**
 * DEV STAND-IN ENGINE — not the game rules.
 *
 * A small deterministic engine that follows the *shape* of GAME_DESIGN_V2 §6 (10 Hz tick,
 * stackable gauge bars of 10000 filled by the AGI ratio up to max bars, moves that cost bars,
 * casts, cooldowns, heat-up, 3 minute cap)
 * so the server, the protocol and the client can be developed before Engine v3 lands. Damage,
 * AI and Lv50 sync are simplified. Production must run Engine v3 (`BATTLE_ENGINE=v3`); see
 * docs/REALTIME_PROTOCOL.md §9.
 */
import type {
  AiTier,
  BattleEngine,
  BattleEvent,
  BattleSim,
  FighterSetup,
  FighterSource,
  MovePublic,
  Side,
  SideView,
  StepResult,
} from "../engine";
import { Mulberry32, deriveSeed, fnv1a32 } from "./rng";

const STATS = ["HP", "SP", "STR", "VIT", "DEF", "INT", "RES", "DEX", "AGI", "LUK"] as const;
type Stat = (typeof STATS)[number];

interface DevMove extends MovePublic {
  kind: "physical" | "special" | "heal";
  power: number;
  castTicks: number;
  cooldownTicks: number;
}

interface DevFighter {
  stats: Record<Stat, number>;
  moves: DevMove[];
  maxBars: number;
}

const TICK_HZ = 10;
const GAUGE_MAX = 10_000;
const HARD_CAP = 1800;
const HEAT_START = 600;
const BEATS: Record<string, string> = { gu: "choki", choki: "pa", pa: "gu" };

function int(v: unknown, def: number, min = 0, max = 100_000): number {
  return typeof v === "number" && Number.isFinite(v) ? Math.min(max, Math.max(min, Math.trunc(v))) : def;
}

function rel(base: number, x: number, y: number, w: number): number {
  const sum = x + y;
  if (sum <= 0) return base;
  return Math.floor((base * (100 * sum + w * (x - y))) / (100 * sum));
}

/** Moves unlocked at a real level (GAME_DESIGN_V2 §5: 2 at Lv1, 3rd at Lv10, 4th at Lv50). */
export function unlockedMoveCount(level: number): number {
  return level >= 50 ? 4 : level >= 10 ? 3 : 2;
}

function parseMoves(raw: unknown, count: number, maxBars: number): DevMove[] {
  const list = Array.isArray(raw) ? raw : [];
  const moves: DevMove[] = [];
  for (let i = 0; i < Math.min(count, list.length); i++) {
    const m = (list[i] ?? {}) as Record<string, unknown>;
    const kind = m.kind === "special" || m.kind === "heal" ? m.kind : "physical";
    moves.push({
      slot: i,
      name: typeof m.name === "string" ? m.name.slice(0, 20) : `わざ${i + 1}`,
      templateId: typeof m.templateId === "string" ? m.templateId : "strike",
      attr: typeof m.attr === "string" ? m.attr : "none",
      bars: i === 0 ? 1 : int(m.bars, 1, 1, maxBars),
      kind,
      power: int(m.power, 80, 1, 300),
      castTicks: int(m.castTicks, 0, 0, 20),
      cooldownTicks: int(m.cooldownTicks, 0, 0, 150),
    });
  }
  if (moves.length === 0) {
    moves.push({ slot: 0, name: "たいあたり", templateId: "strike", attr: "none", bars: 1, kind: "physical", power: 60, castTicks: 0, cooldownTicks: 0 });
  }
  return moves;
}

export class DevEngine implements BattleEngine {
  readonly engineId = "dev-0";
  readonly tickHz = TICK_HZ;
  readonly hardCapTick = HARD_CAP;

  ratedFighter(source: FighterSource, syncLevel: number): FighterSetup {
    const d = source.data;
    const raw = (d.statsLv1 ?? {}) as Record<string, unknown>;
    const stats = {} as Record<Stat, number>;
    // Simplified sync: +4 % of the Lv1 value per level (GAME_DESIGN_V2 §4.1 averages 4 %).
    for (const s of STATS) stats[s] = Math.floor((int(raw[s], 40, 1, 10_000) * (100 + 4 * (syncLevel - 1))) / 100);
    // Max bars from the Lv1 SP (SP / 10, clamped to 2..5), as in the real engine.
    const maxBars = Math.min(5, Math.max(2, Math.floor(int(raw.SP, 40, 1, 10_000) / 10)));
    const moves = parseMoves(d.moves, unlockedMoveCount(source.level), maxBars);
    const attr = d.attr === "gu" || d.attr === "choki" || d.attr === "pa" ? d.attr : "gu";
    const fighter: DevFighter = { stats, moves, maxBars };
    const pub: MovePublic[] = moves.map((m) => ({ slot: m.slot, name: m.name, templateId: m.templateId, attr: m.attr, bars: m.bars }));
    return { attr, moves: pub, maxHp: maxHpOf(stats), maxBars, engineData: fighter };
  }

  createBattle(a: FighterSetup, b: FighterSetup, opts: { seed: number }): BattleSim {
    return new DevBattle(a, b, opts.seed >>> 0);
  }
}

function other(s: Side): Side {
  return s === 0 ? 1 : 0;
}

function maxHpOf(s: Record<Stat, number>): number {
  let sum = 0;
  for (const k of STATS) sum += s[k];
  return 3 * s.HP + Math.floor((5 * sum) / STATS.length);
}

interface State {
  hp: number;
  maxHp: number;
  gauge: number;
  castSlot: number;
  castLeft: number;
  cooldowns: number[];
  plan: number | null;
}

class DevBattle implements BattleSim {
  tick = 0;
  winner: Side | null = null;
  endReason: "ko" | "timeout" | null = null;
  private readonly f: [DevFighter, DevFighter];
  private readonly attr: [string, string];
  private readonly st: [State, State];
  private readonly rng: Mulberry32;
  private readonly aiRng: [Mulberry32, Mulberry32];

  constructor(a: FighterSetup, b: FighterSetup, seed: number) {
    this.f = [a.engineData as DevFighter, b.engineData as DevFighter];
    this.attr = [a.attr, b.attr];
    const mk = (x: DevFighter): State => {
      const maxHp = maxHpOf(x.stats);
      return { hp: maxHp, maxHp, gauge: 0, castSlot: -1, castLeft: 0, cooldowns: x.moves.map(() => 0), plan: null };
    };
    this.st = [mk(this.f[0]), mk(this.f[1])];
    this.rng = new Mulberry32(deriveSeed(seed, 0));
    this.aiRng = [new Mulberry32(deriveSeed(seed, 1)), new Mulberry32(deriveSeed(seed, 2))];
  }

  private isOver(): boolean {
    return this.winner !== null;
  }

  get finished(): boolean {
    return this.winner !== null;
  }

  canQueue(side: Side, slot: number): boolean {
    const m = this.f[side].moves[slot];
    return m !== undefined && m.bars <= this.f[side].maxBars;
  }

  canUse(side: Side, slot: number): boolean {
    const m = this.f[side].moves[slot];
    const s = this.st[side];
    return m !== undefined && s.castLeft === 0 && s.cooldowns[slot] === 0 && s.gauge >= m.bars * GAUGE_MAX;
  }

  view(side: Side): SideView {
    const s = this.st[side];
    const maxBars = this.f[side].maxBars;
    return { hp: s.hp, maxHp: s.maxHp, gauge: s.gauge, bars: Math.floor(s.gauge / GAUGE_MAX), maxBars, casting: s.castLeft > 0 };
  }

  stateHash(): string {
    return fnv1a32(JSON.stringify([this.tick, this.st.map((x) => ({ ...x, plan: null }))])).toString(16).padStart(8, "0");
  }

  private eligible(side: Side): DevMove[] {
    return this.f[side].moves.filter((m) => this.st[side].cooldowns[m.slot] === 0 && m.bars <= this.f[side].maxBars);
  }

  /** The stand-in ignores `_thinkTicks` (no thinking time). */
  aiInput(side: Side, tier: AiTier, _thinkTicks: number): number | null {
    const me = this.st[side];
    if (me.castLeft > 0 || me.gauge < GAUGE_MAX) return null;
    if (me.plan === null) {
      const options = this.eligible(side);
      const rnd = this.aiRng[side];
      const randomPct = tier === "weak" ? 40 : tier === "normal" ? 20 : 0;
      if (rnd.nextInt(100) < randomPct) {
        me.plan = options[rnd.nextInt(options.length)]?.slot ?? 0;
      } else {
        let best = options[0];
        let bestScore = -Infinity;
        for (const m of options) {
          const value = m.kind === "heal" ? (me.hp * 2 < me.maxHp ? m.power * 1.2 : 0) : m.power;
          const score = value / m.bars - m.castTicks;
          if (score > bestScore) {
            bestScore = score;
            best = m;
          }
        }
        me.plan = best?.slot ?? 0;
      }
    }
    return this.canUse(side, me.plan) ? me.plan : null;
  }

  omakaseInput(side: Side): number | null {
    const me = this.st[side];
    if (me.castLeft > 0) return null;
    if (me.plan === null) {
      const options = this.eligible(side);
      me.plan = options[this.aiRng[side].nextInt(options.length)]?.slot ?? 0;
    }
    return this.canUse(side, me.plan) ? me.plan : null;
  }

  clearPlan(side: Side): void {
    this.st[side].plan = null;
  }

  step(inputs: readonly [number | null, number | null]): StepResult {
    const events: BattleEvent[] = [];
    const acted: [boolean, boolean] = [false, false];
    if (this.winner !== null) return { events, acted };
    this.tick++;
    const t = this.tick;
    const sides: Side[] = [0, 1];
    // 1. timers
    for (const i of sides) {
      const cd = this.st[i].cooldowns;
      for (let k = 0; k < cd.length; k++) if ((cd[k] ?? 0) > 0) cd[k] = (cd[k] ?? 0) - 1;
    }
    // 2. gauges (stackable bars; not while casting, up to max bars)
    for (const i of sides) {
      const me = this.st[i];
      const cap = this.f[i].maxBars * GAUGE_MAX;
      if (me.castLeft > 0 || me.gauge >= cap) continue;
      const before = Math.floor(me.gauge / GAUGE_MAX);
      me.gauge = Math.min(cap, me.gauge + rel(280, this.f[i].stats.AGI, this.f[other(i)].stats.AGI, 30));
      const after = Math.floor(me.gauge / GAUGE_MAX);
      if (after > before) events.push({ tick: t, type: "bar", side: i, bars: after });
    }
    // 3. decisions + cast countdown
    const resolve: Side[] = [];
    for (const i of sides) {
      const me = this.st[i];
      if (me.castLeft > 0) {
        me.castLeft--;
        if (me.castLeft === 0) resolve.push(i);
        continue;
      }
      const slot = inputs[i];
      if (slot === null || !this.canUse(i, slot)) continue;
      const m = this.f[i].moves[slot];
      if (!m) continue;
      me.gauge -= m.bars * GAUGE_MAX;
      me.castSlot = slot;
      me.plan = null;
      acted[i] = true;
      events.push({ tick: t, type: "act", side: i, slot, cost: m.bars });
      if (m.castTicks > 0) {
        me.castLeft = m.castTicks;
        events.push({ tick: t, type: "cast", side: i, slot, ticks: m.castTicks });
      } else {
        resolve.push(i);
      }
    }
    // 4. resolutions (a then b; when both resolve in the same tick one coin flip decides)
    if (resolve.length === 2 && this.rng.nextInt(2) === 1) resolve.reverse();
    for (const i of resolve) {
      if (this.isOver() || this.st[i].hp <= 0) break;
      this.resolveMove(i, events);
    }
    // 5. hard cap
    if (!this.isOver() && t >= HARD_CAP) {
      const [a, b] = this.st;
      const l = a.hp * b.maxHp;
      const r = b.hp * a.maxHp;
      this.winner = l > r ? 0 : r > l ? 1 : (this.rng.nextInt(2) as Side);
      this.endReason = "timeout";
      events.push({ tick: t, type: "end", winner: this.winner, reason: "timeout" });
    }
    return { events, acted };
  }

  private resolveMove(i: Side, events: BattleEvent[]): void {
    const me = this.st[i];
    const foeSide: Side = i === 0 ? 1 : 0;
    const foe = this.st[foeSide];
    const m = this.f[i].moves[me.castSlot];
    if (!m) return;
    me.cooldowns[m.slot] = m.cooldownTicks;
    if (m.kind === "heal") {
      const heal = Math.max(1, Math.floor((me.maxHp * m.power) / 1000));
      me.hp = Math.min(me.maxHp, me.hp + heal);
      events.push({ tick: this.tick, type: "heal", side: i, amount: heal, hp: me.hp });
      return;
    }
    const s = this.f[i].stats;
    const fs = this.f[foeSide].stats;
    const atk = m.kind === "physical" ? s.STR : s.INT;
    const def = m.kind === "physical" ? fs.DEF : fs.RES;
    const raw = Math.floor((m.power * 2 * atk * atk) / Math.max(1, atk + def) / 100);
    const typePct = m.attr !== "none" && BEATS[m.attr] === this.attr[foeSide] ? 150 : m.attr !== "none" && BEATS[this.attr[foeSide]] === m.attr ? 75 : 100;
    let dmg = Math.floor((raw * 60 * typePct) / 10_000);
    dmg = Math.floor((dmg * (90 + this.rng.nextInt(11))) / 100);
    if (this.tick > HEAT_START) dmg = Math.floor((dmg * (100 + 3 * Math.floor((this.tick - HEAT_START) / TICK_HZ))) / 100);
    dmg = Math.max(1, dmg);
    foe.hp = Math.max(0, foe.hp - dmg);
    events.push({ tick: this.tick, type: "hit", side: foeSide, dmg, hp: foe.hp, typePct });
    if (foe.hp === 0) {
      this.winner = i;
      this.endReason = "ko";
      events.push({ tick: this.tick, type: "ko", side: foeSide });
      events.push({ tick: this.tick, type: "end", winner: i, reason: "ko" });
    }
  }
}
