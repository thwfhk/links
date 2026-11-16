import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
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

const basics = "examples/basics.links";
const factorial = "examples/factorial.links";
const application = "examples/met/fresco-types/application.links";
const importExample = "examples/handlers/module_import.links";
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
const quickExamples = [basics, application, toggle, countdown, coinExample, importExample];

const expectedExamples = new Map([
  [basics, "42"],
  ["examples/church.links", "4"],
  ["examples/extensible-case.links", '("A", "B", "C")'],
  [factorial, /\(f = 3628800, i = 10\)\]$/],
  [coinExample, "()"],
  [countdown, "0"],
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

// Adapt the browser message API while running the unmodified worker bundle.
const workerBootstrap = `
  const { parentPort, workerData } = require("node:worker_threads");
  globalThis.onmessage = null;
  globalThis.postMessage = message => parentPort.postMessage(message);
  parentPort.on("message", data => globalThis.onmessage({ data }));
  require(workerData);
`;

function openSite(basePath) {
  const workers = new Set();
  const pages = [];
  const errors = [];
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

    // jsdom returns no layout boxes for elements and lacks the equivalent Range method.
    window.Range.prototype.getClientRects ??= () => [];

    window.fetch = async (href, { signal } = {}) => {
      const path = assetPath(new URL(href, url));
      return new Response(await readFile(path, { signal }));
    };
    window.Worker = class extends window.EventTarget {
      constructor(href) {
        super();
        const workerData = assetPath(new URL(href, url));
        this.worker = new Worker(workerBootstrap, { eval: true, workerData });
        workers.add(this.worker);
        this.worker.once("exit", () => workers.delete(this.worker));
        this.worker.on("message", data => this.dispatchEvent(new window.MessageEvent("message", { data })));
        this.worker.on("error", error => this.dispatchEvent(new window.ErrorEvent("error", {
          message: error.message,
          cancelable: true,
        })));
      }

      postMessage(message) { this.worker.postMessage(message); }
      terminate() { void this.worker.terminate(); }
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

  return { loadPage, close, activeWorkers: () => workers.size };
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
  await waitFor(() => button.disabled, false, "Run finished");
  const diagnostic = document.getElementById("diagnostic").textContent;
  assert.equal(document.getElementById("request-status").textContent, "Run complete.", diagnostic);
  const result = document.getElementById("value");
  assert.ok(!result.closest("[hidden]"), "Run returned no value");
  if (value instanceof RegExp) assert.match(result.textContent, value);
  else assert.equal(result.textContent, value);
}

test("Package repository sources and their catalogue entries", async () => {
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

test("Check and run source and the published examples at the site root", async () => {
  const site = openSite("/");
  try {
    const window = await site.loadPage();
    const document = window.document;
    const check = document.getElementById("check");
    const runButton = document.getElementById("run");
    const stop = document.getElementById("stop");
    const examples = document.getElementById("example-list");
    const newProgram = document.getElementById("new-program");
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
    await expectText(document, "inferred-type", "Int");
    assert.ok(document.getElementById("value").closest("[hidden]"));
    assert.ok(document.getElementById("output").closest("[hidden]"));
    await run(document, "42");
    await expectText(document, "output", "hello from SmallLinks");

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

    editSource(window, '{ print("before the error"); connectSocket("localhost", 80) }');
    runButton.click();
    await expectText(document, "diagnostic", /connectSocket is unavailable in the browser/);
    await expectText(document, "output", "before the error");

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

    editSource(window, "loop(0)");
    check.click();
    await expectText(document, "diagnostic", /loop/);
    editSource(window, "length([1, 2, 3])");
    await run(document, "3");
    assert.ok(document.getElementById("output").closest("[hidden]"));
    assert.ok(document.getElementById("diagnostic").closest("[hidden]"));
  } finally {
    await site.close();
  }
});

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
}

for (const basePath of ["/", "/smalllinks/"]) {
  test(`Follow repository sources and retain the editor at ${basePath}`, async () => {
    const site = openSite(basePath);
    try {
      const window = await site.loadPage(`${basePath}?example=${encodeURIComponent(importExample)}`);
      const document = window.document;
      await expectLoadedExample(document, importExample);
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
      const directLink = requireLink(direct.getElementById("source-files"), "index.html", "file", rejectedExample);
      assert.equal(directLink.getAttribute("aria-current"), "page");
      assert.equal(directLink.closest("details:not([open])"), null, "A direct preview opens every containing folder");
    } finally {
      await site.close();
    }
  });

  test(`Follow chapter navigation and run the guide's examples at ${basePath}`, async () => {
    const site = openSite(basePath);
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
