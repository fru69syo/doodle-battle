/**
 * Validator for AI-proposed moves — same deterministic rules (and warning
 * texts) as app/lib/domain/battle_v3/validator.dart (GAME_DESIGN_V2 §5.6).
 * The AI never decides numbers: every number is clamped to the template
 * range and the move is shrunk to the slot budget, or rejected.
 */
import {
  atkFormula,
  ATK_FORMULAS,
  clampRange,
  COLOURS,
  fitToBudget,
  makeMove,
  type Move,
  moveCost,
  moveToJson,
  SECONDARY_RANGES,
  type SecondaryType,
  slotBudget,
  STAGE_STATS,
  TEMPLATES,
  VFX,
} from './moves';
import { type Attr, isAttr, Stat, type StatIndex, statIndex, type V3Spec } from './spec';

export interface MoveValidation {
  move: Move | null;
  warnings: string[];
  rejected: boolean;
  reason: string | null;
}

const KANA_NAME = /^[ぁ-ゖァ-ヺー]{1,10}$/;
const KANA_FLAVOR = /^[ぁ-ゖァ-ヺー、。！？ 　]{0,30}$/;

/** Integer of a JSON number (floor, saturated at ±1e9), else `def`. */
function intOr(v: unknown, def: number): number {
  if (typeof v !== 'number' || !Number.isFinite(v)) return def;
  if (Number.isInteger(v) && Math.abs(v) < 1e15) return v;
  if (v >= 1e9) return 1000000000;
  if (v <= -1e9) return -1000000000;
  return Math.floor(v);
}

const isNumber = (v: unknown) => typeof v === 'number';

export type NgCheck = (s: string) => boolean;

/** Validates one AI move for `slot` of a character with attribute `own`. */
export function validateAiMove(
  s: V3Spec,
  json: Record<string, unknown>,
  opts: { slot: number; own: Attr; moveFactorPct: number; ngCheck?: NgCheck },
): MoveValidation {
  const { slot, own } = opts;
  const w: string[] = [];
  const reject = (r: string): MoveValidation => ({ move: null, warnings: w, rejected: true, reason: r });

  const tplId = json.template;
  if (typeof tplId !== 'string' || !Object.prototype.hasOwnProperty.call(TEMPLATES, tplId)) {
    return reject('unknown template');
  }
  const tpl = TEMPLATES[tplId]!;
  const dmg = tpl.kind === 'physical' || tpl.kind === 'special';
  const numParam = (k: string, def: number): number => {
    const v = json[k];
    const r = tpl.ranges[k];
    let i = intOr(v, def);
    if (v !== undefined && v !== null && !isNumber(v)) w.push(`${k} not a number`);
    if (r && (i < r[0] || i > r[1])) {
      w.push(`${k} clamped`);
      i = clampRange(r, i);
    }
    return i;
  };

  if (slot === 0 && !dmg) return reject('slot 1 must be a damage move');
  if (slot === 3 && !dmg) return reject('slot 4 must be a damage move');

  let attr: Attr = isAttr(json.attribute) ? json.attribute : 'none';
  const supportKind = tpl.kind === 'heal' || tpl.kind === 'buff' || tpl.kind === 'shield';
  if (supportKind && attr !== 'none') {
    w.push('support moves have no attribute');
    attr = 'none';
  }
  if (slot === 0 && attr !== own) {
    w.push('slot 1 attribute forced to own');
    attr = own;
  }
  if (slot === 3 && attr !== 'none') {
    w.push('slot 4 (ひっさつ) is always neutral');
    attr = 'none';
  }
  if (slot === 1 && attr === own) {
    w.push('slot 2 attribute must differ from slot 1');
    attr = 'none';
  }

  const name = typeof json.name === 'string' ? json.name : '';
  let flavor = typeof json.flavor === 'string' ? json.flavor : '';
  if (!KANA_NAME.test(name) || (opts.ngCheck?.(name) ?? false)) return reject('name');
  if (!KANA_FLAVOR.test(flavor) || (opts.ngCheck?.(flavor) ?? false)) {
    w.push('flavor dropped');
    flavor = '';
  }
  let vfx = typeof json.vfx === 'string' ? json.vfx : '';
  if (!(VFX as readonly string[]).includes(vfx)) {
    w.push('vfx defaulted');
    vfx = dmg ? 'punch' : 'glow';
  }
  let colour = typeof json.colour === 'string' ? json.colour : '';
  if (!(COLOURS as readonly string[]).includes(colour)) {
    w.push('colour defaulted');
    colour = 'white';
  }

  let formula = typeof json.atkFormula === 'string' ? atkFormula(json.atkFormula) : undefined;
  const physical = tpl.kind === 'physical';
  if (dmg && (formula === undefined || formula.physical !== physical)) {
    w.push('atkFormula defaulted');
    formula = physical ? ATK_FORMULAS[0] : ATK_FORMULAS[3];
  }
  let statKind: StatIndex = Stat.str;
  if (tpl.kind === 'buff' || tpl.kind === 'debuff') {
    const si = typeof json.stat === 'string' ? statIndex(json.stat) : undefined;
    if (si === undefined || !STAGE_STATS.includes(si)) return reject('stat');
    statKind = si;
  }

  let secondary: SecondaryType = 'none';
  let secChance = 0;
  let secStat: StatIndex = Stat.def;
  let drain = 0;
  const secJ = json.secondary;
  if (dmg && typeof secJ === 'object' && secJ !== null && !Array.isArray(secJ)) {
    const sec = secJ as Record<string, unknown>;
    const types: SecondaryType[] = ['none', 'poison', 'paralyze', 'debuff', 'drain'];
    secondary = types.find((t) => t === sec.type) ?? 'none';
    const sn = (k: 'chance' | 'drainPct') => {
      const i = intOr(sec[k], SECONDARY_RANGES[k][0]);
      const c = clampRange(SECONDARY_RANGES[k], i);
      if (c !== i) w.push(`secondary.${k} clamped`);
      return c;
    };
    if (secondary === 'poison' || secondary === 'paralyze' || secondary === 'debuff') secChance = sn('chance');
    if (secondary === 'debuff') {
      const si = typeof sec.stat === 'string' ? statIndex(sec.stat) : undefined;
      if (si === undefined || !STAGE_STATS.includes(si)) {
        w.push('secondary dropped');
        secondary = 'none';
      } else {
        secStat = si;
      }
    }
    if (secondary === 'drain') drain = sn('drainPct');
  }

  // Same evaluation order as the Dart constructor arguments.
  const has = (k: string) => Object.prototype.hasOwnProperty.call(tpl.ranges, k);
  const power = dmg ? numParam('power', 100) : 0;
  const hits = dmg ? numParam('hits', tpl.ranges.hits![0]) : 1;
  const accuracy = has('accuracy') ? numParam('accuracy', 100) : 100;
  const critBonus = dmg ? numParam('critBonus', 0) : 0;
  const spCost = numParam('spCost', 0);
  const castTicks = numParam('castTicks', 0);
  const cooldownTicks = numParam('cooldownTicks', tpl.ranges.cooldownTicks![0]);
  const healPct = tpl.kind === 'heal' ? numParam('healPct', 10) : 0;
  const stages = has('stages') ? numParam('stages', 1) : 0;
  const durationTicks = has('durationTicks') ? numParam('durationTicks', tpl.ranges.durationTicks![0]) : 0;
  const chance = has('chance') ? numParam('chance', 30) : 0;
  const shieldPct = has('shieldPct') ? numParam('shieldPct', 20) : 0;

  let m = makeMove({
    template: tplId,
    attr,
    name,
    flavor,
    vfx,
    colour,
    atkFormula: formula ?? ATK_FORMULAS[0]!,
    power,
    hits,
    accuracy,
    critBonus,
    spCost,
    castTicks,
    cooldownTicks,
    secondary,
    secondaryChance: secChance,
    secondaryStat: secStat,
    drainPct: drain,
    healPct,
    stat: statKind,
    stages,
    durationTicks,
    chance,
    shieldPct,
  });

  if (slot === 0 && (m.spCost !== 0 || m.cooldownTicks !== 0 || m.castTicks > 5)) {
    w.push('slot 1 made free (sp 0, cooldown 0, cast <= 5)');
    m = { ...m, spCost: 0, cooldownTicks: 0, castTicks: m.castTicks > 5 ? 5 : m.castTicks };
  }
  if ((tpl.kind === 'buff' || tpl.kind === 'debuff') && m.cooldownTicks < m.durationTicks) {
    m = { ...m, cooldownTicks: m.durationTicks };
  }

  const fitted = fitToBudget(s, m, slotBudget(s, slot, opts.moveFactorPct));
  if (fitted === null) return reject('over budget');
  if (fitted !== m) w.push('scaled to budget');
  return { move: fitted, warnings: w, rejected: false, reason: null };
}

