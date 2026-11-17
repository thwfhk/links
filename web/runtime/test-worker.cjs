const assert = require("node:assert/strict");
const { copyFileSync, mkdtempSync, readFileSync, rmSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");
const { test } = require("node:test");
const { Worker } = require("node:worker_threads");

const workerPath = resolve(process.argv[2]);
const runtime = process.argv[3] ?? "javascript";
assert.ok(["javascript", "wasm"].includes(runtime), `Unknown runtime ${runtime}`);

// Adapt the browser message API to Node without changing the worker bundle.
const bootstrap = `
  const { parentPort, workerData } = require("node:worker_threads");
  globalThis.onmessage = null;
  globalThis.postMessage = message => parentPort.postMessage(message);
  parentPort.on("message", data => globalThis.onmessage({ data }));
  require(workerData);
`;

function sendRequest(kind, source, exampleId, scriptPath = workerPath) {
  const worker = new Worker(bootstrap, { eval: true, workerData: scriptPath });
  const output = [];
  return new Promise((resolve, reject) => {
    const finish = () => {
      clearTimeout(timeout);
      void worker.terminate();
    };
    const timeout = setTimeout(() => {
      finish();
      reject(new Error("The worker did not reply."));
    }, 10_000);
    worker.on("error", error => {
      finish();
      reject(error);
    });
    worker.on("message", message => {
      if (message.kind === "ready") {
        worker.postMessage({ kind, id: 1, source, exampleId });
      } else if (message.kind === "output") {
        output.push(message.text);
      } else {
        finish();
        resolve({ ...message, output: output.join("") });
      }
    });
  });
}

test("Check returns the inferred type without evaluating source", async () => {
  const result = await sendRequest("check", '{ print("hello"); 42 }');
  assert.deepEqual(result, { kind: "success", id: 1, inferredType: "Int", output: "" });
});

test("Run reports the result, type and printed output", async () => {
  const result = await sendRequest("run", '{ print("café"); 6 * 7 }');
  assert.deepEqual(result, {
    kind: "success", id: 1, value: "42", inferredType: "Int", output: "café",
  });
});

test("Run preserves floating-point values across worker messages", async () => {
  const result = await sendRequest("run", "1.5 +. 2.25");
  assert.deepEqual(result, {
    kind: "success", id: 1, value: "3.75", inferredType: "Float", output: "",
  });
});

test("Integer bounds and overflow follow the selected runtime", async () => {
  const minimum = runtime === "wasm" ? -1_073_741_824 : -2_147_483_648;
  const maximum = runtime === "wasm" ? 1_073_741_823 : 2_147_483_647;
  const addition = runtime === "wasm" ? minimum : 1_073_741_824;
  const result = await sendRequest("run",
    "(min_int, max_int, max_int + 1, min_int - 1, 1073741823 + 1)");
  assert.equal(result.kind, "success", result.diagnostic);
  assert.equal(result.value,
    `(${minimum}, ${maximum}, ${minimum}, ${maximum}, ${addition})`);
});

test("A missing worker script reports a startup error", async () => {
  await assert.rejects(
    sendRequest("check", "42", undefined, join(workerPath, "missing.js")),
    /Cannot find module|ENOTDIR/);
});

test("The Wasm loader reports missing runtime assets", {
  skip: runtime !== "wasm",
}, async context => {
  const directory = mkdtempSync(join(tmpdir(), "smalllinks-missing-wasm-"));
  context.after(() => rmSync(directory, { recursive: true, force: true }));
  const script = join(directory, "worker-wasm.js");
  copyFileSync(workerPath, script);
  await assert.rejects(sendRequest("check", "42", undefined, script), /ENOENT|no such file/i);
});

test("Run resumes a SmallLinks effect handler", async () => {
  const example = "examples/met/fresco-effects/single-yield.links";
  const result = await sendRequest("run", readFileSync(example, "utf8"), example);
  assert.deepEqual(result, {
    kind: "success", id: 1, value: "1", inferredType: "Int", output: "",
  });
});

test("Run checks higher-rank polymorphism from a bundled example", async () => {
  const example = "examples/met/fresco-types/rank-two.links";
  const result = await sendRequest("run", readFileSync(example, "utf8"), example);
  assert.deepEqual(result, {
    kind: "success", id: 1, output: "",
    value: "(42, 42, (42, true), (), 42, (42, true))",
    inferredType: "(Int, Int, (Int, Bool), (), Int, (Int, Bool))",
  });
});

test("A new program can import the bundled standard library", async () => {
  const result = await sendRequest("run", "import BinaryTree; 42");
  assert.deepEqual(result, {
    kind: "success", id: 1, value: "42", inferredType: "Int", output: "",
  });
});

test("Run imports dependencies of a packaged example", async () => {
  const example = "examples/handlers/tests.links";
  const result = await sendRequest("run", "import Shallow_state; Shallow_state.unitTest(5)", example);
  assert.equal(result.kind, "success", result.diagnostic);
  assert.equal(result.value, "(0, [0, 1, 2, 3, 4])");
});

test("An unavailable import produces a diagnostic", async () => {
  const result = await sendRequest("check", "import Missing; 42");
  assert.equal(result.kind, "failure");
  assert.equal(result.stage, "checking");
  assert.match(result.diagnostic, /Could not find file missing\.links/);
});

test("Imports see the editor version of a packaged entry file", async () => {
  const example = "examples/handlers/tests.links";
  const result = await sendRequest("check", "import Tests; 42", example);
  assert.equal(result.kind, "failure");
  assert.equal(result.stage, "checking");
  assert.match(result.diagnostic, /cyclic dependencies involving Tests/);
});

test("A parse diagnostic includes the example's source name", async () => {
  const example = "examples/factorial.links";
  const result = await sendRequest("check", "var x = ;", example);
  assert.equal(result.kind, "failure");
  assert.equal(result.stage, "parsing");
  assert.ok(result.diagnostic.includes(example), result.diagnostic);
});

test("A type error prevents execution", async () => {
  const result = await sendRequest("run", '{ print("hello"); 1 + true }');
  assert.equal(result.kind, "failure");
  assert.equal(result.stage, "checking");
  assert.equal(result.output, "");
});

test("A host-only operation reports its name and preserves preceding output", async () => {
  const result = await sendRequest("run", '{ print("before"); connectSocket("localhost", 80) }');
  assert.equal(result.kind, "failure");
  assert.equal(result.stage, "running");
  assert.match(result.diagnostic, /connectSocket.*unavailable in the browser/);
  assert.equal(result.output, "before");
});

test("Milliseconds report an unsupported operation in the browser", async () => {
  const result = await sendRequest("run", "serverTimeMilliseconds()");
  assert.equal(result.kind, "failure");
  assert.equal(result.stage, "running");
  assert.match(result.diagnostic, /serverTimeMilliseconds.*unavailable in the browser/);
});

test("Early exit returns its value and preserves preceding output", async () => {
  const result = await sendRequest("run", '{ print("before"); exit(42) }');
  assert.deepEqual(result, { kind: "success", id: 1, value: "42", output: "before" });
});

test("Assertion failure ends the current request with the exit status", async () => {
  const result = await sendRequest("run", "{ assertEq(1, 2); 42 }");
  assert.equal(result.kind, "failure");
  assert.equal(result.stage, "running");
  assert.equal(result.exitStatus, 2);
  assert.match(result.output, /Assertion failed/);
});

test("The worker bounds chunks before sending them to the page", async () => {
  const source = `{ print("before"); print("${"x".repeat(70_000)}"); 42 }`;
  const result = await sendRequest("run", source);
  assert.deepEqual(result, {
    kind: "success", id: 1, value: "42", inferredType: "Int",
    output: "before\n[Output truncated.]\n",
  });
});
