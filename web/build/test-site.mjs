import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { posix, resolve, sep } from "node:path";
import { test } from "node:test";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";
import { EditorView } from "@codemirror/view";
import { JSDOM, VirtualConsole } from "jsdom";

const dist = fileURLToPath(new URL("../dist", import.meta.url));
const root = fileURLToPath(new URL("../../", import.meta.url));
const host = "https://smalllinks.test";
const runtimeScripts = new Map([
  ["javascript", "worker.js"],
  ["webassembly", "worker-wasm.js"],
]);
const basePaths = ["/", "/smalllinks/"];
const runtimeSites = [...runtimeScripts.keys()].flatMap(runtime =>
  basePaths.map(basePath => ({ runtime, basePath })));
const runtimeStorageKey = "smalllinks-runtime";

const basics = "examples/basics.links";
const factorial = "examples/factorial.links";
const application = "examples/met/fresco-types/application.links";
const importExample = "examples/handlers/module_import.links";
const ehop2022 = "examples/handlers/ehop2022.links";
const stateModule = "examples/handlers/shallow_state.links";
const slowExample = "examples/handlers/tests.links";
const coinExample = "examples/handlers/coin_composition.links";
const countdown = "examples/handlers/count.links";
const toggle = "examples/handlers/toggle.links";
const effectfulList = "examples/met/fresco-effects/effectful-list.links";
const searchExample = "examples/met/fresco-effects/find_mask_paper.links";
const handlerResults = "examples/met/thesis/handler_results.links";
const singleYield = "examples/met/fresco-effects/single-yield.links";
const rankTwo = "examples/met/fresco-types/rank-two.links";
const rejectedExample = "examples/met/fresco-effects/rejected/effectful-list-non-value.links";
const quickExamples = [basics, application, toggle, countdown, coinExample, importExample, ehop2022];

const expectedExamples = new Map([
  [basics, "42"],
  ["examples/church.links", "4"],
  ["examples/extensible-case.links", '("A", "B", "C")'],
  [factorial, /\(f = 3628800, i = 10\)\]$/],
  [coinExample, "()"],
  [countdown, "0"],
  [ehop2022,
    '([0, 0], (dir = [("act3", 3), ("hamlet", 2), ("ritchie.txt", 1), ("stdout", 0)], dregion = ' +
    '[(3, "To be, or not to be,\nthat is the question:\nWhether \'tis nobler in the mind to suffer\n"), ' +
    '(2, "To be, or not to be,\nthat is the question:\nWhether \'tis nobler in the mind to suffer\n"), ' +
    '(1, "UNIX is basically a simple operating system, but you have to be a genius to understand the simplicity.\n"), ' +
    '(0, "")], inext = 4, inodes = [(3, (lno = 1, loc = 3)), (2, (lno = 1, loc = 2)), ' +
    '(1, (lno = 1, loc = 1)), (0, (lno = 1, loc = 0))], lnext = 4))'],
  [importExample, "(0, [0, 1, 2, 3, 4])"],
  [toggle, "(true, true)"],
  ["examples/linearList.links", "LinCons(fun, LinNil)"],
  [effectfulList, "[1]"],
  [searchExample, "([1, 2, 3], Just(3), (Just(2), [1, 2]))"],
  ["examples/met/fresco-effects/list-map-fold.links", "([2, 3, 4], 123, 321, [1, 2, 3])"],
  [singleYield, "1"],
  [application,
    "(((42, true), (42, true), (42, true)), ((42, true), (42, true)), ((42, true), (42, true)), " +
    "((42, true), (42, true), (42, true)), ((true, 42), (42, true)), (42, 42))"],
  [rankTwo, "(42, 42, (42, true), (), 42, (42, true))"],
  [handlerResults, '(52, (42, true, "second"))'],
  ["examples/met/thesis/print_list.links", '["digit 3", "digit 1", "digit 4"]'],
  ["examples/met/thesis/yield_state.links", '([42], ["callback"])'],
  ["examples/paginate.links", '[(meaning = "a round fruit", word = "apple"), (meaning = "a stone fruit", word = "apricot")]'],
]);

const guideSnippetValues = [
  '(42, "yes")', "25",
  "42", "42", '(43, "start")', '["Ali", "Kim"]',
  "[12, 22]", "(120, true)", "(42, true)", '(1, "one")',
  "42", expectedExamples.get(importExample),
  "[1, 2]", "1",
  "42", "42", "42", "()", "43", "42", "42",
  "42",
];

const catalogue = JSON.parse(await readFile(resolve(dist, "examples.json"), "utf8"));
const sourceCatalogue = JSON.parse(await readFile(resolve(dist, "sources.json"), "utf8"));
const sources = new Map(sourceCatalogue.map(source => [source.id, source]));