export interface SlotValidation {
  slot: number;
  result: MoveValidation;
  accepted: boolean;
  /** Normalised proposal to persist, or null (offline fallback). */
  proposal: Record<string, unknown> | null;
}

/**
 * Validates a whole AI answer `{moves: [m0..m3]}`: missing / malformed
 * entries and names already used by an earlier accepted slot are rejected.
 * Always 4 results.
 */
export function validateAiMoveSet(
  s: V3Spec,
  json: unknown,
  opts: { own: Attr; moveFactorPct: number; ngCheck?: NgCheck },
): SlotValidation[] {
  const raw = typeof json === 'object' && json !== null && !Array.isArray(json) ? (json as Record<string, unknown>).moves : null;
  const list: unknown[] = Array.isArray(raw) ? raw : [];
  const names = new Set<string>();
  const out: SlotValidation[] = [];
  for (let slot = 0; slot < 4; slot++) {
    const m = slot < list.length ? list[slot] : null;
    let res: MoveValidation;
    if (typeof m !== 'object' || m === null || Array.isArray(m)) {
      res = { move: null, warnings: [], rejected: true, reason: 'missing' };
    } else {
      res = validateAiMove(s, m as Record<string, unknown>, { slot, ...opts });
      if (!res.rejected) {
        if (names.has(res.move!.name)) {
          res = { move: null, warnings: res.warnings, rejected: true, reason: 'duplicate name' };
        } else {
          names.add(res.move!.name);
        }
      }
    }
    out.push({
      slot,
      result: res,
      accepted: !res.rejected,
      proposal: res.move ? moveToJson(res.move) : null,
    });
  }
  return out;
}

/** Per slot: the accepted AI move, else the offline move. */
export function resolveWithOffline(offline: readonly Move[], v: readonly SlotValidation[]): Move[] {
  return offline.map((m, i) => (v[i]?.accepted ? v[i]!.result.move! : m));
}

/** Golden-vector form of a validation result. */
export function validationToJson(s: V3Spec, v: MoveValidation): Record<string, unknown> {
  return v.rejected
    ? { rejected: true, reason: v.reason }
    : { rejected: false, move: moveToJson(v.move!), cost: moveCost(s, v.move!), warnings: v.warnings };
}
