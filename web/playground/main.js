import { createEditor } from "./editor.js";

const textarea = document.querySelector("#source");
const exampleList = document.querySelector("#example-list");
const exampleStatus = document.querySelector("#example-status");
const files = document.querySelector("#source-files");
const catalogueStatus = document.querySelector("#catalogue-status");
const playgroundLink = document.querySelector("#playground-link");
const newProgram = document.querySelector("#new-program");
const exampleContext = document.querySelector("#example-context");
const exampleSource = document.querySelector("#example-source");
const importRow = document.querySelector("#example-import-row");
const exampleImports = document.querySelector("#example-imports");
const exampleDiagnostic = document.querySelector("#example-diagnostic");
const exampleNote = document.querySelector("#example-note");
const callerRow = document.querySelector("#example-caller-row");
const exampleCallers = document.querySelector("#example-callers");
const editorMode = document.querySelector("#editor-mode");
const editActions = document.querySelector("#edit-actions");
const previewActions = document.querySelector("#preview-actions");
const loadButton = document.querySelector("#load-source");
const returnButton = document.querySelector("#return-to-editor");
const results = document.querySelector("#results");
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
const homeHref = new URL("./index.html", window.location.href).href;
const commonExamples = [
  { id: "examples/factorial.links" },
  { id: "examples/met/fresco-types/rank-two.links" },
  { id: "examples/met/fresco-effects/single-yield.links" },
  { id: "examples/handlers/module_import.links" },
  { id: "examples/met/fresco-effects/effectful-list.links" },
  { id: "examples/met/fresco-effects/find_mask_paper.links", label: "Search with effectful callbacks" },
  { id: "examples/met/thesis/handler_results.links", label: "Return effectful functions" },
];

const sources = new Map();
const fileLinks = new Map();
const exampleButtons = new Map();
let draftHref = homeHref;
let draftEntry = null;
let previewEntry = null;
let sourceLoad = null;
let activeRequest = null;
let nextRequestId = 0;

function updateControls() {
  const busy = activeRequest !== null;
  const viewing = previewEntry !== null;
  checkButton.disabled = runButton.disabled = busy || viewing || sourceLoad !== null;
  stopButton.disabled = !busy || viewing;
  newProgram.disabled = busy;
  loadButton.disabled = busy || sourceLoad !== null;
  for (const button of exampleButtons.values()) button.disabled = busy;
}

async function fetchAsset(path, signal) {
  const response = await fetch("./" + path, { signal });
  if (!response.ok) throw new Error("HTTP " + response.status);
  return response;
}

function cancelSourceLoad() {
  sourceLoad?.abort();
  sourceLoad = null;
  exampleStatus.textContent = "";
  updateControls();
}

function onSourceEdit() {
  if (sourceLoad) cancelSourceLoad();
}

function sourceHref(kind, id) {
  const url = new URL(homeHref);
  url.searchParams.set(kind, id);
  return url.href;
}

function setLocation(href) {
  if (window.location.href !== href) window.history.pushState(null, "", href);
}

function isPlainClick(event) {
  return event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
}

function loadFileLink(event) {
  if (!isPlainClick(event)) return;
  event.preventDefault();
  const link = event.currentTarget;
  const id = new URL(link.href).searchParams.get("file");
  void openSource(id, "file", link.href, link);
}

function createFileLink(id, text) {
  const link = document.createElement("a");
  link.href = sourceHref("file", id);
  link.textContent = text;
  link.addEventListener("click", loadFileLink);
  return link;
}

function showRelatedFiles(row, container, entries) {
  container.replaceChildren();
  for (const { id, title } of entries) {
    if (!sources.has(id)) continue;
    if (container.hasChildNodes()) container.append(", ");
    container.append(createFileLink(id, title));
  }
  row.hidden = !container.hasChildNodes();
}

