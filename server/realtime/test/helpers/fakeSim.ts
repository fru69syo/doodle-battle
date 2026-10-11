import type { AiTier, BattleEngine, BattleEvent, BattleSim, FighterSetup, FighterSource, Side, SideView, StepResult } from "../../src/engine";

/**
 * Scripted engine for timer tests: a side's gauge fills in `fillTicks` ticks, then it is ready
 * until an input arrives. Every action removes `damage` HP from the foe. Fully predictable.
 */
export class FakeSim implements BattleSim {
  tick = 0;
  winner: Side | null = null;
  endReason: "ko" | "timeout" | null = null;
  readonly inputsSeen: { tick: number; side: Side; slot: number }[] = [];
  readonly hp: [number, number];
  readonly gauge: [number, number] = [0, 0];
  readonly ready: [boolean, boolean] = [false, false];
  unusable = new Set<string>();
  aiChoice = 1;
  aiCalls = 0;

  constructor(
    readonly fillTicks: [number, number] = [10, 10],
    readonly damage = 10,
    maxHp = 100,
    readonly hardCap = 1800,
  ) {
    this.hp = [maxHp, maxHp];
  }

  get finished(): boolean {
    return this.winner !== null;
  }

  isReady(side: Side): boolean {
    return this.ready[side];
  }

  canUse(side: Side, slot: number): boolean {
    return !this.unusable.has(`${side}:${slot}`);
  }

  chooseMove(_side: Side, _tier: AiTier): number {
    this.aiCalls++;
    return this.aiChoice;
  }

  view(side: Side): SideView {
    return { hp: this.hp[side], maxHp: 100, sp: 0, gauge: this.gauge[side], ready: this.ready[side], casting: false };
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
      if (!this.ready[s]) {
        this.gauge[s]++;
        if (this.gauge[s] >= this.fillTicks[s]) {
          this.ready[s] = true;
          events.push({ tick: this.tick, type: "ready", side: s });
        }
      }
    }
    for (const s of [0, 1] as const) {
      const slot = inputs[s];
      if (!this.ready[s] || slot === null || !this.canUse(s, slot) || this.winner !== null) continue;
      acted[s] = true;
      this.ready[s] = false;
      this.gauge[s] = 0;
      this.inputsSeen.push({ tick: this.tick, side: s, slot });
      const foe: Side = s === 0 ? 1 : 0;
      this.hp[foe] = Math.max(0, this.hp[foe] - this.damage);
      events.push({ tick: this.tick, type: "act", side: s, slot });
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
    engineData: null,
    moves: [0, 1, 2].map((slot) => ({ slot, name: `m${slot}`, templateId: "strike", attr: "gu", spCost: 0 })),
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
