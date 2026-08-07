import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { marked } from "marked";

const root = new URL(".", import.meta.url).pathname;
const layout = readFileSync(join(root, "templates", "layout.html"), "utf8");

const meta = {
  "index": { title: "Altair — batteries-included web framework for Crystal", description: "Altair is a batteries-included web framework for Crystal: routing, controllers, views, an ORM, generators and a CLI." },
  "docs/index": { title: "Documentation — Altair", description: "The Altair documentation: install, usage, features, the CLI reference and guides." },
  "docs/install": { title: "Install — Altair", description: "Download and set up Altair on Linux, macOS or Windows with one command and checksum verification." },
  "docs/usage": { title: "Usage — Altair", description: "Create a project, generate a scaffold and run the server with the Altair CLI." },
  "docs/update": { title: "Updating — Altair", description: "Update the Altair binary and a project's framework copy, with checksum verification." },
  "docs/features": { title: "What is implemented — Altair", description: "The current state of the Altair framework, phase by phase." },
  "docs/cli": { title: "CLI reference — Altair", description: "Every Altair command and generator." },
  "docs/routing": { title: "Routing guide — Altair", description: "Routes, parameters, resources and path helpers in Altair." },
  "docs/controllers": { title: "Controllers guide — Altair", description: "Actions, parameters, rendering and templates in Altair." },
  "docs/views": { title: "Views guide — Altair", description: "ECR templates, escaping, layouts, partials, helpers and the form builder." },
  "docs/record": { title: "Record (ORM) guide — Altair", description: "Models, migrations, validations, callbacks and associations in Altair::Record." },
  "docs/sessions": { title: "Sessions and auth guide — Altair", description: "Signed-cookie sessions, flash messages, CSRF protection and login helpers in Altair." },
  "docs/configuration": { title: "Configuration guide — Altair", description: "Altair configuration: .env, config/database.yml, per-environment settings and the config object." },
  "docs/security": { title: "Security guide — Altair", description: "Default security headers, CORS and request ids: the security middleware that ships with Altair." },
  "docs/uploads": { title: "Uploads guide — Altair", description: "Multipart form uploads: reading files from params and saving them with Altair." },
  "docs/benchmarks": { title: "Benchmarks — Altair", description: "Altair vs Express and Fiber on PostgreSQL-backed CRUD endpoints under real HTTP load, driven by k6." },
};

// Sidebar navigation, grouped. Order here is also the reading order for the
// next/previous pager at the bottom of each guide.
const docsNav = [
  { heading: "Getting started", pages: [
    { page: "docs/install", title: "Install" },
    { page: "docs/usage", title: "Usage" },
    { page: "docs/update", title: "Updating" },
  ]},
  { heading: "Guides", pages: [
    { page: "docs/routing", title: "Routing" },
    { page: "docs/controllers", title: "Controllers" },
    { page: "docs/views", title: "Views" },
    { page: "docs/record", title: "Record (ORM)" },
    { page: "docs/sessions", title: "Sessions and auth" },
    { page: "docs/configuration", title: "Configuration" },
    { page: "docs/security", title: "Security" },
    { page: "docs/uploads", title: "Uploads" },
  ]},
  { heading: "Reference", pages: [
    { page: "docs/features", title: "What is implemented" },
    { page: "docs/cli", title: "CLI reference" },
    { page: "docs/benchmarks", title: "Benchmarks" },
  ]},
];

const flatOrder = docsNav.flatMap((group) => group.pages.map((p) => p.page));

function renderSidebar(current) {
  let out = '<nav class="docs-sidebar" aria-label="Docs">';
  for (const group of docsNav) {
    out += `<h4>${group.heading}</h4><ul>`;
    for (const page of group.pages) {
      const active = page.page === current ? ' class="is-active" aria-current="page"' : "";
      const href = page.page === "docs/index" ? "index.html" : `${page.page.replace("docs/", "")}.html`;
      out += `<li><a href="${href}"${active}>${page.title}</a></li>`;
    }
    out += "</ul>";
  }
  out += "</nav>";
  return out;
}

