const textarea = document.querySelector("#source");
const exampleSelect = document.querySelector("#example");
const exampleStatus = document.querySelector("#example-status");
const starterSource = textarea.value;
const examples = new Map();
let exampleId = "";
let exampleLoad = null;
let loadLinkedExample = true;

async function fetchAsset(path, signal) {
  const response = await fetch(`./${path}`, { signal });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  return response;
}

function onSourceEdit() {
  loadLinkedExample = false;
  if (exampleLoad) {
    exampleLoad.abort();
    exampleStatus.textContent = "";
    exampleSelect.value = exampleId;
  }
}

async function loadExample(id) {
  exampleLoad?.abort();
  exampleLoad = null;
  exampleStatus.textContent = "";

  if (id === "") {
    exampleId = "";
    textarea.value = starterSource;
    return;
  }

  const controller = new AbortController();
  exampleLoad = controller;
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
    }
  }
}

async function loadCatalogue() {
  const linkedId = new URLSearchParams(window.location.search).get("example");
  try {
    const response = await fetchAsset("examples.json");
    for (const { id, title } of await response.json()) {
      examples.set(id, title);
      exampleSelect.add(new Option(title, id));
    }
  } catch (error) {
    exampleStatus.textContent = `Could not load the example list (${error.message}).`;
    return;
  }

  if (linkedId && loadLinkedExample) {
    if (examples.has(linkedId)) {
      exampleSelect.value = linkedId;
      await loadExample(linkedId);
    } else {
      exampleStatus.textContent = "The linked example is unavailable.";
    }
  }
}

textarea.addEventListener("input", onSourceEdit);
exampleSelect.addEventListener("change", () => loadExample(exampleSelect.value));
loadCatalogue();
