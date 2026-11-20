#!/usr/bin/env node
/** Render docs/*.md plan pages into themed HTML for GitHub Pages. */
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

let marked;
try {
  ({ marked } = await import("marked"));
} catch {
  // allow running after npm i marked in docs/ or repo root
  try {
    ({ marked } = require("marked"));
  } catch {
    console.error("Need marked: npm i marked (in repo root or docs/)");
    process.exit(1);
  }
}

const PAGES = [
  ["AUTH-PLAN.md", "auth-plan.html", "Auth / SSO plan", "Auth plan"],
  ["DEV-MOVE.md", "dev-move.html", "Moving development", "Dev move"],
];

const SITE_LINKS = [
  ["./", "Home"],
  ["setup-guide.html", "Setup guide"],
  ["auth-plan.html", "Auth plan"],
  ["dev-move.html", "Dev move"],
];

function slugify(value) {
  return String(value)
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, "")
    .replace(/[\s_-]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function rewriteLinks(html) {
  return html
    .replaceAll('href="AUTH-PLAN.md"', 'href="auth-plan.html"')
    .replaceAll('href="./AUTH-PLAN.md"', 'href="auth-plan.html"')
    .replaceAll('href="DEV-MOVE.md"', 'href="dev-move.html"')
    .replaceAll('href="./DEV-MOVE.md"', 'href="dev-move.html"');
}

function extractToc(html) {
  const items = [];
  const re = /<h([23])\s+id="([^"]+)">([\s\S]*?)<\/h\1>/g;
  let m;
  while ((m = re.exec(html))) {
    const level = m[1];
    const id = m[2];
    const text = m[3].replace(/<[^>]+>/g, "").trim();
    const cls = level === "3" ? "toc-h3" : "toc-h2";
    items.push(`<li class="${cls}"><a href="#${id}">${text}</a></li>`);
  }
  if (!items.length) return "";
  return `<span class="toc-label">On this page</span>\n<ul class="toc">\n${items.join("\n")}\n</ul>`;
}

function renderPage(srcName, outName, title, current) {
  const mdText = readFileSync(join(__dirname, srcName), "utf8");
  const renderer = new marked.Renderer();
  const headings = [];
  renderer.heading = function ({ text, depth }) {
    const plain = String(text).replace(/<[^>]+>/g, "");
    const id = slugify(plain);
    if (depth === 2 || depth === 3) headings.push({ depth, id, text: plain });
    return `<h${depth} id="${id}">${text}</h${depth}>\n`;
  };

  let body = marked.parse(mdText, { renderer, gfm: true, breaks: false });
  body = rewriteLinks(body);

  // ensure ids even if marked version uses different heading API
  if (!headings.length) {
    body = body.replace(/<h([23])>([\s\S]*?)<\/h\1>/g, (_, depth, inner) => {
      const plain = inner.replace(/<[^>]+>/g, "").trim();
      const id = slugify(plain);
      return `<h${depth} id="${id}">${inner}</h${depth}>`;
    });
  }

  const toc = extractToc(body);
  const nav = SITE_LINKS.map(([href, label]) => {
    const cur = label === current ? ' aria-current="page"' : "";
    return `<li><a href="${href}"${cur}>${label}</a></li>`;
  }).join("\n        ");

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${title} · tak-home</title>
  <meta name="description" content="${title} — tak-home docs" />
  <link rel="icon" href="favicon.svg" type="image/svg+xml" />
  <link rel="icon" href="favicon.ico" sizes="any" />
  <link rel="apple-touch-icon" href="apple-touch-icon.png" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&family=Schibsted+Grotesk:wght@600;700&display=swap" rel="stylesheet" />
  <link rel="stylesheet" href="site.css" />
</head>
<body>
  <div class="wrap">
    <aside class="side">
      <a class="brand" href="./"><img src="logo.png" width="28" height="28" alt="" />tak-home</a>
      <ul class="nav-links">
        ${nav}
      </ul>
      ${toc}
    </aside>
    <main>
      <article>
${body}
      </article>
      <footer class="doc-foot">
        Source: <a href="${srcName}">${srcName}</a>
        · <a href="./">docs home</a>
        · <a href="https://github.com/TobiTenno/tak-home">GitHub</a>
      </footer>
    </main>
  </div>
</body>
</html>
`;
  writeFileSync(join(__dirname, outName), html);
  console.log(`wrote ${outName}`);
}

for (const row of PAGES) renderPage(...row);
