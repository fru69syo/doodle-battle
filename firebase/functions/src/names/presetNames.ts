/**
 * Safe preset character names offered when a child's name is rejected
 * (SPEC §5: "不合格ならプリセットの名前に置き換えるよう促す") or when the AI
 * suggestions do not pass the filters.
 */
export const PRESET_CHARACTER_NAMES: readonly string[] = [
  "もこたん", "ぴかりん", "ぷにまる", "ころりん", "ふわりん", "ぽよまる", "きらりん", "どんぐり",
  "まめたろう", "ぽんた", "にこまる", "ぷっくん", "ちびすけ", "もちもち", "ぴょんた", "ほっぺ",
  "くるりん", "ぱたぱた", "ぴよすけ", "まるたん", "ゆきんこ", "ほしまる", "にじまる", "かぜのすけ",
];

export function pickPresetNames(count: number, rand: () => number = Math.random): string[] {
  const pool = [...PRESET_CHARACTER_NAMES];
  const out: string[] = [];
  while (out.length < count && pool.length > 0) {
    const i = Math.floor(rand() * pool.length);
    out.push(...pool.splice(i, 1));
  }
  return out;
}
