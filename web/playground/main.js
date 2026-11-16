import { createEditor } from "./editor.js";

const textarea = document.querySelector("#source");
const exampleList = document.querySelector("#example-list");
const exampleStatus = document.querySelector("#example-status");
const newProgram = document.querySelector("#new-program");
const exampleContext = document.querySelector("#example-context");
const exampleSource = document.querySelector("#example-source");
const importRow = document.querySelector("#example-import-row");
const exampleImports = document.querySelector("#example-imports");
const exampleDiagnostic = document.querySelector("#example-diagnostic");
const checkButton = document.querySelector("#check");
const runButton = document.querySelector("#run");
const stopButton = document.querySelector("#stop");
const requestStatus = document.querySelector("#request-status");
const inferredType = document.querySelector("#inferred-type");
const value = document.querySelector("#value");
const output = document.querySelector("#output");
const diagnostic = document.querySelector("#diagnostic");

const timeoutSeconds = 10;
// Allow the worker's output limit and room for its truncation notice.
const outputLimit = 64 * 1024 + 64;
const failureStatuses = {
  startup: "Worker startup failed.",
  parsing: "Parsing failed.",
  checking: "Check failed.",
  running: "Run failed.",
};

const starterSource = textarea.defaultValue;
const query = new URLSearchParams(window.location.search);
const linkedExampleId = query.get("example");
const linkedSource = query.get("code");
const sources = new Map();
const exampleButtons = new Map([["", newProgram]]);
let exampleId = "";
let exampleLoad = null;
let loadLinkedExample = Boolean(linkedExampleId) && textarea.value === starterSource;
let activeRequest = null;
let nextRequestId = 0;

function updateControls() {
  const busy = activeRequest !== null;
  const loadingExample = loadLinkedExample || exampleLoad !== null;
  checkButton.disabled = runButton.disabled = busy || loadingExample;
  stopButton.disabled = !busy;
  for (const button of exampleButtons.values()) button.disabled = busy;
}

async function fetchAsset(path, signal) {
  const response = await fetch(`./${path}`, { signal });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  return response;
}

function onSourceEdit() {
  if (!loadLinkedExample && !exampleLoad) return;

  loadLinkedExample = false;
  exampleLoad?.abort();
  exampleLoad = null;
  exampleStatus.textContent = "";
  updateControls();
}

function sourceLink(id) {
  return `./sources.html?file=${encodeURIComponent(id)}`;
}

function updateExampleContext() {
  exampleContext.hidden = exampleId === "";
  if (!exampleId) return;

  exampleSource.href = sourceLink(exampleId);
  exampleSource.textContent = exampleId;
  exampleSource.setAttribute("aria-label", `View ${exampleId} (opens in a new tab)`);

  const entry = sources.get(exampleId);
  exampleDiagnostic.hidden = entry?.kind !== "diagnostic";
  const imports = entry?.imports ?? [];
  importRow.hidden = imports.length === 0;
  exampleImports.replaceChildren();
  for (const { name, id } of imports) {
    const link = document.createElement("a");
    link.href = sourceLink(id);
    link.target = "_blank";
    link.rel = "noopener";
    link.textContent = name;
    link.setAttribute("aria-label", `${name} (opens in a new tab)`);
    if (exampleImports.hasChildNodes()) exampleImports.append(", ");
    exampleImports.append(link);
  }
}

function showLoadedExample(id, source, button) {
  editor.setSource(source);
  clearResults();
  requestStatus.textContent = "";
  exampleButtons.get(exampleId)?.removeAttribute("aria-current");
  exampleId = id;
  exampleButtons.get(id)?.setAttribute("aria-current", "true");
  updateExampleContext();
  if (button && document.activeElement === button) editor.focus();
}

async function loadExample(id, title, button) {
  loadLinkedExample = false;
  exampleLoad?.abort();
  exampleLoad = null;
  exampleStatus.textContent = "";

  if (id === "") {
    showLoadedExample("", starterSource, button);
    updateControls();
    return;
  }

  const controller = new AbortController();
  exampleLoad = controller;
  updateControls();
  exampleStatus.textContent = `Loading ${title}…`;
  try {
    const path = id.split("/").map(encodeURIComponent).join("/");
    const response = await fetchAsset(path, controller.signal);
    const source = await response.text();
    if (!controller.signal.aborted) {
      showLoadedExample(id, source, button);
      exampleStatus.textContent = "";
    }
  } catch (error) {
    if (!controller.signal.aborted) {
      exampleStatus.textContent = `Could not load ${title} (${error.message}).`;
    }
  } finally {
    if (exampleLoad === controller) {
      exampleLoad = null;
      updateControls();
    }
  }
}

function showExamples(examples) {
  const groups = new Map();
  for (const { id, title, group = "SmallLinks" } of examples) {
    if (!groups.has(group)) {
      const topic = document.createElement("div");
      topic.className = "example-topic";
      const heading = document.createElement("h3");
      heading.textContent = group;
      const list = document.createElement("ul");
      topic.append(heading, list);
      exampleList.append(topic);
      groups.set(group, list);
    }

    const button = document.createElement("button");
    button.type = "button";
    button.textContent = title;
    button.dataset.exampleId = id;
    button.addEventListener("click", () => loadExample(id, title, button));
    exampleButtons.set(id, button);

    const item = document.createElement("li");
    item.append(button);
    groups.get(group).append(item);
  }
  updateControls();
}

