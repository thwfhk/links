import { copyFile, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, join, posix } from "node:path";

const groups = {
  "Functions and data": {
    "examples/basics.links": "Bindings and functions",
    "examples/factorial.links": "Factorials",
    "examples/church.links": "Church numerals",
    "examples/extensible-case.links": "Extensible pattern matching",
    "examples/paginate.links": "Paginate a word list",
  },
  "Lists and linearity": {
    "examples/met/fresco-effects/list-map-fold.links": "Map and fold over lists",
    "examples/met/fresco-effects/effectful-list.links": "A list of effectful functions",
    "examples/linearList.links": "Linear lists",
  },
  "Polymorphism": {
    "examples/met/fresco-types/rank-two.links": "Rank-two polymorphism",
    "examples/met/fresco-types/application.links": "Apply polymorphic functions",
  },
  "Modules and imports": {
    "examples/handlers/module_import.links": "Import a state handler",
  },
  "Effects and handlers": {
    "examples/met/fresco-effects/single-yield.links": "Single yield",
    "examples/handlers/toggle.links": "Toggle state",
    "examples/handlers/count.links": "Count down with state",
    "examples/met/thesis/print_list.links": "Collect printed values",
    "examples/handlers/coin_composition.links": "Compose coin toss handlers",
    "examples/met/fresco-effects/find_mask_paper.links": "Search with effect handlers",
    "examples/met/thesis/handler_results.links": "Return functions from a handler",
    "examples/met/thesis/yield_state.links": "Yield and update state",
  },
};

const examples = Object.entries(groups).flatMap(([group, entries]) =>
  Object.entries(entries).map(([id, title]) => ({ id, title, group }))
);

const handlerImports = {
  "examples/handlers/module_import.links": ["Shallow_state"],
  "examples/handlers/tests.links": [
    "Shallow_state", "Deep_state", "Pipes", "Exceptions", "Fringe",
    "Light_switch", "Sat", "Pi", "Shiftreset",
  ],
};

const sourceNotes = {
  "prelude.links": "Loaded automatically for each playground request.",
  "lib/comprehension.links": "Provides the helpers for list comprehensions.",
  "examples/TicTacToe-Console.links": "Call playGame with a list of moves to run the game.",
  "examples/handlers/aop.links": "The test functions take an expression to evaluate.",
  "examples/handlers/aop2.links": "The test functions take an expression to evaluate.",
  "examples/handlers/choose.links": "Call a handler with the choice function to see a result.",
  "examples/handlers/concurrency.links": "Pass the test computation to one of the schedulers.",
  "examples/handlers/coop.links": "Pass the test computation to the cooperative scheduler.",
  "examples/handlers/identity.links": "The force handler takes a computation from a caller.",
  "examples/handlers/monadic_reflection.links": "Call runExample() to run the state handler.",
  "examples/handlers/nim.links": "Defines game functions and handlers for a caller.",
  "examples/handlers/number_games.links": "Call example() to play a game with simulated input.",
  "examples/handlers/pi.links": "The test driver's π estimate exceeds the playground timeout.",
  "examples/handlers/tests.links": "The π estimate exceeds the playground timeout.",
  "examples/handlers/transaction.links": "Call example() to simulate the bank transactions.",
  "examples/handlers/u2_puzzle.links": "Defines puzzle and solution functions for a caller.",
  "examples/sierpinski_bits.links": "Call sierpinski() to print the triangle.",
};

async function sourceIds(root) {
  // The repository checks that every tracked example is in this registry.
  // The worker uses the same paths as the source viewer.
  const registry = await readFile(join(root, "tests/typecheck_examples.tests"), "utf8");
  const registered = registry.split(/\r?\n/).filter(line => /^examples\/(?:[\w-]+\/)*[\w-]+\.links$/.test(line));
  const stdlib = await readdir(join(root, "lib/stdlib"), { withFileTypes: true });
  const modules = stdlib.filter(file => file.isFile() && file.name.endsWith(".links"))
    .map(file => "lib/stdlib/" + file.name);
  return [...new Set([...registered, "prelude.links", "lib/comprehension.links", ...modules])].sort();
}

async function catalogue(root) {
  const titles = new Map(examples.map(({ id, title }) => [id, title]));
  const ids = await sourceIds(root);
  const sources = new Map(ids.map(id => {
    const title = titles.get(id) ?? posix.basename(id, ".links")
      .replace(/([a-z])([A-Z])/g, "$1 $2")
      .replace(/[-_]+/g, " ")
      .replace(/^[a-z]/, letter => letter.toUpperCase());
    const diagnostic = id.includes("/rejected/");
    const kind = titles.has(id) ? "runnable" : diagnostic ? "diagnostic" : "source";
    const note = sourceNotes[id] ?? (diagnostic ? "Expected type error." : "");
    return [id, { id, title, kind, note, imports: [], callers: [] }];
  }));
  for (const id of titles.keys()) {
    if (!sources.has(id)) throw new Error("Unregistered runnable example " + id);
  }
  for (const [id, names] of Object.entries(handlerImports)) {
    const source = sources.get(id);
    if (!source) throw new Error("Unregistered importing example " + id);
    for (const name of names) {
      const path = "examples/handlers/" + name[0].toLowerCase() + name.slice(1) + ".links";
      const dependency = sources.get(path);
      if (!dependency) throw new Error(path + " is missing from the source catalogue");
      source.imports.push({ name, id: path });
      dependency.callers.push(id);
    }
  }
  return [...sources.values()];
}

export async function packageExamples(root, output) {
  const sources = await catalogue(root);
  await Promise.all(sources.map(async ({ id }) => {
    const destination = join(output, id);
    await mkdir(dirname(destination), { recursive: true });
    await copyFile(join(root, id), destination);
  }));
  await Promise.all([
    writeFile(join(output, "examples.json"), JSON.stringify(examples, null, 2) + "\n"),
    writeFile(join(output, "sources.json"), JSON.stringify(sources, null, 2) + "\n"),
  ]);
  return examples;
}
