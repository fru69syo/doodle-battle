import { COL, db } from "./firebase";
import { clock } from "./clock";
import { ErrorCode, fail } from "./errors";

export interface RateRule {
  readonly key: string;
  readonly limit: number;
  readonly windowMs: number;
}

interface Bucket {
  start: number;
  count: number;
}

/**
 * Fixed-window rate limiter stored in `rateLimits/{uid}` (one doc per user,
 * one map entry per window). Consumes one unit from every rule atomically or
 * throws RATE_LIMITED without consuming anything.
 */
export async function consumeRateLimit(uid: string, rules: readonly RateRule[]): Promise<void> {
  const ref = db().collection(COL.rateLimits).doc(uid);
  const now = clock.now();
  const exceeded = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const buckets = (snap.data()?.buckets ?? {}) as Record<string, Bucket>;
    const next: Record<string, Bucket> = { ...buckets };
    for (const r of rules) {
      const b = buckets[r.key];
      const fresh = !b || now - b.start >= r.windowMs;
      const count = fresh ? 0 : b.count;
      if (count >= r.limit) return true;
      next[r.key] = { start: fresh ? now : b.start, count: count + 1 };
    }
    tx.set(ref, { buckets: next, updatedAt: now });
    return false;
  });
  if (exceeded) fail(ErrorCode.RATE_LIMITED, "too many requests");
}
