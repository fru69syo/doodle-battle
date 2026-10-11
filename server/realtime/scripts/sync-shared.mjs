// Copies repo-level shared data into src/vendor/ so it is compiled into lib/ and shipped in the
// container image (the image only contains server/realtime). Runs before build, lint and test.
//
//   shared/cost_mode/cost_mode.json            -> src/vendor/cost_mode.json     (required)
//   shared/battle_spec_v3/golden_vectors.json  -> test fixtures read directly from shared/ (not copied)
//
// When the Engine v3 package lands (shared/battle_engine_v3_ts), it becomes a normal npm
// dependency ("file:../../shared/battle_engine_v3_ts"), not a copied folder. See
// docs/REALTIME_PROTOCOL.md §9 "Engine swap".
import { cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const pkgDir = resolve(here, "..");
const repoRoot = resolve(pkgDir, "..", "..");
const vendor = join(pkgDir, "src", "vendor");

rmSync(vendor, { recursive: true, force: true });
mkdirSync(vendor, { recursive: true });

const costMode = join(repoRoot, "shared", "cost_mode", "cost_mode.json");
if (!existsSync(costMode)) throw new Error("Missing shared/cost_mode/cost_mode.json");
cpSync(costMode, join(vendor, "cost_mode.json"));
console.log("[sync-shared] shared/cost_mode/cost_mode.json -> src/vendor/cost_mode.json");
