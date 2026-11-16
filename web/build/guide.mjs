import { copyFile, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { join, relative, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import MarkdownIt from "markdown-it";

const guidePath = "web/guide.md";
// The published branch containing the full language guide and the examples.
const repository = "https://github.com/thwfhk/links";
const sourceRef = "small-met";

function headingId(title, usedIds) {
  const base = title
    .toLowerCase()
    .replace(/[^\p{L}\p{M}\p{N}_ -]/gu, "")
    .replaceAll(" ", "-") || "section";

  let id = base;
  for (let suffix = 1; usedIds.has(id); suffix += 1) {
    id = `${base}-${suffix}`;
  }
  usedIds.add(id);
  return id;
}

async function readSourceIds(output) {
  try {
    const sources = JSON.parse(await readFile(join(output, "sources.json"), "utf8"));
    return new Set(sources.map(({ id }) => id));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

async function guideLink(href, root, guideUrl, exampleIds, sourceIds) {
  if (/^(#|\/\/|[a-z][a-z\d+.-]*:)/i.test(href)) return href;

  const url = new URL(href, guideUrl);
  const filename = fileURLToPath(url);
  const path = relative(root, filename).split(sep).join("/");
  if (path === ".." || path.startsWith("../")) {
    throw new Error(`Guide link leaves the repository: ${href}`);
  }
  if (path === guidePath) return `guide.html${url.search}${url.hash}`;
  if (exampleIds.has(path)) return `index.html?example=${encodeURIComponent(path)}`;
  if (sourceIds?.has(path)) return `index.html?file=${encodeURIComponent(path)}`;

  const kind = (await stat(filename)).isDirectory() ? "tree" : "blob";
  const sourcePath = path.split("/").map(encodeURIComponent).join("/");
  return `${repository}/${kind}/${sourceRef}/${sourcePath}${url.search}${url.hash}`;
}

export async function renderGuide(root, output, examples) {
  const guideUrl = pathToFileURL(join(root, guidePath));
  const [source, sourceIds] = await Promise.all([
    readFile(guideUrl, "utf8"),
    readSourceIds(output),
  ]);
  const markdown = new MarkdownIt();
  const env = {};
  const tokens = markdown.parse(source, env);
  const usedIds = new Set(["chapter-nav-title"]);
  const exampleIds = new Set(examples.map(({ id }) => id));
  const chapters = [];

  for (const [i, token] of tokens.entries()) {
    if (token.type === "heading_open") {
      const title = tokens[i + 1].children
        .map(child => child.type === "softbreak" || child.type === "hardbreak" ? " " : child.content)
        .join("");
      const id = headingId(title, usedIds);
      token.attrSet("id", id);
      if (token.tag === "h2" && token.level === 0) {
        chapters.push({ id, title });
      }
    }
    if (token.type === "inline") {
      for (const child of token.children) {
        if (child.type === "link_open") {
          const href = await guideLink(child.attrGet("href"), root, guideUrl, exampleIds, sourceIds);
          child.attrSet("href", href);
        }
      }
    }
  }

  const renderFence = markdown.renderer.rules.fence;
  markdown.renderer.rules.fence = (tokens, i, options, env, renderer) => {
    const token = tokens[i];
    const block = renderFence(tokens, i, options, env, renderer);
    const [language, ...attributes] = markdown.utils.unescapeAll(token.info).trim().split(/\s+/);
    if (language !== "links") return block;

    let href = `index.html?code=${encodeURIComponent(token.content)}`;
    if (attributes.length) {
      const id = /^example=(\S+)$/.exec(attributes.join(" "))?.[1];
      if (!exampleIds.has(id)) {
        throw new Error(`Links fence must name a runnable example: ${token.info}`);
      }
      href = `index.html?example=${encodeURIComponent(id)}`;
    }
    return `<div class="listing">\n${block}  <a href="${href}">Open in playground</a>\n</div>\n`;
  };

  markdown.renderer.rules.table_open = (tokens, i, options, env, renderer) =>
    `<div class="table-scroll" tabindex="0">${renderer.renderToken(tokens, i, options)}`;
  markdown.renderer.rules.table_close = (tokens, i, options, env, renderer) =>
    `${renderer.renderToken(tokens, i, options)}</div>\n`;

  const content = markdown.renderer.render(tokens, markdown.options, env);
  const chapterLinks = chapters.map(({ id, title }) =>
    `        <li><a href="#${encodeURIComponent(id)}">${markdown.utils.escapeHtml(title)}</a></li>`);
  const chapterNav = chapters.length ? `    <nav class="site-sidebar panel chapters" aria-labelledby="chapter-nav-title">
      <p class="panel-title" id="chapter-nav-title">Chapters</p>
      <ul>
${chapterLinks.join("\n")}
      </ul>
    </nav>
` : "";
  const page = `<!doctype html>
<html lang="en-GB">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SmallLinks language guide</title>
  <link rel="stylesheet" href="./styles.css">
  <link rel="stylesheet" href="./guide.css">
</head>
<body>
  <header class="site-header">
    <a class="site-name" href="./index.html">SmallLinks</a>
    <nav class="site-links" aria-label="SmallLinks">
      <a href="./index.html">Playground</a>
      <a href="./guide.html" aria-current="page">Language guide</a>
    </nav>
  </header>
  <main class="site-layout">
${chapterNav}    <article class="site-content panel guide-content">
      <div class="guide-prose">
${content}      </div>
    </article>
  </main>
</body>
</html>
`;

  await mkdir(output, { recursive: true });
  await Promise.all([
    copyFile(new URL("guide.css", import.meta.url), join(output, "guide.css")),
    writeFile(join(output, "guide.html"), page),
  ]);
}