// Run unmodified classic workers with browser globals and local HTTP asset paths.
const workerBootstrap = `
  const assert = require("node:assert/strict");
  const { readFileSync } = require("node:fs");
  const { readFile } = require("node:fs/promises");
  const { resolve, sep } = require("node:path");
  const { createContext, runInContext } = require("node:vm");
  const { parentPort, workerData } = require("node:worker_threads");
  const base = new URL(workerData.baseUrl);
  const listeners = new Map();
  function dispatchEvent(event) {
    const handler = context["on" + event.type];
    if (typeof handler === "function") handler.call(context, event);
    for (const listener of listeners.get(event.type) ?? []) listener.call(context, event);
    return !event.defaultPrevented;
  }
  function assetPath(href) {
    const url = new URL(href, workerData.url);
    assert.equal(url.origin, base.origin, "Worker asset origin");
    assert.ok(url.pathname.startsWith(base.pathname), "Worker asset base path: " + url.href);
    const path = resolve(workerData.dist, decodeURIComponent(url.pathname.slice(base.pathname.length)));
    assert.ok(path.startsWith(workerData.dist + sep), "Worker asset stays in the static build");
    return { path, url };
  }
  const context = createContext({
    console, URL, TextDecoder, TextEncoder, Response, Blob, atob, btoa, performance, crypto,
    setTimeout, clearTimeout, setInterval, clearInterval, queueMicrotask,
    location: new URL(workerData.url),
    navigator: { userAgent: "SmallLinks Node site tests" },
    onmessage: null,
    addEventListener: (type, listener) => {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(listener);
    },
    removeEventListener: (type, listener) => listeners.get(type)?.delete(listener),
    dispatchEvent,
    postMessage: message => parentPort.postMessage(message),
    fetch: async href => {
      const { path, url } = assetPath(href);
      parentPort.postMessage({ kind: "test-asset-request", url: url.href });
      if (workerData.failure?.kind === "missing-asset") {
        return new Response("Missing runtime asset", { status: 404 });
      }
      return new Response(await readFile(path), { headers: { "Content-Type": "application/wasm" } });
    },
  });
  context.self = context;
  context.importScripts = (...hrefs) => {
    for (const href of hrefs) {
      const { path, url } = assetPath(href);
      parentPort.postMessage({ kind: "test-asset-request", url: url.href });
      runInContext(readFileSync(path, "utf8"), context, { filename: url.href });
    }
  };
  if (workerData.failure?.kind === "unsupported-webassembly") {
    runInContext("globalThis.WebAssembly = undefined", context);
  }
  parentPort.on("message", data => dispatchEvent({ type: "message", data }));
  // Browsers dispatch unhandledrejection without turning it into Worker.onerror.
  process.on("unhandledRejection", (reason, promise) => dispatchEvent({
    type: "unhandledrejection", reason, promise, cancelable: true, defaultPrevented: false,
    preventDefault() { this.defaultPrevented = true; },
  }));
  if (workerData.failure?.kind === "missing-worker") {
    throw new Error("HTTP 404 loading " + workerData.url);
  }
  runInContext(readFileSync(assetPath(workerData.url).path, "utf8"), context, { filename: workerData.url });
`;

function openSite(basePath, { runtime = null, storageFailure = false } = {}) {
  const workers = new Set();
  const workerRequests = [];
  const workerFailures = [];
  const pages = [];
  const errors = [];
  let sessionStorage;
  const virtualConsole = new VirtualConsole();
  virtualConsole.on("jsdomError", error => errors.push(error));

  function assetPath(url) {
    assert.equal(url.origin, host, `Off-site request for ${url}`);
    assert.ok(url.pathname.startsWith(basePath), `Request outside ${basePath}: ${url}`);
    const path = resolve(dist, decodeURIComponent(url.pathname.slice(basePath.length)) || "index.html");
    assert.ok(path.startsWith(dist + sep), `Request outside the static build: ${url}`);
    return path;
  }

  async function loadPage(href = basePath) {
    const url = new URL(href, host);
    const html = await readFile(assetPath(url), "utf8");
    const { window } = new JSDOM(html, { url, virtualConsole, runScripts: "outside-only", pretendToBeVisual: true });
    pages.push(window);

    // Page loads share one browsing session, including visits to the guide.
    if (storageFailure) {
      Object.defineProperty(window, "sessionStorage", {
        get() { throw new window.DOMException("Storage is unavailable.", "SecurityError"); },
      });
    } else {
      if (!sessionStorage) {
        sessionStorage = window.sessionStorage;
        if (runtime !== null) sessionStorage.setItem(runtimeStorageKey, runtime);
      }
      Object.defineProperty(window, "sessionStorage", { value: sessionStorage });
    }

    // jsdom returns no layout boxes for elements and lacks the equivalent Range method.
    window.Range.prototype.getClientRects ??= () => [];

    window.fetch = async (href, { signal } = {}) => {
      const path = assetPath(new URL(href, url));
      return new Response(await readFile(path, { signal }));
    };
    window.Worker = class extends window.EventTarget {
      constructor(href, options) {
        super();
        const workerUrl = new URL(href, url);
        assetPath(workerUrl);
        assert.equal(workerUrl.href, new URL(runtimeScripts.get(window.document.getElementById("runtime").value),
          host + basePath).href, "The selected runtime uses its local worker");
        assert.ok(!options?.type || options.type === "classic", "Both runtimes use classic workers");
        this.request = { url: workerUrl.href, messages: [], assets: [], terminated: false };
        workerRequests.push(this.request);
        const failure = workerFailures.shift();
        if (failure?.kind === "constructor") throw new Error(failure.diagnostic);
        if (failure && ["error", "startup", "messageerror"].includes(failure.kind)) {
          queueMicrotask(() => {
            if (this.request.terminated) return;
            if (failure.kind === "startup") {
              this.dispatchEvent(new window.MessageEvent("message", {
                data: { kind: "failure", stage: "startup", diagnostic: failure.diagnostic },
              }));
            } else if (failure.kind === "messageerror") {
              this.dispatchEvent(new window.MessageEvent("messageerror"));
            } else {
              this.dispatchEvent(new window.ErrorEvent("error", {
                message: failure.diagnostic, cancelable: true,
              }));
            }
          });
          return;
        }
        this.worker = new Worker(workerBootstrap, {
          eval: true,
          workerData: { dist, baseUrl: host + basePath, url: workerUrl.href, failure },
        });
        workers.add(this.worker);
        this.worker.once("exit", () => workers.delete(this.worker));
        this.worker.on("message", data => {
          if (data.kind === "test-asset-request") this.request.assets.push(data.url);
          else this.dispatchEvent(new window.MessageEvent("message", { data }));
        });
        this.worker.on("error", error => this.dispatchEvent(new window.ErrorEvent("error", {
          message: error.message,
          cancelable: true,
        })));
      }

      postMessage(message) {
        this.request.messages.push(message);
        this.worker?.postMessage(message);
      }
      terminate() {
        this.request.terminated = true;
        void this.worker?.terminate();
      }
    };

    const document = window.document;
    for (const stylesheet of document.querySelectorAll('link[rel="stylesheet"][href]')) {
      await readFile(assetPath(new URL(stylesheet.href)));
    }
    for (const script of document.querySelectorAll('script[type="module"][src]')) {
      // The built app is a self-contained bundle. jsdom leaves module scripts unevaluated.
      window.eval(await readFile(assetPath(new URL(script.src)), "utf8"));
    }
    return window;
  }

  async function close() {
    await Promise.all([...workers].map(worker => worker.terminate()));
    for (const window of pages) {
      editorView(window.document)?.destroy();
      window.close();
    }
    assert.deepEqual(errors, [], "Errors reported by the in-memory DOM");
  }

  return {
    loadPage, close, workerRequests,
    activeWorkers: () => workers.size,
    failNextWorker: failure => workerFailures.push(failure),
  };
}

