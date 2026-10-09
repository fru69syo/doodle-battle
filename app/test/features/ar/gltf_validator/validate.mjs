// Usage: node validate.mjs <dir-with-glb-files>
// Exits non-zero if any file has validation errors (warnings are printed).
import fs from 'node:fs';
import path from 'node:path';
import validator from 'gltf-validator';

const dir = process.argv[2];
let failed = false;
for (const name of fs.readdirSync(dir).filter((f) => f.endsWith('.glb')).sort()) {
  const data = new Uint8Array(fs.readFileSync(path.join(dir, name)));
  const report = await validator.validateBytes(data, { uri: name, maxIssues: 100 });
  const { numErrors, numWarnings, numInfos, numHints, messages } = report.issues;
  const info = report.info;
  console.log(
    `${name}: errors=${numErrors} warnings=${numWarnings} infos=${numInfos} hints=${numHints}` +
      ` | meshes=${info.meshCount ?? '?'} materials=${info.materialCount} animations=${info.animationCount}` +
      ` textures=${info.resources?.filter((r) => r.pointer.startsWith('/images')).length ?? '?'}`,
  );
  for (const m of messages) console.log(`  [${m.severity}] ${m.code} ${m.pointer ?? ''} ${m.message}`);
  if (numErrors > 0) failed = true;
}
process.exit(failed ? 1 : 0);
