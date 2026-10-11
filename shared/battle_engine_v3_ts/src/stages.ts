/**
 * Single-player stage table (10 worlds × 10). Port of
 * app/lib/domain/battle_v3/stages.dart.
 */
import type { AiTier } from './ai';
import { STAGE_POWER_TABLE } from './stagePowerTable';

export { STAGE_POWER_TABLE };

export const STAGE_POWER_PCT = [88, 89, 90, 91, 92, 93, 94, 95, 96, 98] as const;

export const WORLD_NAMES = [
  'らくがき のはら',
  'クレヨン もり',
  'えのぐ うみ',
  'いろえんぴつ やま',
  'ペンギン こおり',
  'マーカー まち',
  'ねんど さばく',
  'はさみ おしろ',
  'にじいろ そら',
  'まっしろ ノート',
] as const;

export const WORLD_ROSTERS: readonly (readonly string[])[] = [
  ['cpu_fire_blob', 'cpu_leaf_caterpillar', 'cpu_stickman', 'cpu_leaf_frog'],
  ['cpu_bear', 'cpu_butterfly', 'cpu_hedgehog', 'cpu_thunder_bird'],
  ['cpu_water_fish', 'cpu_octopus', 'cpu_jellyfish', 'cpu_swordfish'],
  ['cpu_rock_golem', 'cpu_flower', 'cpu_fire_spiky', 'cpu_dino'],
  ['cpu_penguin', 'cpu_snowman', 'cpu_water_snake', 'cpu_shadow_ghost'],
  ['cpu_car', 'cpu_train', 'cpu_rainbow_robot', 'cpu_ufo'],
  ['cpu_crab', 'cpu_cactus', 'cpu_thunder_star', 'cpu_shadow_bat'],
  ['cpu_knight', 'cpu_rainbow_cat', 'cpu_rocket', 'cpu_castle'],
  ['cpu_cloud', 'cpu_rainbow_bird', 'cpu_kite', 'cpu_dragon'],
  ['cpu_stickman', 'cpu_knight', 'cpu_dragon', 'cpu_scribble_king'],
];

export interface Stage {
  stage: number;
  world: number;
  position: number;
  recommendedLevel: number;
  cpuLevel: number;
  aiTier: AiTier;
  cpuId: string;
  boss: boolean;
  cpuPowerPct: number;
}

export function stageTier(n: number): AiTier {
  return n <= 20 ? 'weak' : n <= 60 ? 'normal' : 'strong';
}

export function stageAt(n: number): Stage {
  const world = Math.floor((n - 1) / 10) + 1;
  const pos = ((n - 1) % 10) + 1;
  const roster = WORLD_ROSTERS[world - 1]!;
  const boss = pos === 10;
  const tier = stageTier(n);
  return {
    stage: n,
    world,
    position: pos,
    recommendedLevel: n,
    cpuLevel: n,
    aiTier: tier,
    cpuId: boss ? roster[roster.length - 1]! : roster[(pos - 1) % (roster.length - 1)]!,
    boss,
    cpuPowerPct: STAGE_POWER_TABLE[n - 1]!,
  };
}

export function stageTable(): Stage[] {
  return Array.from({ length: 100 }, (_, i) => stageAt(i + 1));
}