async function waitFor(read, expected, label) {
  const matches = value => expected instanceof RegExp ? expected.test(value ?? "") : value === expected;
  const deadline = Date.now() + 10_000;
  let actual = read();
  while (!matches(actual) && Date.now() < deadline) {
    await delay(15);
    actual = read();
  }
  assert.ok(matches(actual), `${label}: expected ${expected}, got ${JSON.stringify(actual)}`);
}

function expectText(document, id, value) {
  const element = document.getElementById(id);
  return waitFor(() => element?.closest("[hidden]") ? null : element?.textContent, value, id);
}

function editorView(document) {
  const editor = document.querySelector(".cm-editor");
  return editor && EditorView.findFromDOM(editor);
}

function getSource(document) {
  return editorView(document)?.state.doc.toString() ?? document.getElementById("source").value;
}

function editSource(window, source) {
  const document = window.document;
  const view = editorView(document);
  if (view) {
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: source } });
  } else {
    const textarea = document.getElementById("source");
    textarea.value = source;
    textarea.dispatchEvent(new window.Event("input", { bubbles: true }));
  }
}

function chooseRuntime(window, runtime) {
  const select = window.document.getElementById("runtime");
  assert.equal(select.disabled, false, "Runtime is available");
  select.value = runtime;
  select.dispatchEvent(new window.Event("change", { bubbles: true }));
  assert.equal(select.value, runtime);
}

function unavailable(button) {
  return button.disabled || Boolean(button.closest("[hidden]"));
}

async function expectEditable(document) {
  await expectText(document, "editor-mode", "Editable");
  await waitFor(() => unavailable(document.getElementById("check")), false, "Check is available");
  assert.ok(!unavailable(document.getElementById("run")), "Run is available");
  const view = editorView(document);
  assert.ok(view, "The highlighted editor did not load");
  assert.equal(view.state.readOnly, false);
  assert.equal(view.contentDOM.getAttribute("contenteditable"), "true");
  assert.equal(document.getElementById("runtime").disabled, false, "Runtime is available while editing");
}

async function expectLoadedExample(document, id) {
  const source = await readFile(resolve(root, id), "utf8");
  await waitFor(() => getSource(document), source, id);
  await expectEditable(document);
}

function linksTo(element, page, parameter, id) {
  return [...element.querySelectorAll("a[href]")].filter(link => {
    const url = new URL(link.href);
    return url.pathname.endsWith(`/${page}`) &&
      (!parameter || (id ? url.searchParams.get(parameter) === id : url.searchParams.has(parameter)));
  });
}

function requireLink(element, page, parameter, id) {
  const link = linksTo(element, page, parameter, id)[0];
  assert.ok(link, `Missing link to ${page}${id ? ` for ${id}` : ""}`);
  assert.ok(link.getAttribute("aria-label")?.trim() || link.textContent.trim(), `Unnamed link to ${link.href}`);
  return link;
}

async function expectSourcePreview(document, id) {
  const { note } = sources.get(id);
  const source = await readFile(resolve(root, id), "utf8");
  await waitFor(() => getSource(document), source, id);
  await expectText(document, "editor-mode", "Read-only");
  const context = document.getElementById("example-context");
  assert.ok(!context.closest("[hidden]"), `Missing file context for ${id}`);
  assert.equal(requireLink(context, "index.html", "file", id).id, "example-source");
  if (note) await expectText(document, "example-note", note);
  assert.equal(document.querySelectorAll(".cm-editor").length, 1, "Preview uses the shared editor");
  const view = editorView(document);
  assert.equal(view.state.readOnly, true);
  assert.equal(view.contentDOM.getAttribute("contenteditable"), "false");
  assert.ok(unavailable(document.getElementById("check")), "Check is unavailable during preview");
  assert.ok(unavailable(document.getElementById("run")), "Run is unavailable during preview");
  assert.ok(!unavailable(document.getElementById("load-source")), `Can load ${id} into the editor`);
  assert.equal(document.getElementById("runtime").disabled, false, "Runtime is available in source previews");
}

function containingDirectories(link) {
  const directories = [];
  for (let directory = link.closest("details"); directory;
    directory = directory.parentElement.closest("details")) {
    directories.push(directory);
  }
  return directories.reverse();
}

function followPreview(element, id) {
  const link = requireLink(element, "index.html", "file", id);
  assert.ok(["", "_self"].includes(link.target), `Preview should open in place for ${id}`);
  for (const directory of containingDirectories(link)) {
    if (!directory.open) directory.querySelector(":scope > summary").click();
    assert.ok(directory.open, `Cannot open the directory for ${id}`);
  }
  link.click();
  return link;
}

