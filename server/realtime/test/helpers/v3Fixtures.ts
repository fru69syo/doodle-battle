import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/** shared/battle_spec_v3/golden_vectors.json (read from the repo, never copied). */
export function goldenV3(): Record<string, any> {
  return JSON.parse(readFileSync(resolve(__dirname, "..", "..", "..", "..", "shared", "battle_spec_v3", "golden_vectors.json"), "utf8")) as Record<string, unknown>;
}

/** `snapshots/{id}.engine` for golden genome `index`, with the hidden verdict `trust`. */
export function v2EngineData(index: number, trust: string | null = null): Record<string, unknown> {
  const g = goldenV3().genomes[index].input;
  return { features: g.features, energy10: g.energy10, skill10: g.skill10, imageHash: g.imageHash, trust, proposals: [] };
}
