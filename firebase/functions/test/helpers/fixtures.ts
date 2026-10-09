import { registerCharacterHandler } from "../../src/callables/registerCharacter";
import { joinQueueHandler } from "../../src/callables/matchmaking";
import { COL, db } from "../../src/lib/firebase";
import type { MatchDoc } from "../../src/model";
import { registerInput, req, seedUser } from "./emulator";

/** Seeds a consenting user and registers one character; returns its snapshot id. */
export async function registeredPlayer(uid: string, over: Record<string, unknown> = {}): Promise<string> {
  await seedUser(uid);
  const res = await registerCharacterHandler(req(uid, registerInput({ localCharacterId: `c-${uid}`, ...over })));
  if (!res.ok) throw new Error(`registration failed: ${res.reason}`);
  return res.snapshotId;
}

/** Two registered players matched against each other. */
export async function pvpMatch(a = "alice", b = "bob") {
  const sa = await registeredPlayer(a);
  const sb = await registeredPlayer(b);
  const r1 = await joinQueueHandler(req(a, { characterId: sa }));
  const r2 = await joinQueueHandler(req(b, { characterId: sb }));
  if (r1.status !== "waiting" || r2.status !== "matched") throw new Error("pairing failed");
  return { matchId: r2.matchId, sa, sb };
}

export async function getMatch(matchId: string): Promise<MatchDoc> {
  return (await db().collection(COL.matches).doc(matchId).get()).data() as MatchDoc;
}