async function run(document, value) {
  const button = document.getElementById("run");
  assert.ok(!button.disabled, "Run is disabled");
  button.click();
  assert.equal(document.getElementById("runtime").disabled, true, "Runtime is disabled during Run");
  await waitFor(() => button.disabled, false, "Run finished");
  const diagnostic = document.getElementById("diagnostic").textContent;
  assert.equal(document.getElementById("request-status").textContent, "Run complete.", diagnostic);
  const result = document.getElementById("value");
  assert.ok(!result.closest("[hidden]"), "Run returned no value");
  if (value instanceof RegExp) assert.match(result.textContent, value);
  else assert.equal(result.textContent, value);
  assert.equal(document.getElementById("runtime").disabled, false, "Runtime is available after Run");
}

test("Package repository sources and their catalogue entries", async () => {
  for (const script of runtimeScripts.values()) {
    assert.ok((await readFile(resolve(dist, script))).length > 0, `Missing runtime worker ${script}`);
  }
  const wasmAssets = await readdir(resolve(dist, "worker-wasm.assets"), { recursive: true });
  assert.ok(wasmAssets.some(path => path.endsWith(".wasm")), "Missing WebAssembly modules");
  for (const oldPage of ["sources.html", "sources.js"]) {
    await assert.rejects(readFile(resolve(dist, oldPage)), { code: "ENOENT" });
  }
  assert.equal(sources.size, sourceCatalogue.length, "Duplicate source catalogue entries");
  const exampleIds = new Set(catalogue.map(({ id }) => id));
  assert.equal(exampleIds.size, catalogue.length, "Duplicate runnable catalogue entries");
  assert.deepEqual([...exampleIds].sort(), [...expectedExamples.keys()].sort());
  for (const { id, title, group } of catalogue) {
    assert.equal(sources.get(id)?.kind, "runnable", id);
    assert.ok(title?.trim(), `Missing title for ${id}`);
    assert.ok(group?.trim(), `Missing group for ${id}`);
  }
  for (const { id, title, kind, note, imports, callers } of sourceCatalogue) {
    assert.match(id, /^(?:(?:examples|lib)\/.+|prelude)\.links$/);
    assert.ok(title?.trim(), `Missing title for ${id}`);
    assert.ok(["runnable", "source", "diagnostic"].includes(kind), `Unknown source kind ${kind} for ${id}`);
    assert.equal(typeof note, "string", `Missing note field for ${id}`);
    if (kind === "runnable") {
      assert.ok(exampleIds.has(id), `Missing runnable catalogue entry for ${id}`);
    }
    for (const { name, id: target } of imports) {
      assert.ok(name?.trim(), `Missing import name in ${id}`);
      assert.ok(sources.has(target), `Missing import ${target} from ${id}`);
    }
    for (const caller of callers) {
      assert.ok(sources.has(caller), `Missing caller ${caller} of ${id}`);
    }
    assert.deepEqual(await readFile(resolve(dist, id)), await readFile(resolve(root, id)), id);
  }
  assert.ok(sources.has("prelude.links"), "Missing prelude");
  assert.ok(sources.has("lib/comprehension.links"), "Missing comprehension helpers");
  assert.ok(sources.has("lib/stdlib/binaryTree.links"), "Missing standard library module");
  assert.deepEqual(sources.get(importExample).imports, [{ name: "Shallow_state", id: stateModule }]);
  assert.ok(sources.get(stateModule)?.callers.includes(importExample), "Missing caller of Shallow_state");
  assert.equal(sources.get(stateModule).kind, "source");
  assert.equal(sources.get(slowExample)?.kind, "source");
  assert.equal(sources.get(rejectedExample)?.kind, "diagnostic");
});

