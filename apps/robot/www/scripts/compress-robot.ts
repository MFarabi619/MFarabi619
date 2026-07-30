import { existsSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { NodeIO } from "@gltf-transform/core";
import { ALL_EXTENSIONS } from "@gltf-transform/extensions";
import { draco } from "@gltf-transform/functions";
import draco3d from "draco3dgltf";

// Draco-compresses the robot_cad-generated source (apps/robot/assets/robot.glb)
// into the served public glb. Wired as `prebuild`, so it regenerates locally
// when the mesh changes and no-ops in CI: the source is gitignored, so clones
// have no source and build from the committed public glb. Also runnable
// directly: `pnpm robot:glb`.
const here = dirname(fileURLToPath(import.meta.url));
const source = resolve(here, "../../assets/robot.glb");
const destination = resolve(here, "../../assets/public/robot.glb");

if (!existsSync(source)) {
  console.log(`skip: no source at ${source} (using committed ${destination})`);
  process.exit(0);
}
if (
  existsSync(destination) &&
  statSync(destination).mtimeMs >= statSync(source).mtimeMs
) {
  console.log(`skip: ${destination} already up to date`);
  process.exit(0);
}

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
io.registerDependencies({
  "draco3d.encoder": await draco3d.createEncoderModule(),
  "draco3d.decoder": await draco3d.createDecoderModule(),
});

const document = await io.read(source);
await document.transform(draco());
await io.write(destination, document);

console.log(`compressed ${source} -> ${destination}`);
