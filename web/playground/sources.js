const files = document.getElementById("source-files");
const status = document.getElementById("source-status");
const title = document.getElementById("source-title");
const path = document.getElementById("source-path");
const kind = document.getElementById("source-kind");
const note = document.getElementById("source-note");
const playground = document.getElementById("source-playground");
const imports = document.getElementById("source-imports");
const callers = document.getElementById("source-callers");
const previewStatus = document.getElementById("source-preview-status");
const code = document.getElementById("source-code");

const kindLabels = {
  runnable: "Runnable example",
  diagnostic: "Expected type error",
  source: "Source only",
};

function createLink(text, href) {
  const link = document.createElement("a");
  link.textContent = text;
  link.href = href;
  return link;
}

function sourceURL(id) {
  return `./sources.html?file=${encodeURIComponent(id)}`;
}

function playgroundURL(id) {
  return `./index.html?example=${encodeURIComponent(id)}`;
}

function directoryOf(id) {
  return id.slice(0, Math.max(0, id.lastIndexOf("/")));
}

async function fetchAsset(asset) {
  const response = await fetch(`./${asset}`);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response;
}

function showFiles(catalogue, selected) {
  const directories = new Map();
  const entries = [...catalogue.values()].sort((a, b) => a.id.localeCompare(b.id));
  for (const entry of entries) {
    const directory = directoryOf(entry.id);
    if (!directories.has(directory)) directories.set(directory, []);
    directories.get(directory).push(entry);
  }

  const openDirectory = selected ? directoryOf(selected.id) : "examples";
  const orderedDirectories = [...directories.keys()].sort();
  for (const directory of orderedDirectories) {
    const group = document.createElement("details");
    group.className = "source-directory";
    group.open = directory === openDirectory;
    const summary = document.createElement("summary");
    summary.textContent = directory ? `${directory}/` : "Repository root";
    const list = document.createElement("ul");
    for (const { id } of directories.get(directory)) {
      const item = document.createElement("li");
      const link = createLink(id.slice(id.lastIndexOf("/") + 1), sourceURL(id));
      if (id === selected?.id) link.setAttribute("aria-current", "page");
      item.append(link);
      list.append(item);
    }
    group.append(summary, list);
    files.append(group);
  }
  files.hidden = false;
}

function showImports(entries, catalogue) {
  for (const { name, id } of entries) {
    const item = document.createElement("li");
    if (catalogue.has(id)) {
      item.append(createLink(name, sourceURL(id)));
    } else {
      item.textContent = `${name} (source unavailable)`;
    }
    imports.append(item);
  }
  imports.parentElement.hidden = imports.children.length === 0;
}

function showCallers(ids, catalogue) {
  for (const id of ids) {
    const caller = catalogue.get(id);
    if (!caller) continue;
    const item = document.createElement("li");
    item.append(createLink(caller.title, sourceURL(id)));
    if (caller.kind === "runnable") {
      const link = createLink("Open in playground", playgroundURL(id));
      link.setAttribute("aria-label", `Open in playground (${caller.title})`);
      item.append(" ", link);
    }
    callers.append(item);
  }
  callers.parentElement.hidden = callers.children.length === 0;
}

async function showSource(entry, catalogue) {
  title.textContent = entry.title;
  path.textContent = entry.id;
  kind.textContent = kindLabels[entry.kind];
  note.textContent = entry.note ?? "";
  note.hidden = !entry.note;

  if (entry.kind === "runnable" || entry.kind === "diagnostic") {
    playground.href = playgroundURL(entry.id);
    playground.textContent = entry.kind === "runnable" ? "Open in playground" : "Open in playground to check";
    playground.hidden = false;
  }

  showImports(entry.imports, catalogue);
  showCallers(entry.callers, catalogue);
  title.parentElement.hidden = false;
  document.title = `${entry.title} · SmallLinks Sources`;

  previewStatus.textContent = "Loading source…";
  try {
    const asset = entry.id.split("/").map(encodeURIComponent).join("/");
    const response = await fetchAsset(asset);
    code.textContent = await response.text();
    code.parentElement.hidden = false;
    previewStatus.textContent = "";
  } catch (error) {
    previewStatus.textContent = `Could not load the source (${error.message}).`;
  }
}

async function loadCatalogue() {
  status.textContent = "Loading the source catalogue…";
  let catalogue;
  try {
    const response = await fetchAsset("sources.json");
    catalogue = new Map((await response.json()).map(entry => [entry.id, entry]));
  } catch (error) {
    status.textContent = `Could not load the source catalogue (${error.message}).`;
    return;
  }

  const requested = new URLSearchParams(window.location.search).get("file");
  const entry = catalogue.get(requested);
  status.textContent = requested && !entry ? "This file is unavailable in the source catalogue." : "";
  showFiles(catalogue, entry);
  if (entry) await showSource(entry, catalogue);
}

loadCatalogue();