for (const basePath of basePaths) {
  test(`Change runtime while retaining source, results and navigation at ${basePath}`, async () => {
    const site = openSite(basePath);
    try {
      const window = await site.loadPage(`${basePath}?example=${encodeURIComponent(importExample)}`);
      const document = window.document;
      await expectLoadedExample(document, importExample);
      const runtimeSelect = document.getElementById("runtime");
      assert.equal(document.querySelector('label[for="runtime"]').textContent.trim(), "Runtime");
      assert.deepEqual([...runtimeSelect.options].map(option => [option.value, option.textContent.trim()]),
        [["javascript", "JavaScript"], ["webassembly", "WebAssembly"]]);
      assert.equal(runtimeSelect.value, "javascript", "JavaScript is initially selected");

      const edited = 'import Shallow_state;\n{ print("retained output"); Shallow_state.unitTest(3) }';
      editSource(window, edited);
      const view = editorView(document);
      const anchor = edited.lastIndexOf("Shallow_state");
      const head = anchor + "Shallow_state".length;
      view.dispatch({ selection: { anchor, head } });
      await run(document, "(0, [0, 1, 2])");
      const results = document.getElementById("results").innerHTML;
      const context = document.getElementById("example-context").innerHTML;
      const href = window.location.href;
      const workerCount = site.workerRequests.length;
      chooseRuntime(window, "webassembly");
      assert.equal(window.sessionStorage.getItem(runtimeStorageKey), "webassembly");
      assert.equal(getSource(document), edited);
      assert.equal(view.state.selection.main.anchor, anchor);
      assert.equal(view.state.selection.main.head, head);
      assert.equal(document.getElementById("example-context").innerHTML, context);
      assert.equal(document.getElementById("results").innerHTML, results);
      assert.equal(window.location.href, href);
      assert.equal(site.workerRequests.length, workerCount, "Choosing a runtime starts no worker");
      await run(document, "(0, [0, 1, 2])");
      assert.equal(site.workerRequests.at(-1).url, host + basePath + "worker-wasm.js");
      assert.equal(site.workerRequests.at(-1).messages[0].exampleId, importExample);

      // The selector stays available while a source is loading and in a preview.
      const fetch = window.fetch;
      let releaseSource;
      const sourceGate = new Promise(resolve => { releaseSource = resolve; });
      window.fetch = async (href, options) => {
        if (new URL(href, window.location.href).pathname.endsWith(stateModule)) await sourceGate;
        return fetch(href, options);
      };
      followPreview(document.getElementById("example-imports"), stateModule);
      assert.equal(runtimeSelect.disabled, false, "Runtime is available while loading source");
      releaseSource();
      await expectSourcePreview(document, stateModule);
      chooseRuntime(window, "javascript");
      await expectSourcePreview(document, stateModule);
      document.getElementById("return-to-editor").click();
      await expectEditable(document);
      assert.equal(getSource(document), edited);
      assert.equal(view.state.selection.main.anchor, anchor);
      assert.equal(view.state.selection.main.head, head);
      await expectText(document, "output", "retained output");
      await run(document, "(0, [0, 1, 2])");
      assert.equal(site.workerRequests.at(-1).url, host + basePath + "worker.js");
      assert.equal(site.workerRequests.at(-1).messages[0].exampleId, importExample);

      chooseRuntime(window, "webassembly");
      document.querySelector(`button[data-example-id="${basics}"]`).click();
      await expectLoadedExample(document, basics);
      assert.equal(runtimeSelect.value, "webassembly", "Examples retain the chosen runtime");
      const guide = (await site.loadPage(requireLink(document, "guide.html").href)).document;
      const home = (await site.loadPage(requireLink(guide.querySelector("header"), "index.html").href)).document;
      await expectEditable(home);
      assert.equal(home.getElementById("runtime").value, "webassembly");
      await run(home, "3");
      assert.equal(site.workerRequests.at(-1).url, host + basePath + "worker-wasm.js");
    } finally {
      await site.close();
    }
  });

  test(`Use the runtime selector when session storage is unavailable at ${basePath}`, async () => {
    const site = openSite(basePath, { storageFailure: true });
    try {
      const window = await site.loadPage();
      await expectEditable(window.document);
      assert.equal(window.document.getElementById("runtime").value, "javascript");
      chooseRuntime(window, "webassembly");
      await run(window.document, "3");
      chooseRuntime(window, "javascript");
      await run(window.document, "3");
    } finally {
      await site.close();
    }
  });
}

for (const { runtime, basePath } of runtimeSites) {
  test(`Recover from worker startup failures with ${runtime} at ${basePath}`, async () => {
    const site = openSite(basePath, { runtime });
    try {
      const window = await site.loadPage(`${basePath}?example=${encodeURIComponent(importExample)}`);
      const document = window.document;
      await expectLoadedExample(document, importExample);
      const source = "import Shallow_state; Shallow_state.unitTest(2)";
      editSource(window, source);
      const failures = [
        { kind: "constructor", diagnostic: "Could not construct the runtime worker." },
        { kind: "error", diagnostic: "The runtime worker script could not be loaded." },
        { kind: "missing-worker", diagnostic: new RegExp(`HTTP 404 loading ${host}${basePath}`) },
        { kind: "startup", diagnostic: "The runtime loader could not load its module." },
        { kind: "messageerror", diagnostic: /could not communicate with the worker/ },
      ];
      if (runtime === "webassembly") {
        failures.push(
          { kind: "missing-asset", diagnostic: /404|Missing runtime asset|response.*status|MIME type/i },
          { kind: "unsupported-webassembly", diagnostic: /WebAssembly|undefined|unavailable|unsupported/i },
        );
      }
      for (const failure of failures) {
        site.failNextWorker(failure);
        document.getElementById("run").click();
        await waitFor(() => document.getElementById("request-status").textContent,
          "Worker startup failed.", `${failure.kind} startup status`);
        await expectText(document, "diagnostic", failure.diagnostic);
        assert.equal(getSource(document), source);
        assert.equal(document.getElementById("runtime").disabled, false);
        assert.equal(document.getElementById("runtime").value, runtime);
        assert.equal(site.workerRequests.at(-1).messages.length, 0,
          "No source is sent to a worker that failed before ready");
        if (failure.kind === "missing-asset") {
          assert.ok(site.workerRequests.at(-1).assets.some(href =>
            href.startsWith(host + basePath + "worker-wasm.assets/") && href.endsWith(".wasm")),
          "The actual loader requested the missing Wasm module");
        }
        if (["missing-asset", "unsupported-webassembly"].includes(failure.kind)) {
          chooseRuntime(window, "javascript");
          await run(document, "(0, [0, 1])");
          chooseRuntime(window, runtime);
        }
        await run(document, "(0, [0, 1])");
        assert.equal(site.workerRequests.at(-1).messages[0].exampleId, importExample);
        assert.equal(site.workerRequests.at(-1).messages[0].source, source);
        assert.equal(site.workerRequests.at(-1).terminated, true);
      }
    } finally {
      await site.close();
    }
  });
}

