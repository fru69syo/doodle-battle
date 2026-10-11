/**
 * Cost mode (docs/LEARN_GCP.md §6). The kill-switch function writes config/costMode; the
 * battle server reads it (cached) and only changes how long children wait before a ghost
 * opponent is used, and whether two children are paired at all. Nothing is shown to children.
 */
import costModeSpec from "./vendor/cost_mode.json";

export type CostModeName = "normal" | "saving" | "minimal";

export interface CostFlags {
  cloudJudge: boolean;
  cloudMoveGen: boolean;
  pvp: boolean;
  ghostAfterSec: number;
}

export interface CostMode {
  mode: CostModeName;
  flags: CostFlags;
}

export const COST_MODES: Record<CostModeName, CostFlags> = costModeSpec.modes;

export function isCostModeName(v: unknown): v is CostModeName {
  return v === "normal" || v === "saving" || v === "minimal";
}

export function costModeFrom(name: unknown): CostMode {
  const mode: CostModeName = isCostModeName(name) ? name : "normal";
  return { mode, flags: COST_MODES[mode] };
}

/** Reads the current mode; implementations cache (the doc changes a few times per month). */
export interface CostModeSource {
  current(): CostMode;
}

/**
 * Polls a loader at most once per `ttlMs` and serves the cached value in between, so the hot
 * path (matchmaking ticks) never waits for Firestore. Unknown/failed reads keep the last value
 * (initially "normal": failing open on cost is fine, the budget alerts still fire).
 */
export class CachedCostMode implements CostModeSource {
  private value: CostMode = costModeFrom("normal");
  private fetchedAt = -Infinity;
  private inflight = false;

  constructor(
    private readonly load: () => Promise<unknown>,
    private readonly ttlMs = 60_000,
    private readonly now: () => number = Date.now,
    private readonly onError: (err: unknown) => void = () => {},
  ) {}

  current(): CostMode {
    if (!this.inflight && this.now() - this.fetchedAt >= this.ttlMs) void this.refresh();
    return this.value;
  }

  async refresh(): Promise<CostMode> {
    this.inflight = true;
    try {
      this.value = costModeFrom(await this.load());
    } catch (err) {
      this.onError(err);
    } finally {
      this.fetchedAt = this.now();
      this.inflight = false;
    }
    return this.value;
  }
}

/** Fixed mode (tests, local development). */
export class StaticCostMode implements CostModeSource {
  constructor(public mode: CostModeName = "normal") {}
  current(): CostMode {
    return costModeFrom(this.mode);
  }
}