async function loadSources() {
  try {
    const response = await fetchAsset("sources.json");
    for (const entry of await response.json()) sources.set(entry.id, entry);
  } catch {
    return;
  }
  updateExampleContext();
}

async function loadCatalogue(sourceCatalogue) {
  if (loadLinkedExample) exampleStatus.textContent = "Loading the linked example…";
  let examples = [];
  try {
    const response = await fetchAsset("examples.json");
    const catalogue = await response.json();
    showExamples(catalogue);
    examples = catalogue;
  } catch (error) {
    exampleStatus.textContent = `Could not load the example list (${error.message}).`;
  }

  if (!loadLinkedExample) return;
  let linked = examples.find(({ id }) => id === linkedExampleId);
  if (!linked) {
    await sourceCatalogue;
    if (!loadLinkedExample) return;
    const entry = sources.get(linkedExampleId);
    if (entry?.kind === "diagnostic" || entry?.kind === "runnable") linked = entry;
  }
  loadLinkedExample = false;
  if (linked) {
    await loadExample(linked.id, linked.title);
  } else {
    exampleStatus.textContent = "The linked example is unavailable.";
    updateControls();
  }
}

function setResult(element, text = "") {
  element.textContent = text;
  element.parentElement.hidden = text === "";
}

function clearResults() {
  for (const result of [inferredType, value, output, diagnostic]) {
    setResult(result);
  }
}

function appendOutput(request, text) {
  if (!text || request.outputTruncated) return;

  const available = outputLimit - request.outputLength;
  output.append(text.slice(0, available));
  output.parentElement.hidden = false;
  request.outputLength += Math.min(text.length, available);

  if (text.length > available) {
    output.append("\n[Output truncated.]\n");
    request.outputTruncated = true;
  }
}

function finishRequest(request, status) {
  const restoreFocus = document.activeElement === stopButton;
  clearTimeout(request.timer);
  request.worker?.terminate();
  activeRequest = null;
  requestStatus.textContent = status;
  updateControls();
  if (restoreFocus) request.button.focus();
}

function onWorkerError(request, message) {
  if (request !== activeRequest) return;
  setResult(diagnostic, message || "The browser could not communicate with the worker.");
  const status = request.started ? "The worker stopped unexpectedly." : "Worker startup failed.";
  finishRequest(request, status);
}

function onWorkerMessage(request, submission, message) {
  if (request !== activeRequest || !message) return;

  if (message.kind === "ready" && !request.started) {
    request.started = true;
    requestStatus.textContent = submission.kind === "check" ? "Checking…" : "Running…";
    try {
      request.worker.postMessage(submission);
    } catch (error) {
      onWorkerError(request, error.message);
    }
    return;
  }

  if (message.id !== submission.id) return;
  switch (message.kind) {
    case "output":
      appendOutput(request, message.text);
      break;
    case "success":
      setResult(inferredType, message.inferredType);
      setResult(value, message.value);
      finishRequest(request, submission.kind === "check" ? "Check complete." : "Run complete.");
      break;
    case "failure":
      setResult(diagnostic, message.diagnostic);
      finishRequest(request, failureStatuses[message.stage] ?? "Request failed.");
      break;
  }
}

function startRequest(kind) {
  if (activeRequest || loadLinkedExample || exampleLoad) return;

  const submission = { kind, id: ++nextRequestId, source: editor.getSource() };
  if (exampleId) submission.exampleId = exampleId;

  const button = kind === "check" ? checkButton : runButton;
  const moveFocus = document.activeElement === button;
  const request = { button, started: false, outputLength: 0, outputTruncated: false };
  activeRequest = request;
  clearResults();
  requestStatus.textContent = "Starting worker…";
  updateControls();
  if (moveFocus) stopButton.focus();

  request.timer = setTimeout(() => {
    if (request === activeRequest) {
      finishRequest(request, `Timed out after ${timeoutSeconds} seconds.`);
    }
  }, timeoutSeconds * 1000);

  try {
    request.worker = new Worker("./worker.js");
    request.worker.addEventListener("message", ({ data }) => {
      onWorkerMessage(request, submission, data);
    });
    request.worker.addEventListener("messageerror", () => onWorkerError(request));
    request.worker.addEventListener("error", (event) => {
      event.preventDefault();
      onWorkerError(request, event.message);
    });
  } catch (error) {
    onWorkerError(request, error.message);
  }
}

function initialiseEditor() {
  try {
    return createEditor(textarea, onSourceEdit);
  } catch (error) {
    console.warn("Could not start the highlighted editor.", error);
    textarea.addEventListener("input", onSourceEdit);
    return {
      getSource: () => textarea.value,
      setSource: (source) => { textarea.value = source; },
      focus: () => textarea.focus(),
    };
  }
}

if (!linkedExampleId && linkedSource !== null && textarea.value === starterSource) {
  textarea.value = linkedSource;
}
const editor = initialiseEditor();
newProgram.addEventListener("click", () => loadExample("", "New program", newProgram));
checkButton.addEventListener("click", () => startRequest("check"));
runButton.addEventListener("click", () => startRequest("run"));
stopButton.addEventListener("click", () => {
  if (activeRequest) finishRequest(activeRequest, "Stopped.");
});
updateControls();
loadCatalogue(loadSources());