for (const { runtime, basePath } of runtimeSites) {
  test(`Check and run source and the published examples with ${runtime} at ${basePath}`, async () => {
    const site = openSite(basePath, { runtime });
    try {
      const window = await site.loadPage();
      const document = window.document;
      const check = document.getElementById("check");
      const runButton = document.getElementById("run");
      const stop = document.getElementById("stop");
      const examples = document.getElementById("example-list");
      const newProgram = document.getElementById("new-program");
      const runtimeSelect = document.getElementById("runtime");
      assert.equal(runtimeSelect.value, runtime);
      assert.equal(check.textContent.trim(), "Check");
      assert.equal(runButton.textContent.trim(), "Run");
      assert.equal(stop.textContent.trim(), "Stop");
      assert.equal(newProgram.textContent.trim(), "New program");
      assert.equal(document.getElementById("examples-heading").textContent.trim(), "Examples");
      const buttons = () => [...examples.querySelectorAll("button[data-example-id]")];
      await waitFor(() => buttons().length, quickExamples.length, "Quick example count");
      const byId = new Map(buttons().map(button => [button.dataset.exampleId, button]));
      assert.deepEqual([...byId.keys()], quickExamples);

      const files = document.getElementById("source-files");
      await waitFor(() => linksTo(files, "index.html", "file").length, sources.size, "File browser");
      assert.equal(files.querySelectorAll("details[open]").length, 0, "File folders start collapsed");
      await expectEditable(document);
      const starter = getSource(document);

      editSource(window, '{ print("hello from SmallLinks"); 6 * 7 }');
      check.click();
      assert.equal(runtimeSelect.disabled, true, "Runtime is disabled during Check");
      await expectText(document, "inferred-type", "Int");
      assert.equal(runtimeSelect.disabled, false, "Runtime is available after Check");
      assert.ok(document.getElementById("value").closest("[hidden]"));
      assert.ok(document.getElementById("output").closest("[hidden]"));
      await run(document, "42");
      await expectText(document, "output", "hello from SmallLinks");
      editSource(window, '{ print("café λ"); exit(42) }');
      await run(document, "42");
      await expectText(document, "output", "café λ");
      editSource(window, "1073741823 + 1");
      await run(document, runtime === "webassembly" ? "-1073741824" : "1073741824");

      for (const id of quickExamples) {
        const button = byId.get(id);
        assert.ok(button.textContent.trim(), `Unnamed shortcut for ${id}`);
        button.click();
        await expectLoadedExample(document, id);
        await run(document, expectedExamples.get(id));
      }

      for (const { id } of catalogue) {
        followPreview(files, id);
        await expectSourcePreview(document, id);
        document.getElementById("load-source").click();
        await expectLoadedExample(document, id);
        await run(document, expectedExamples.get(id));
        if (id === coinExample) await expectText(document, "output", "[[Heads],[Tails],[]]\n[]\n");
      }

      newProgram.click();
      await expectEditable(document);
      assert.equal(getSource(document), starter);

      editSource(window, "{ var x = 1; x + true }");
      check.click();
      await expectText(document, "diagnostic", /Type error: Expected Int, got Bool/);
      assert.equal(runtimeSelect.disabled, false, "Runtime is available after a type error");

      editSource(window, '{ print("before the error"); connectSocket("localhost", 80) }');
      runButton.click();
      await expectText(document, "diagnostic", /connectSocket is unavailable in the browser/);
      await expectText(document, "output", "before the error");
      assert.equal(runtimeSelect.disabled, false, "Runtime is available after a runtime error");

      // The evaluator pauses and resumes before this sum completes.
      editSource(window, "fun sum(n, acc) { if (n == 0) acc else sum(n - 1, acc + n) } sum(10000, 0)");
      await run(document, "50005000");

      const loop = 'fun loop(n) { loop(n + 1) } { print("loop started"); loop(0) }';
      editSource(window, loop);
      runButton.click();
      await expectText(document, "output", "loop started");
      assert.ok(runButton.disabled);
      stop.click();
      await expectText(document, "request-status", /stopped/i);
      await waitFor(site.activeWorkers, 0, "Stopped worker terminated");
      await expectText(document, "output", "loop started");
      assert.equal(getSource(document), loop);
      assert.equal(runtimeSelect.disabled, false, "Runtime is available after Stop");
      editSource(window, "loop(0)");
      check.click();
      await expectText(document, "diagnostic", /loop/);
      editSource(window, loop);

      // Advance the page's timer once the real worker starts the loop.
      const schedule = window.setTimeout;
      let expire;
      window.setTimeout = (callback, milliseconds) => {
        expire = callback;
        return schedule(callback, milliseconds);
      };
      try {
        runButton.click();
      } finally {
        window.setTimeout = schedule;
      }
      await expectText(document, "output", "loop started");
      expire();
      await expectText(document, "request-status", /timed out/i);
      await waitFor(site.activeWorkers, 0, "Timed-out worker terminated");
      await expectText(document, "output", "loop started");
      assert.equal(getSource(document), loop);
      assert.equal(runtimeSelect.disabled, false, "Runtime is available after timeout");

      editSource(window, "loop(0)");
      check.click();
      await expectText(document, "diagnostic", /loop/);
      editSource(window, "length([1, 2, 3])");
      await run(document, "3");
      assert.ok(document.getElementById("output").closest("[hidden]"));
      assert.ok(document.getElementById("diagnostic").closest("[hidden]"));
      assert.ok(site.workerRequests.length > 0);
      for (const request of site.workerRequests) {
        assert.equal(request.url, host + basePath + runtimeScripts.get(runtime));
        assert.equal(request.messages.length, 1, "Each fresh worker receives one request");
        assert.equal(request.terminated, true, "Each finished worker is terminated");
        if (runtime === "webassembly") {
          assert.ok(request.assets.some(href => href.endsWith(".wasm")), "The worker loaded its Wasm module");
          for (const href of request.assets) {
            assert.ok(href.startsWith(host + basePath + "worker-wasm.assets/"),
              `Runtime asset uses the site's origin and base path: ${href}`);
          }
        }
      }
    } finally {
      await site.close();
    }
  });
}