function updateWorkspace() {
  const viewing = previewEntry !== null;
  const entry = previewEntry ?? draftEntry;
  const shownId = entry?.id;

  editorMode.textContent = viewing ? "Read-only" : "Editable";
  editActions.hidden = results.hidden = viewing;
  previewActions.hidden = !viewing;
  exampleContext.hidden = !entry;
  if (entry) {
    exampleSource.href = sourceHref("file", shownId);
    exampleSource.textContent = shownId;
    exampleNote.textContent = entry.note;
    exampleNote.hidden = !entry.note;
    exampleDiagnostic.hidden = viewing || entry.kind !== "diagnostic";
    showRelatedFiles(importRow, exampleImports, entry.imports.map(({ id, name }) => ({ id, title: name })));
    showRelatedFiles(callerRow, exampleCallers, entry.callers.map(id => sources.get(id)).filter(Boolean));
  }
  for (const [id, link] of fileLinks) {
    if (id === shownId) {
      link.setAttribute("aria-current", "page");
      for (let directory = link.closest(".source-directory"); directory;
           directory = directory.parentElement.closest(".source-directory")) {
        directory.open = true;
      }
    } else {
      link.removeAttribute("aria-current");
    }
  }
  for (const [id, button] of exampleButtons) {
    if (!viewing && id === shownId) button.setAttribute("aria-current", "true");
    else button.removeAttribute("aria-current");
  }
  updateControls();
}

function restoreDraft(href, trigger) {
  const focusEditor = document.activeElement === trigger;
  cancelSourceLoad();
  editor.restoreDraft();
  previewEntry = null;
  updateWorkspace();
  if (href) setLocation(href);
  if (focusEditor) editor.focus();
}

function replaceDraft(entry, source, href) {
  if (activeRequest) finishRequest(activeRequest, "Stopped.");
  if (source === null) editor.editPreview();
  else editor.setSource(source);
  draftHref = href;
  draftEntry = entry;
  previewEntry = null;
  clearResults();
  requestStatus.textContent = "";
  updateWorkspace();
}

async function openSource(id, kind, href, trigger) {
  cancelSourceLoad();
  const controller = new AbortController();
  sourceLoad = controller;
  updateControls();
  exampleStatus.textContent = "Loading source…";
  try {
    await sourceCatalogue;
    if (controller.signal.aborted) return;
    const entry = sources.get(id);
    if (!entry) throw new Error("File is unavailable in the catalogue.");
    const path = id.split("/").map(encodeURIComponent).join("/");
    const response = await fetchAsset(path, controller.signal);
    const source = await response.text();
    if (controller.signal.aborted) return;
    const focusEditor = document.activeElement === trigger;
    if (kind === "file") {
      editor.showPreview(source);
      previewEntry = entry;
      updateWorkspace();
    } else {
      replaceDraft(entry, source, href);
    }
    if (trigger) setLocation(href);
    if (focusEditor) editor.focus();
    exampleStatus.textContent = "";
  } catch (error) {
    if (!controller.signal.aborted) exampleStatus.textContent = "Could not load source. " + error.message;
  } finally {
    if (sourceLoad === controller) {
      sourceLoad = null;
      updateControls();
    }
  }
}

function createSourceList({ directories, fileIds }) {
  const list = document.createElement("ul");
  list.setAttribute("role", "list");
  for (const [name, directory] of [...directories].sort(([a], [b]) => a.localeCompare(b))) {
    list.append(createDirectoryItem(name, directory));
  }
  for (const id of fileIds) {
    const item = document.createElement("li");
    const link = createFileLink(id, id.slice(id.lastIndexOf("/") + 1));
    fileLinks.set(id, link);
    item.append(link);
    list.append(item);
  }
  return list;
}

function createDirectoryItem(name, directory) {
  const item = document.createElement("li");
  const group = document.createElement("details");
  group.className = "source-directory";
  const summary = document.createElement("summary");
  summary.textContent = name;
  group.append(summary, createSourceList(directory));
  item.append(group);
  return item;
}

