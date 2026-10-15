import type { AiTier, BattleEngine, BattleEvent, BattleSim, FighterSetup, FighterSource, Side, SideView, StepResult } from "../../src/engine";

/**
 * Scripted engine for timing tests (stackable bars): a side gains one bar every `fillTicks`
 * ticks up to `maxBars`; move `slot` costs `costs[slot]` bars. Every action removes `damage` HP
 * from the foe. The AI waits `thinkTicks` after its first bar, then uses `aiChoice` once
 * affordable; おまかせ uses `omakaseChoice` once affordable. Fully predictable.
 */
export class FakeSim implements BattleSim {
  tick = 0;
  winner: Side | null = null;
  endReason: "ko" | "timeout" | null = null;
  readonly inputsSeen: { tick: number; side: Side; slot: number }[] = [];
  readonly hp: [number, number];
  /** Ticks of filling toward the next bar, and full bars. */
  readonly fill: [number, number] = [0, 0];
  readonly bars: [number, number] = [0, 0];
  readonly waited: [number, number] = [0, 0];
  readonly plans: [number | null, number | null] = [null, null];
  unusable = new Set<string>();
  aiChoice = 1;
  omakaseChoice = 1;
  aiCalls = 0;
  omakaseCalls = 0;
  cleared = 0;

  constructor(
    readonly fillTicks: [number, number] = [10, 10],
    readonly damage = 10,
    maxHp = 100,
    readonly hardCap = 1800,
    readonly maxBars = 3,
    readonly costs: readonly number[] = [1, 2, 3],
  ) {
    this.hp = [maxHp, maxHp];
  }

  get finished(): boolean {
    return this.winner !== null;
  }

  canQueue(_side: Side, slot: number): boolean {
    const c = this.costs[slot];
    return c !== undefined && c <= this.maxBars;
  }

  canUse(side: Side, slot: number): boolean {
    return this.canQueue(side, slot) && !this.unusable.has(`${side}:${slot}`) && this.bars[side] >= (this.costs[slot] ?? 99);
  }

  aiInput(side: Side, _tier: AiTier, thinkTicks: number): number | null {
    this.aiCalls++;
    if (this.bars[side] < 1 || this.waited[side] < thinkTicks) return null;
    this.plans[side] ??= this.aiChoice;
    return this.canUse(side, this.plans[side]) ? this.plans[side] : null;
  }

  omakaseInput(side: Side): number | null {
    this.omakaseCalls++;
    this.plans[side] ??= this.omakaseChoice;
    return this.canUse(side, this.plans[side]) ? this.plans[side] : null;
  }

  clearPlan(side: Side): void {
    this.cleared++;
    this.plans[side] = null;
  }

  view(side: Side): SideView {
    return { hp: this.hp[side], maxHp: 100, gauge: this.bars[side] * 10_000, bars: this.bars[side], maxBars: this.maxBars, casting: false };
  }

  stateHash(): string {
    return `${this.tick}:${this.hp.join(",")}`;
  }

  step(inputs: readonly [number | null, number | null]): StepResult {
    const events: BattleEvent[] = [];
    const acted: [boolean, boolean] = [false, false];
    if (this.winner !== null) return { events, acted };
    this.tick++;
    for (const s of [0, 1] as const) {
      if (this.bars[s] >= this.maxBars) continue;
      if (++this.fill[s] >= this.fillTicks[s]) {
        this.fill[s] = 0;
        this.bars[s]++;
        events.push({ tick: this.tick, type: "bar", side: s, bars: this.bars[s] });
      }
    }
    for (const s of [0, 1] as const) {
      const slot = inputs[s];
      if (slot === null || !this.canUse(s, slot) || this.winner !== null) {
        this.waited[s] = this.bars[s] >= 1 ? this.waited[s] + 1 : 0;
        continue;
      }
      acted[s] = true;
      this.bars[s] -= this.costs[slot] ?? 0;
      this.waited[s] = 0;
      this.plans[s] = null;
      this.inputsSeen.push({ tick: this.tick, side: s, slot });
      const foe: Side = s === 0 ? 1 : 0;
      this.hp[foe] = Math.max(0, this.hp[foe] - this.damage);
      events.push({ tick: this.tick, type: "select", side: s, slot, cost: this.costs[slot] ?? 0 });
      if (this.hp[foe] === 0) {
        this.winner = s;
        this.endReason = "ko";
      }
    }
    if (this.winner === null && this.tick >= this.hardCap) {
      this.winner = this.hp[0] >= this.hp[1] ? 0 : 1;
      this.endReason = "timeout";
    }
    return { events, acted };
  }
}

export function fakeSetup(): FighterSetup {
  return {
    attr: "gu",
    maxHp: 100,
    maxBars: 3,
    engineData: null,
    moves: [0, 1, 2].map((slot) => ({ slot, name: `m${slot}`, templateId: "strike", attr: "gu", bars: slot + 1 })),
  };
}

export class FakeEngine implements BattleEngine {
  readonly engineId = "fake";
  readonly tickHz = 10;
  readonly hardCapTick = 1800;
  sims: FakeSim[] = [];
  constructor(private readonly make: () => FakeSim = () => new FakeSim()) {}
  ratedFighter(_s: FighterSource, _lv: number): FighterSetup {
    return fakeSetup();
  }
  createBattle(): BattleSim {
    const s = this.make();
    this.sims.push(s);
    return s;
  }
}