function checkHighlighting(window) {
  const editor = window.document.querySelector(".cm-content");
  assert.ok(editor, "The highlighted editor did not load");
  assert.equal(editor.getAttribute("aria-label"), "Source");
  const highlightTokens = () => [...editor.querySelectorAll(".cm-line span[class]")].map(token => token.textContent);
  assert.ok(highlightTokens().includes("effect"), "The effect keyword has no highlight class");
  assert.ok(highlightTokens().some(token => token.startsWith("# Use a second operation")),
    "The comment has no highlight class");
  const literal = String.raw`"say \"hello\" #"`;
  editSource(window, `{ print(${literal}); 42 }`);
  assert.ok(highlightTokens().includes(literal), "The escaped string has no highlight class");

  editSource(window, [
    "effect Tick { Tick : () => (); }",
    "sig hold : [] ((<> (() -> Int)) -> (() -> Int))",
    "fun hold(f) { handle({ do Tick; (f : <Tick |> (() -> Int)) }) { case <Tick => k> -> k(()) } }",
    "var xs = [] : List ([Tick] Int);",
    "switch([]) { case xs : List Int -> [] };",
    "(1 < 2, 1 <> 2, Left < Right > End)",
  ].join("\n"));
  const modalities = [...editor.querySelectorAll(".cm-smalllinks-modality")];
  assert.deepEqual(modalities.map(token => token.textContent), ["[]", "<>", "<Tick |>", "[Tick]"]);
}

