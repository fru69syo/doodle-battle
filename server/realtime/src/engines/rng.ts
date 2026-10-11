/** mulberry32 + deriveSeed + FNV-1a, bit-exact with shared/battle_engine_ts/src/rng.ts. */
export class Mulberry32 {
  private s: number;
  constructor(seed: number) {
    this.s = seed >>> 0;
  }
  nextUint32(): number {
    this.s = (this.s + 0x6d2b79f5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return (t ^ (t >>> 14)) >>> 0;
  }
  nextInt(n: number): number {
    if (!Number.isInteger(n) || n < 1) throw new RangeError(`n must be >= 1, got ${n}`);
    return this.nextUint32() % n;
  }
}

export function deriveSeed(seed: number, stream: number): number {
  return new Mulberry32((seed ^ Math.imul(stream + 1, 0x9e3779b1)) >>> 0).nextUint32();
}

export function fnv1a32(input: string): number {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(input)) {
    h ^= b;
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}