function showFiles() {
  const root = { directories: new Map(), fileIds: [] };
  const prelude = { directories: new Map(), fileIds: [] };
  for (const { id } of sources.values()) {
    const names = id.split("/");
    names.pop();
    let directory = names.length ? root : prelude;
    for (const name of names) {
      if (!directory.directories.has(name)) {
        directory.directories.set(name, { directories: new Map(), fileIds: [] });
      }
      directory = directory.directories.get(name);
    }
    directory.fileIds.push(id);
  }
  const list = createSourceList(root);
  if (prelude.fileIds.length) list.prepend(createDirectoryItem("prelude", prelude));
  if (list.hasChildNodes()) files.append(list);
}

function showCommonExamples() {
  for (const { id, label } of commonExamples) {
    const entry = sources.get(id);
    if (!entry) continue;
    const item = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = label ?? entry.title;
    button.dataset.exampleId = id;
    button.addEventListener("click", () => openSource(id, "example", sourceHref("example", id), button));
    exampleButtons.set(id, button);
    item.append(button);
    exampleList.append(item);
  }
}

async function loadCatalogue() {
  catalogueStatus.textContent = "Loading files…";
  try {
    const response = await fetchAsset("sources.json");
    for (const entry of await response.json()) sources.set(entry.id, entry);
  } catch (error) {
    catalogueStatus.textContent = "Could not load files. " + error.message;
    return;
  }
  showFiles();
  showCommonExamples();
  catalogueStatus.textContent = "";
  updateWorkspace();
}

function openLocation() {
  const url = new URL(window.location.href);
  url.hash = "";
  const href = url.href;
  if (href === draftHref) {
    restoreDraft();
    return;
  }
  const query = url.searchParams;
  const file = query.get("file");
  const example = query.get("example");
  if (file === previewEntry?.id) cancelSourceLoad();
  else if (file) void openSource(file, "file", href);
  else if (example) void openSource(example, "example", href);
  else {
    cancelSourceLoad();
    replaceDraft(null, query.get("code") ?? starterSource, href);
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
  if (activeRequest || previewEntry || sourceLoad) return;

  const submission = { kind, id: ++nextRequestId, source: editor.getSource() };
  if (draftEntry?.id.startsWith("examples/")) submission.exampleId = draftEntry.id;

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
    let draft = null;

    function setEditingSource(source) {
      draft = null;
      textarea.readOnly = false;
      textarea.value = source;
    }

    return {
      getSource: () => textarea.value,
      setSource: setEditingSource,
      showPreview(source) {
        draft ??= { source: textarea.value, start: textarea.selectionStart, end: textarea.selectionEnd };
        textarea.value = source;
        textarea.readOnly = true;
      },
      restoreDraft() {
        if (!draft) return;
        const { source, start, end } = draft;
        setEditingSource(source);
        textarea.setSelectionRange(start, end);
      },
      editPreview: () => setEditingSource(textarea.value),
      focus: () => textarea.focus(),
    };
  }
}

const initialSource = textarea.value;
const editor = initialiseEditor();
playgroundLink.addEventListener("click", event => {
  if (!isPlainClick(event)) return;
  event.preventDefault();
  restoreDraft(draftHref);
});
exampleSource.addEventListener("click", loadFileLink);
newProgram.addEventListener("click", () => {
  const focusEditor = document.activeElement === newProgram;
  cancelSourceLoad();
  replaceDraft(null, starterSource, homeHref);
  setLocation(homeHref);
  if (focusEditor) editor.focus();
});
loadButton.addEventListener("click", () => {
  if (!previewEntry || sourceLoad || activeRequest) return;
  const focusEditor = document.activeElement === loadButton;
  const href = sourceHref("example", previewEntry.id);
  replaceDraft(previewEntry, null, href);
  setLocation(href);
  if (focusEditor) editor.focus();
});
returnButton.addEventListener("click", () => restoreDraft(draftHref, returnButton));
checkButton.addEventListener("click", () => startRequest("check"));
runButton.addEventListener("click", () => startRequest("run"));
stopButton.addEventListener("click", () => {
  if (activeRequest) finishRequest(activeRequest, "Stopped.");
});
window.addEventListener("popstate", openLocation);
const sourceCatalogue = loadCatalogue();
if (initialSource === starterSource) openLocation();
else {
  const url = new URL(window.location.href);
  url.hash = "";
  draftHref = url.href;
}
updateWorkspace();
