import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { defaultSpec, ELEMENTS, isShoboSkill, levelUpPct, parseSpec, statsAtLevel } from '../src';

const specJson = JSON.parse(readFileSync(join(__dirname, '..', '..', 'battle_spec', 'battle_spec.json'), 'utf8'));

describe('battle spec', () => {
  it('bundled spec equals shared/battle_spec/battle_spec.json', () => {
    expect(defaultSpec).toEqual(specJson);
  });

  it('generated specData.ts is up to date', () => {
    expect(() => execFileSync('node', [join(__dirname, '..', 'scripts', 'gen-spec.mjs'), '--check'])).not.toThrow();
  });

  it('type chart follows SPEC §4.1', () => {
    const m = defaultSpec.typeChart.matrix;
    const beats: [string, string][] = [['fire', 'leaf'], ['leaf', 'thunder'], ['thunder', 'water'], ['water', 'fire'], ['shadow', 'rainbow'], ['rainbow', 'shadow']];
    for (const a of ELEMENTS) {
      for (const d of ELEMENTS) {
        const adv = beats.some(([x, y]) => x === a && y === d);
        const dis = !adv && beats.some(([x, y]) => x === d && y === a);
        expect(m[a][d]).toBe(adv ? 150 : dis ? 75 : 100);
      }
    }
  });

  it('parseSpec rejects broken input', () => {
    expect(() => parseSpec({})).toThrow();
    const broken = structuredClone(specJson);
    broken.damage.scalePct = 1.5;
    expect(() => parseSpec(broken)).toThrow(/damage.scalePct/);
  });

  it('しょぼキャラ grow faster; threshold is skill > 75', () => {
    expect(isShoboSkill(defaultSpec, 75)).toBe(false);
    expect(isShoboSkill(defaultSpec, 75.1)).toBe(true);
    expect(levelUpPct(defaultSpec, true)).toBeGreaterThan(levelUpPct(defaultSpec, false));
    const base = { hp: 30, atk: 30, def: 30, spd: 30 };
    expect(statsAtLevel(defaultSpec, base, 30, {}, true).hp).toBeGreaterThan(statsAtLevel(defaultSpec, base, 30, {}, false).hp);
  });
});
