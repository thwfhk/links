import { copyFile, mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const examples = [
  { id: "examples/factorial.links", title: "Factorials" },
  { id: "examples/met/fresco-effects/single-yield.links", title: "Single yield" },
  { id: "examples/met/fresco-types/rank-two.links", title: "Rank-two polymorphism" },
  { id: "examples/met/fresco-effects/find_mask_paper.links", title: "Search with effect handlers" },
  { id: "examples/handlers/module_import.links", title: "Import a state handler" },
];

// The worker also embeds the sibling module used by module_import.links.
const imports = [
  "examples/handlers/shallow_state.links",
];

export async function packageExamples(root, output) {
  const sources = [...examples.map(({ id }) => id), ...imports];
  await Promise.all(sources.map(async source => {
    const destination = join(output, source);
    await mkdir(dirname(destination), { recursive: true });
    await copyFile(join(root, source), destination);
  }));
  await writeFile(join(output, "examples.json"), JSON.stringify(examples, null, 2) + "\n");
  return examples;
}
