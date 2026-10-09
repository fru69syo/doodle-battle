import { describe, expect, it } from 'vitest';
import { fnv1a32, Mulberry32 } from '../src';

/** Canonical mulberry32 as published (Tommy Ettinger / bryc), returning uint32. */
function referenceMulberry32(a: number): () => number {
  return () => {
    let t = (a += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return (t ^ (t >>> 14)) >>> 0;
  };
}

describe('Mulberry32', () => {
  it('matches the canonical implementation', () => {
    for (const seed of [0, 1, 7, 123456789, 0x7fffffff, 0x80000000, 0xffffffff]) {
      const ref = referenceMulberry32(seed);
      const r = new Mulberry32(seed);
      for (let i = 0; i < 1000; i++) expect(r.nextUint32()).toBe(ref());
    }
  });

  it('resumes from its state', () => {
    const r = new Mulberry32(99);
    for (let i = 0; i < 10; i++) r.nextUint32();
    const resumed = new Mulberry32(r.state);
    for (let i = 0; i < 10; i++) expect(resumed.nextUint32()).toBe(r.nextUint32());
  });

  it('nextInt stays in range and rejects bad bounds', () => {
    const r = new Mulberry32(5);
    for (let i = 0; i < 1000; i++) {
      const v = r.nextInt(6);
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThan(6);
    }
    expect(() => r.nextInt(0)).toThrow();
  });

  it('fnv1a32 known values', () => {
    expect(fnv1a32('')).toBe(0x811c9dc5);
    expect(fnv1a32('a')).toBe(0xe40c292c);
    expect(fnv1a32('foobar')).toBe(0xbf9cf968);
  });
});