function renderPager(current) {
  const idx = flatOrder.indexOf(current);
  if (idx === -1) return "";
  const prev = idx > 0 ? flatOrder[idx - 1] : null;
  const next = idx < flatOrder.length - 1 ? flatOrder[idx + 1] : null;
  const title = (page) => {
    for (const group of docsNav) {
      const hit = group.pages.find((p) => p.page === page);
      if (hit) return hit.title;
    }
    return "";
  };
  let out = '<div class="docs-pager">';
  out += prev
    ? `<a href="${prev.replace("docs/", "")}.html"><span class="label">Previous</span>${title(prev)}</a>`
    : "<span></span>";
  out += next
    ? `<a class="right" href="${next.replace("docs/", "")}.html"><span class="label">Next</span>${title(next)}</a>`
    : "<span></span>";
  out += "</div>";
  return out;
}

// Active nav states in the top bar.
function activeTokens(page) {
  const tokens = {
    home_active: "",
    docs_active: "",
    routing_active: "",
    install_active: "",
    usage_active: "",
    benchmarks_active: "",
  };
  if (page === "index") tokens.home_active = ' class="is-active" aria-current="page"';
  if (page === "docs/index") tokens.docs_active = ' class="is-active" aria-current="page"';
  if (page === "docs/routing" || page === "docs/controllers" || page === "docs/views" ||
      page === "docs/record" || page === "docs/sessions" || page === "docs/configuration" ||
      page === "docs/security" || page === "docs/uploads") {
    tokens.routing_active = ' class="is-active" aria-current="page"';
  }
  if (page === "docs/install") tokens.install_active = ' class="is-active" aria-current="page"';
  if (page === "docs/usage") tokens.usage_active = ' class="is-active" aria-current="page"';
  if (page === "docs/benchmarks") tokens.benchmarks_active = ' class="is-active" aria-current="page"';
  return tokens;
}

function render(page) {
  const source = readFileSync(join(root, "pages", `${page}.md`), "utf8");
  const rootPrefix = page === "index" ? "" : "../";
  const renderer = new marked.Renderer();
  const link = renderer.link.bind(renderer);
  renderer.link = (href, title, text) =>
    link(String(href).startsWith("/") ? `${rootPrefix}${String(href).slice(1)}` : href, title, text);
  const image = renderer.image.bind(renderer);
  renderer.image = (href, title, text) =>
    image(String(href).startsWith("/") ? `${rootPrefix}${String(href).slice(1)}` : href, title, text);
  const body = marked.parse(source, { renderer })
    .replaceAll('href="/', `href="${rootPrefix}`)
    .replaceAll('src="/', `src="${rootPrefix}`)
    .replaceAll("{{root}}", rootPrefix);
  const m = meta[page];

  // Non-docs pages (the homepage) render the content directly.
  let docsLayout = body;
  if (page.startsWith("docs/")) {
    docsLayout = `<div class="docs-layout">${renderSidebar(page)}<article class="docs-content">${body}${renderPager(page)}</article></div>`;
  }

  const tokens = activeTokens(page);
  return layout
    .replaceAll("{{home}}", rootPrefix ? rootPrefix : "index.html")
    .replaceAll("{{root}}", rootPrefix)
    .replaceAll("{{title}}", m.title)
    .replaceAll("{{description}}", m.description)
    .replaceAll("{{docs_layout}}", docsLayout)
    .replaceAll("{{home_active}}", tokens.home_active)
    .replaceAll("{{docs_active}}", tokens.docs_active)
    .replaceAll("{{routing_active}}", tokens.routing_active)
    .replaceAll("{{install_active}}", tokens.install_active)
    .replaceAll("{{usage_active}}", tokens.usage_active)
    .replaceAll("{{benchmarks_active}}", tokens.benchmarks_active);
}

const indexHtml = render("index");
writeFileSync(join(root, "index.html"), indexHtml);

mkdirSync(join(root, "docs"), { recursive: true });
const pages = ["index", "install", "usage", "update", "features", "cli", "routing", "controllers", "views", "record", "sessions", "configuration", "security", "uploads", "benchmarks"];
for (const page of pages) {
  writeFileSync(join(root, "docs", `${page}.html`), render(`docs/${page}`));
}

console.log(`Built website/: index.html + docs/{${pages.join(",")}}.html`);
