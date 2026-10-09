// Copies repo-level shared assets into src/vendor/ so they are compiled into
// lib/ and shipped with the functions source (Cloud Functions only uploads the
// functions/ directory). Runs automatically before build, lint and test.
//
//   shared/ng_words/*.json            -> src/vendor/ng_words/
//   shared/battle_spec/*.json         -> src/vendor/battle_spec/      (if present)
//   shared/battle_engine_ts/src/**    -> src/vendor/battle_engine/    (if present)
//
// src/vendor/ is git-ignored: the shared/ directory is the single source of truth.
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const functionsDir = resolve(here, "..");
const repoRoot = resolve(functionsDir, "..", "..");
const vendor = join(functionsDir, "src", "vendor");

rmSync(vendor, { recursive: true, force: true });
mkdirSync(vendor, { recursive: true });

function copyJsonDir(from, to, required) {
  const src = join(repoRoot, from);
  if (!existsSync(src)) {
    if (required) throw new Error(`Missing required shared dir: ${from}`);
    console.log(`[sync-shared] skip ${from} (not present)`);
    return;
  }
  mkdirSync(to, { recursive: true });
  for (const f of readdirSync(src)) {
    if (f.endsWith(".json")) cpSync(join(src, f), join(to, f));
  }
  console.log(`[sync-shared] ${from} -> ${to.replace(functionsDir + "/", "")}`);
}

copyJsonDir("shared/ng_words", join(vendor, "ng_words"), true);
copyJsonDir("shared/battle_spec", join(vendor, "battle_spec"), false);

const engineSrc = join(repoRoot, "shared", "battle_engine_ts", "src");
if (existsSync(engineSrc)) {
  cpSync(engineSrc, join(vendor, "battle_engine"), {
    recursive: true,
    filter: (p) => !/\.(test|spec)\.ts$/.test(p),
  });
  console.log("[sync-shared] shared/battle_engine_ts/src -> src/vendor/battle_engine");
} else {
  console.log("[sync-shared] skip shared/battle_engine_ts/src (not present; stub engine is used)");
}
