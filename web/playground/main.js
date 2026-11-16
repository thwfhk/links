const textarea = document.querySelector("#source");
const exampleSelect = document.querySelector("#example");
const exampleStatus = document.querySelector("#example-status");
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
const linkedExampleId = new URLSearchParams(window.location.search).get("example");
const examples = new Map();
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
  exampleSelect.disabled = busy;
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
  exampleSelect.value = exampleId;
  updateControls();
}

async function loadExample(id) {
  exampleLoad?.abort();
  exampleLoad = null;
  exampleStatus.textContent = "";

  if (id === "") {
    exampleId = "";
    textarea.value = starterSource;
    updateControls();
    return;
  }

  const controller = new AbortController();
  exampleLoad = controller;
  updateControls();
  exampleStatus.textContent = `Loading ${examples.get(id)}…`;
  try {
    const path = id.split("/").map(encodeURIComponent).join("/");
    const response = await fetchAsset(path, controller.signal);
    const source = await response.text();
    if (!controller.signal.aborted) {
      textarea.value = source;
      exampleId = id;
      exampleStatus.textContent = "";
    }
  } catch (error) {
    if (!controller.signal.aborted) {
      exampleStatus.textContent = `Could not load ${examples.get(id)} (${error.message}).`;
      exampleSelect.value = exampleId;
    }
  } finally {
    if (exampleLoad === controller) {
      exampleLoad = null;
      updateControls();
    }
  }
}

async function loadCatalogue() {
  if (loadLinkedExample) exampleStatus.textContent = "Loading the linked example…";
  try {
    const response = await fetchAsset("examples.json");
    for (const { id, title } of await response.json()) {
      examples.set(id, title);
      exampleSelect.add(new Option(title, id));
    }
  } catch (error) {
    exampleStatus.textContent = `Could not load the example list (${error.message}).`;
    loadLinkedExample = false;
    updateControls();
    return;
  }

  if (!loadLinkedExample) return;
  loadLinkedExample = false;
  if (examples.has(linkedExampleId)) {
    exampleSelect.value = linkedExampleId;
    await loadExample(linkedExampleId);
  } else {
    exampleStatus.textContent = "The linked example is unavailable.";
    updateControls();
  }
}

function setResult(element, text = "") {
  element.textContent = text;
  element.parentElement.hidden = text === "";
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

  const submission = { kind, id: ++nextRequestId, source: textarea.value };
  if (exampleId) submission.exampleId = exampleId;

  const button = kind === "check" ? checkButton : runButton;
  const moveFocus = document.activeElement === button;
  const request = { button, started: false, outputLength: 0, outputTruncated: false };
  activeRequest = request;
  for (const result of [inferredType, value, output, diagnostic]) {
    setResult(result);
  }
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

textarea.addEventListener("input", onSourceEdit);
exampleSelect.addEventListener("change", () => loadExample(exampleSelect.value));
checkButton.addEventListener("click", () => startRequest("check"));
runButton.addEventListener("click", () => startRequest("run"));
stopButton.addEventListener("click", () => {
  if (activeRequest) finishRequest(activeRequest, "Stopped.");
});
updateControls();
loadCatalogue();