for (const { runtime, basePath } of runtimeSites) {
  test(`Follow repository sources and retain the editor with ${runtime} at ${basePath}`, async () => {
    const site = openSite(basePath, { runtime });
    try {
      const window = await site.loadPage(`${basePath}?example=${encodeURIComponent(importExample)}`);
      const document = window.document;
      await expectLoadedExample(document, importExample);
      assert.equal(document.getElementById("runtime").value, runtime);
      const original = getSource(document);
      const edited = "import Shallow_state;\nShallow_state.unitTest(3)";
      editSource(window, edited);
      const view = editorView(document);
      const anchor = edited.lastIndexOf("Shallow_state");
      const head = anchor + "Shallow_state".length;
      view.dispatch({ selection: { anchor, head } });
      await run(document, "(0, [0, 1, 2])");
      const atFiles = new Promise(resolve => window.addEventListener("hashchange", resolve, { once: true }));
      window.location.hash = "files";
      await atFiles;
      assert.equal(getSource(document), edited, "Jumping to Files keeps the edited program");

      const context = document.getElementById("example-context");
      const imports = document.getElementById("example-imports");
      assert.equal(requireLink(imports, "index.html", "file", stateModule).textContent.trim(), "Shallow_state");
      assert.ok(!context.closest("[hidden]"));
      followPreview(context, importExample);
      await expectSourcePreview(document, importExample);
      window.history.back();
      await expectEditable(document);
      assert.equal(getSource(document), edited, "Back from a preview restores the draft");
      window.history.forward();
      await expectSourcePreview(document, importExample);
      requireLink(imports, "index.html", "file", stateModule).focus();
      followPreview(imports, stateModule);
      await expectSourcePreview(document, stateModule);
      assert.equal(document.activeElement, view.contentDOM, "Following an import moves focus into the preview");
      assert.ok(document.getElementById("example-note").hidden, "No generic note for the imported module");
      assert.ok(!document.getElementById("example-caller-row").hidden);
      followPreview(document.getElementById("example-callers"), importExample);
      await expectSourcePreview(document, importExample);
      assert.equal(editorView(document), view, "The app uses the same editor for each preview");

      document.getElementById("return-to-editor").click();
      await expectEditable(document);
      assert.equal(getSource(document), edited);
      assert.equal(view.state.selection.main.anchor, anchor);
      assert.equal(view.state.selection.main.head, head);
      await expectText(document, "value", "(0, [0, 1, 2])");
      await run(document, "(0, [0, 1, 2])");
      const mac = /Mac/.test(window.navigator.platform);
      view.contentDOM.dispatchEvent(new window.KeyboardEvent("keydown", {
        key: "z", code: "KeyZ", keyCode: 90, ctrlKey: !mac, metaKey: mac, bubbles: true, cancelable: true,
      }));
      assert.equal(getSource(document), original, "The restored editor retains its undo history");

      const files = document.getElementById("source-files");
      assert.ok(files.closest(".site-sidebar"), "The file browser is in the sidebar");
      assert.ok(!files.closest("[hidden]"), "The file browser is visible");
      const fileLinks = linksTo(files, "index.html", "file");
      assert.deepEqual(fileLinks.map(link => new URL(link.href).searchParams.get("file")).sort(),
        [...sources.keys()].sort());
      for (const link of fileLinks) {
        const id = new URL(link.href).searchParams.get("file");
        const folder = posix.dirname(id)
          .replace(/^examples\/met\/thesis(?=\/|$)/, "examples/met-thesis")
          .replace(/^examples\/met(?=\/|$)/, "examples");
        const expected = id === "prelude.links" ? ["prelude"] : folder.split("/");
        assert.deepEqual(containingDirectories(link).map(directory =>
          directory.querySelector(":scope > summary").textContent.trim()), expected, id);
        assert.equal(link.textContent.trim(), posix.basename(id));
      }

      const selected = followPreview(files, slowExample);
      await expectSourcePreview(document, slowExample);
      assert.equal(selected.getAttribute("aria-current"), "page");
      await expectText(document, "example-note", /time limit|timed out|timeout/i);

      followPreview(files, "prelude.links");
      await expectSourcePreview(document, "prelude.links");
      document.getElementById("load-source").click();
      await expectLoadedExample(document, "prelude.links");
      editSource(window, "length([1, 2, 3])");
      await run(document, "3");

      const rejectedLink = followPreview(files, rejectedExample);
      await expectSourcePreview(document, rejectedExample);
      document.getElementById("load-source").click();
      await expectLoadedExample(document, rejectedExample);
      await expectText(document, "example-diagnostic", /diagnostic/i);
      document.getElementById("check").click();
      await expectText(document, "diagnostic", /Modal introduction requires a value/);
      assert.ok(document.getElementById("diagnostic").textContent.includes(rejectedExample));
      assert.deepEqual(linksTo(document, "sources.html"), [], "No link to the standalone sources page");

      const direct = (await site.loadPage(rejectedLink.href)).document;
      await expectSourcePreview(direct, rejectedExample);
      assert.equal(direct.getElementById("runtime").value, runtime, "Direct source links retain the runtime");
      const directLink = requireLink(direct.getElementById("source-files"), "index.html", "file", rejectedExample);
      assert.equal(directLink.getAttribute("aria-current"), "page");
      assert.equal(directLink.closest("details:not([open])"), null, "A direct preview opens every containing folder");
    } finally {
      await site.close();
    }
  });

  test(`Follow chapter navigation and run the guide's examples with ${runtime} at ${basePath}`, async () => {
    const site = openSite(basePath, { runtime });
    try {
      const { document } = await site.loadPage();
      const guideLink = requireLink(document, "guide.html");
      assert.equal(guideLink.textContent.trim(), "Language guide");
      const guide = (await site.loadPage(guideLink.href)).document;
      assert.equal(guide.querySelector("h1").textContent, "SmallLinks language guide");
      for (const page of [document, guide]) {
        assert.ok(page.querySelector('header a[href="https://github.com/thwfhk/links/tree/small-met"]'),
          "Missing SmallLinks GitHub link");
      }
      assert.ok(guide.querySelector('main a[href="https://links-lang.org/"]'), "Missing Links website link");
      assert.ok(guide.querySelector('main a[href="https://dl.acm.org/doi/10.1145/3720476"]'),
        "Missing modal effect types paper link");
      assert.equal(guide.querySelector('link[rel="stylesheet"]').href,
        document.querySelector('link[rel="stylesheet"]').href, "Playground and guide share their layout stylesheet");
      const chapters = guide.querySelector('nav[aria-labelledby="chapter-nav-title"]');
      assert.ok(chapters.closest(".site-sidebar"), "Guide chapters are in the sidebar");
      assert.equal(guide.getElementById(chapters.getAttribute("aria-labelledby")).textContent.trim(), "Chapters");
      const chapterLinks = [...chapters.querySelectorAll("a[href^='#']")];
      const headings = [...guide.querySelectorAll("main h2")];
      assert.ok(headings.some(heading => heading.id === "modal-effect-types"), "Missing modal effect types chapter");
      assert.ok(headings.some(heading => heading.id === "linear-types"), "Missing linear types chapter");
      assert.deepEqual(chapterLinks.map(link => decodeURIComponent(link.hash.slice(1))), headings.map(h => h.id));
      assert.deepEqual(chapterLinks.map(link => link.textContent.trim()), headings.map(h => h.textContent.trim()));
      for (const anchor of guide.querySelectorAll("a[href^='#']")) {
        assert.ok(guide.getElementById(decodeURIComponent(anchor.hash.slice(1))), `Missing ${anchor.hash}`);
      }
      const backLink = requireLink(guide.querySelector("header"), "index.html");
      const home = (await site.loadPage(backLink.href)).document;
      assert.equal(home.getElementById("runtime").value, runtime, "The guide's Playground link retains the runtime");
      assert.equal(home.querySelector("h1").textContent.trim(), "SmallLinks");
      assert.equal(home.title, "SmallLinks");

      assert.deepEqual(linksTo(guide, "sources.html"), [], "No link to the standalone sources page");
      const guideSources = linksTo(guide, "index.html", "file");
      assert.ok(guideSources.some(link => new URL(link.href).searchParams.get("file") === stateModule),
        "The guide must link to the imported state module");
      for (const link of guideSources) {
        const id = new URL(link.href).searchParams.get("file");
        const preview = (await site.loadPage(link.href)).document;
        await expectSourcePreview(preview, id);
      }

      requireLink(guide, "index.html", "example", searchExample);
      requireLink(guide, "index.html", "example", importExample);
      const blocks = [...guide.querySelectorAll("pre > code.language-links")];
      assert.equal(blocks.length, guideSnippetValues.length, "Guide snippet count");
      const snippets = new Map(blocks.map((block, i) => {
        const link = requireLink(block.closest(".listing"), "index.html");
        return [link, { code: block.textContent, value: guideSnippetValues[i] }];
      }));
      const runnableLinks = [
        ...linksTo(guide, "index.html", "example"),
        ...linksTo(guide, "index.html", "code"),
      ];
      for (const link of snippets.keys()) {
        assert.ok(runnableLinks.includes(link), `Missing runnable code listing link ${link.href}`);
      }
      for (const link of runnableLinks) {
        const params = new URL(link.href).searchParams;
        const linkedWindow = await site.loadPage(link.href);
        assert.equal(linkedWindow.document.getElementById("runtime").value, runtime,
          "Guide listings retain the runtime");
        const snippet = snippets.get(link);
        const id = params.get("example");
        if (id) {
          assert.equal(sources.get(id)?.kind, "runnable", id);
          await expectLoadedExample(linkedWindow.document, id);
          if (snippet) assert.equal(getSource(linkedWindow.document), snippet.code);
          const value = snippet?.value ?? expectedExamples.get(id);
          assert.ok(value, `Missing expected guide result for ${id}`);
          await run(linkedWindow.document, value);
          if (id === searchExample) checkHighlighting(linkedWindow);
        } else {
          assert.ok(snippet, `Missing Links code block for ${link.href}`);
          assert.equal(params.get("code"), snippet.code);
          await expectEditable(linkedWindow.document);
          assert.equal(getSource(linkedWindow.document), snippet.code);
          await run(linkedWindow.document, snippet.value);
        }
      }
    } finally {
      await site.close();
    }
  });
}
