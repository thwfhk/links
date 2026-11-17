import { build } from "esbuild";
import { copyFile, cp, mkdir, mkdtemp, rename, rm } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { packageExamples } from "./examples.mjs";
import { renderGuide } from "./guide.mjs";

const root = fileURLToPath(new URL("../../", import.meta.url));
const playground = join(root, "web", "playground");
const output = join(root, "web", "dist");
const compiled = join(root, "_build");

await mkdir(compiled, { recursive: true });
const staging = await mkdtemp(join(compiled, "web-demo-"));
try {
  for (const file of ["index.html", "styles.css"]) {
    await copyFile(join(playground, file), join(staging, file));
  }
  const runtime = join(compiled, "default", "web", "runtime");
  for (const file of ["worker.js", "worker-wasm.js"]) {
    await copyFile(join(runtime, file), join(staging, file));
  }
  await cp(join(runtime, "worker-wasm.assets"), join(staging, "worker-wasm.assets"), {
    recursive: true,
    dereference: true,
  });
  await build({
    entryPoints: [join(playground, "main.js")],
    outfile: join(staging, "app.js"),
    bundle: true,
    format: "esm",
    target: "es2020",
    minify: true,
  });

  const examples = await packageExamples(root, staging);
  await renderGuide(root, staging, examples);
  await rm(output, { recursive: true, force: true });
  await rename(staging, output);
} finally {
  await rm(staging, { recursive: true, force: true });
}
console.log("Built the SmallLinks playground in web/dist.");
