/**
 * 2.5D rig blob validation (size / shape only) — same rules as
 * app/lib/domain/rig_blob.dart. Invalid or unknown-version blobs are
 * dropped (the opponent's device falls back to the automatic rig).
 */
export const RIG_VERSION = 1;
export const RIG_MAX_BYTES = 4096;
export const RIG_MAX_LIMBS = 12;
export const RIG_MAX_SIDE = 4096;
export const RIG_LIMB_KINDS: ReadonlySet<string> = new Set(['head', 'arm', 'leg', 'tail', 'extra']);
export const RIG_SOURCES: ReadonlySet<string> = new Set(['auto', 'edited']);

const isObj = (x: unknown): x is Record<string, unknown> => typeof x === 'object' && x !== null && !Array.isArray(x);
const isNum = (x: unknown): x is number => typeof x === 'number' && Number.isFinite(x);

/** Why `json` is not a valid rig blob, or null when it is. */
export function rigProblem(json: unknown): string | null {
  if (!isObj(json)) return 'not an object';
  let enc: string;
  try {
    enc = JSON.stringify(json);
  } catch {
    return 'not JSON';
  }
  if (new TextEncoder().encode(enc).length > RIG_MAX_BYTES) return 'too large';
  if (json.v !== RIG_VERSION) return 'version';
  const w = json.width;
  const h = json.height;
  if (!isNum(w) || !isNum(h)) return 'size';
  if (!(w > 0 && w <= RIG_MAX_SIDE && h > 0 && h <= RIG_MAX_SIDE)) return 'size';
  const point = (p: unknown) =>
    Array.isArray(p) && p.length === 2 && isNum(p[0]) && isNum(p[1]) && p[0] >= -w && p[0] <= 2 * w && p[1] >= -h && p[1] <= 2 * h;
  if (!point(json.root) || !point(json.chest)) return 'body';
  const g = json.ground;
  if (g !== undefined && g !== null && (!isNum(g) || g < -h || g > 2 * h)) return 'ground';
  const src = json.source;
  if (src !== undefined && src !== null && !(typeof src === 'string' && RIG_SOURCES.has(src))) return 'source';
  const limbs = json.limbs;
  if (!Array.isArray(limbs)) return 'limbs';
  if (limbs.length > RIG_MAX_LIMBS) return 'too many limbs';
  for (const l of limbs) {
    if (!isObj(l)) return 'limb';
    if (!(typeof l.kind === 'string' && RIG_LIMB_KINDS.has(l.kind))) return 'limb kind';
    if (!point(l.base) || !point(l.mid) || !point(l.tip)) return 'limb point';
    if (l.edited !== undefined && l.edited !== null && typeof l.edited !== 'boolean') return 'limb edited';
  }
  return null;
}

/** A JSON-safe copy of `json` when valid, else null. */
export function validateRigJson(json: unknown): Record<string, unknown> | null {
  return rigProblem(json) === null ? (JSON.parse(JSON.stringify(json)) as Record<string, unknown>) : null;
}
