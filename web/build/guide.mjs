import { copyFile, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { join, relative, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import MarkdownIt from "markdown-it";

const guidePath = "tasks/met/GUIDE.md";
// The published branch containing the guide and its source links.
const repository = "https://github.com/thwfhk/links";
const sourceRef = "small-met";

function headingId(inline, usedIds) {
  const base = inline.children
    .map(token => token.type === "softbreak" ? " " : token.content)
    .join("")
    .toLowerCase()
    .replace(/[^\p{L}\p{M}\p{N}_ -]/gu, "")
    .replaceAll(" ", "-");

  let id = base;
  for (let suffix = 1; usedIds.has(id); suffix += 1) {
    id = `${base}-${suffix}`;
  }
  usedIds.add(id);
  return id;
}

async function guideLink(href, root, guideUrl, exampleIds) {
  if (/^(#|\/\/|[a-z][a-z\d+.-]*:)/i.test(href)) return href;

  const url = new URL(href, guideUrl);
  const filename = fileURLToPath(url);
  const path = relative(root, filename).split(sep).join("/");
  if (path === ".." || path.startsWith("../")) {
    throw new Error(`Guide link leaves the repository: ${href}`);
  }
  if (path === guidePath) return `guide.html${url.search}${url.hash}`;
  if (exampleIds.has(path)) return `index.html?example=${encodeURIComponent(path)}`;

  const kind = (await stat(filename)).isDirectory() ? "tree" : "blob";
  const sourcePath = path.split("/").map(encodeURIComponent).join("/");
  return `${repository}/${kind}/${sourceRef}/${sourcePath}${url.search}${url.hash}`;
}

export async function renderGuide(root, output, examples) {
  const guideUrl = pathToFileURL(join(root, guidePath));
  const source = await readFile(guideUrl, "utf8");
  const markdown = new MarkdownIt();
  const env = {};
  const tokens = markdown.parse(source, env);
  const usedIds = new Set();
  const exampleIds = new Set(examples.map(({ id }) => id));

  for (const [i, token] of tokens.entries()) {
    if (token.type === "heading_open") {
      token.attrSet("id", headingId(tokens[i + 1], usedIds));
    }
    if (token.type === "inline") {
      for (const child of token.children) {
        if (child.type === "link_open") {
          const href = await guideLink(child.attrGet("href"), root, guideUrl, exampleIds);
          child.attrSet("href", href);
        }
      }
    }
  }

  markdown.renderer.rules.table_open = (tokens, i, options, env, renderer) =>
    `<div class="table-scroll" tabindex="0">${renderer.renderToken(tokens, i, options)}`;
  markdown.renderer.rules.table_close = (tokens, i, options, env, renderer) =>
    `${renderer.renderToken(tokens, i, options)}</div>\n`;

  const content = markdown.renderer.render(tokens, markdown.options, env);
  const page = `<!doctype html>
<html lang="en-GB">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SmallLinks language guide</title>
  <link rel="stylesheet" href="guide.css">
</head>
<body>
  <header>
    <nav aria-label="SmallLinks">
      <a href="index.html">SmallLinks playground</a>
    </nav>
  </header>
  <main>
${content}  </main>
</body>
</html>
`;

  await mkdir(output, { recursive: true });
  await Promise.all([
    copyFile(new URL("guide.css", import.meta.url), join(output, "guide.css")),
    writeFile(join(output, "guide.html"), page),
  ]);
}
