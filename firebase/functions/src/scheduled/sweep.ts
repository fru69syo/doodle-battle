import { logger } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { startGhostMatch } from "../battle/matchmaking";
import { enforceDeadline } from "../battle/matchService";
import { LIMITS } from "../config";
import { clock } from "../lib/clock";
import { COL, db } from "../lib/firebase";
import type { QueueDoc } from "../model";

export interface SweepStats {
  staleQueueRemoved: number;
  ghostMatches: number;
  turnsEnforced: number;
}

/**
 * Backstop for everything clients normally trigger themselves:
 * - drops queue entries whose client stopped heart-beating,
 * - starts ghost matches for players waiting ≥ 60 s,
 * - resolves turns whose 20 s deadline passed (both players gone, or a
 *   client that never called pollMatch).
 */
export async function sweep(): Promise<SweepStats> {
  const stats: SweepStats = { staleQueueRemoved: 0, ghostMatches: 0, turnsEnforced: 0 };
  const now = clock.now();
  const waiting = await db().collection(COL.queue).where("status", "==", "waiting").limit(500).get();
  for (const d of waiting.docs) {
    const q = d.data() as QueueDoc;
    if (now - q.lastSeenMs >= LIMITS.queueStaleMs) {
      await d.ref.delete({ lastUpdateTime: d.updateTime }).then(
        () => stats.staleQueueRemoved++,
        () => undefined, // changed meanwhile (heartbeat or matched)
      );
    } else if (now - q.joinedAtMs >= LIMITS.ghostAfterMs) {
      if (await startGhostMatch(q.uid)) stats.ghostMatches++;
    }
  }
  const expired = await db()
    .collection(COL.matches)
    .where("status", "==", "active")
    .where("turnDeadlineMs", "<", now - LIMITS.turnGraceMs)
    .limit(200)
    .get();
  for (const m of expired.docs) {
    try {
      if (await enforceDeadline(m.id)) stats.turnsEnforced++;
    } catch (err) {
      logger.error("sweep: enforceDeadline failed", { matchId: m.id, err: String(err) });
    }
  }
  return stats;
}

export const sweepMatches = onSchedule(
  { schedule: "every 1 minutes", timeZone: "Asia/Tokyo", timeoutSeconds: 120, memory: "256MiB" },
  async () => {
    const stats = await sweep();
    if (stats.staleQueueRemoved + stats.ghostMatches + stats.turnsEnforced > 0) logger.info("sweep", stats);
  },
);
