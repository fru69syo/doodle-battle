/**
 * Seed helpers. The battle itself uses the shared engine's mulberry32 (state
 * kept in the engine state); the ghost AI seeds its own rng per
 * (match seed, turn, side) with `turnSeed`.
 */

/** FNV-1a 32-bit hash of a string. */
export function hash32(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** Deterministic seed for one turn of one match. */
export function turnSeed(matchSeed: number, turn: number, salt = ""): number {
  return hash32(`${matchSeed}:${turn}:${salt}`);
}
