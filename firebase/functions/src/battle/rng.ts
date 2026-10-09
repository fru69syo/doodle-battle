/**
 * Small portable PRNG helpers used by the stub engine and the ghost AI.
 * The shared engine brings its own PRNG; the adapter only needs a per-turn
 * seed so that a turn can be resolved statelessly from (match seed, turn).
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

/** mulberry32: returns floats in [0, 1). */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
