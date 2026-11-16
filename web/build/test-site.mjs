import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve, sep } from "node:path";
import { test } from "node:test";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";
import { EditorView } from "@codemirror/view";
import { JSDOM, VirtualConsole } from "jsdom";

const dist = fileURLToPath(new URL("../dist", import.meta.url));
const root = fileURLToPath(new URL("../../", import.meta.url));
const host = "https://smalllinks.test";

const expectedExamples = new Map([
  ["examples/factorial.links", /\(f = 3628800, i = 10\)\]$/],
  ["examples/met/fresco-effects/single-yield.links", "1"],
  ["examples/met/fresco-types/rank-two.links", "(42, 42, (42, true), (), 42, (42, true))"],
  ["examples/met/fresco-effects/find_mask_paper.links", "([1, 2, 3], Just(3), (Just(2), [1, 2]))"],
  ["examples/handlers/module_import.links", "(0, [0, 1, 2, 3, 4])"],
]);

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
      const editor = window.document.querySelector(".cm-editor");
      if (editor) EditorView.findFromDOM(editor).destroy();
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

function getSource(document) {
  const editor = document.querySelector(".cm-editor");
  return editor ? EditorView.findFromDOM(editor).state.doc.toString() : document.getElementById("source").value;
}

function editSource(window, source) {
  const document = window.document;
  const editor = document.querySelector(".cm-editor");
  if (editor) {
    const view = EditorView.findFromDOM(editor);
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: source } });
  } else {
    const textarea = document.getElementById("source");
    textarea.value = source;
    textarea.dispatchEvent(new window.Event("input", { bubbles: true }));
  }
}

function selectExample(window, id) {
  const menu = window.document.getElementById("example");
  menu.value = id;
  assert.equal(menu.value, id);
  menu.dispatchEvent(new window.Event("change", { bubbles: true }));
}

async function run(document, value) {
  document.getElementById("run").click();
  await expectText(document, "value", value);
}

test("Check and run source and the published examples at the site root", async () => {
  const site = openSite("/");
  try {
    const window = await site.loadPage();
    const document = window.document;
    const check = document.getElementById("check");
    const runButton = document.getElementById("run");
    const stop = document.getElementById("stop");
    const menu = document.getElementById("example");
    assert.equal(check.textContent.trim(), "Check");
    assert.equal(runButton.textContent.trim(), "Run");
    assert.equal(stop.textContent.trim(), "Stop");
    assert.ok(menu.labels[0]?.textContent.trim(), "The example selector needs a label");
    const exampleIds = () => [...menu.options].map(option => option.value).filter(Boolean);

    const catalogue = JSON.parse(await readFile(resolve(dist, "examples.json"), "utf8"));
    assert.deepEqual(catalogue.map(({ id }) => id).sort(), [...expectedExamples.keys()].sort());
    await waitFor(() => exampleIds().length, catalogue.length, "Example count");
    assert.deepEqual(exampleIds(), catalogue.map(({ id }) => id));

    editSource(window, '{ print("hello from SmallLinks"); 6 * 7 }');
    check.click();
    await expectText(document, "inferred-type", "Int");
    assert.ok(document.getElementById("value").closest("[hidden]"));
    assert.ok(document.getElementById("output").closest("[hidden]"));
    await run(document, "42");
    await expectText(document, "output", "hello from SmallLinks");

    const sibling = "examples/handlers/shallow_state.links";
    assert.equal(await readFile(resolve(dist, sibling), "utf8"), await readFile(resolve(root, sibling), "utf8"));
    for (const { id } of catalogue) {
      const source = await readFile(resolve(root, id), "utf8");
      selectExample(window, id);
      await waitFor(() => getSource(document), source, id);
      await run(document, expectedExamples.get(id));
    }

    // The edited program still needs the example's sibling-module search path.
    const importExample = "examples/handlers/module_import.links";
    selectExample(window, importExample);
    const importSource = await readFile(resolve(root, importExample), "utf8");
    await waitFor(() => runButton.disabled, false, "Import example loaded");
    await waitFor(() => getSource(document), importSource, importExample);
    editSource(window, "import Shallow_state;\nShallow_state.unitTest(3)");
    await run(document, "(0, [0, 1, 2])");
    selectExample(window, "");

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

test("Follow the guide and run its linked example beneath a path prefix", async () => {
  const site = openSite("/smalllinks/");
  try {
    const { document } = await site.loadPage();
    const guideLink = [...document.links].find(link => link.textContent.trim() === "Language guide");
    const guide = (await site.loadPage(guideLink.href)).document;
    assert.equal(guide.querySelector("h1").textContent, "SmallLinks language guide");
    for (const anchor of guide.querySelectorAll("a[href^='#']")) {
      assert.ok(guide.getElementById(decodeURIComponent(anchor.hash.slice(1))), `Missing ${anchor.hash}`);
    }
    assert.ok(guide.querySelector("pre > code.language-links"), "The guide has no Links code blocks");
    const backLink = guide.querySelector("header a[href]");
    const home = (await site.loadPage(backLink.href)).document;
    assert.equal(home.querySelector("h1").textContent.trim(), "SmallLinks Playground");

    const searchId = "examples/met/fresco-effects/find_mask_paper.links";
    const searchLink = [...guide.links].find(link => link.textContent === "search example");
    assert.equal(new URL(searchLink.href).searchParams.get("example"), searchId);
    const linkedWindow = await site.loadPage(searchLink.href);
    const linked = linkedWindow.document;
    const source = await readFile(resolve(root, searchId), "utf8");
    await waitFor(() => getSource(linked), source, searchId);
    assert.equal(linked.getElementById("example").value, searchId);
    await run(linked, expectedExamples.get(searchId));

    const editor = linked.querySelector(".cm-content");
    assert.ok(editor, "The highlighted editor did not load");
    assert.equal(editor.getAttribute("aria-label"), "Source");
    const highlightTokens = () => [...editor.querySelectorAll(".cm-line span[class]")].map(token => token.textContent);
    assert.ok(highlightTokens().includes("effect"), "The effect keyword has no highlight class");
    assert.ok(highlightTokens().some(token => token.startsWith("# Use a second operation")),
      "The comment has no highlight class");
    const literal = String.raw`"say \"hello\" #"`;
    editSource(linkedWindow, `{ print(${literal}); 42 }`);
    assert.ok(highlightTokens().includes(literal), "The escaped string has no highlight class");
  } finally {
    await site.close();
  }
});
