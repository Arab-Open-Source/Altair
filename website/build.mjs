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
  "docs/console": { title: "Console guide — Altair", description: "Development console: boot banner, request log, colors and slow-request highlighting." },
  "docs/testing": { title: "Testing guide — Altair", description: "Testing Altair applications with Altair::Test helpers." },
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
    { page: "docs/console", title: "Console" },
    { page: "docs/testing", title: "Testing" },
  ]},
  { heading: "Reference", pages: [
    { page: "docs/features", title: "What is implemented" },
    { page: "docs/cli", title: "CLI reference" },
    { page: "docs/benchmarks", title: "Benchmarks" },
  ]},
];

const icons = {
  "docs/install": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>',
  "docs/usage": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"/></svg>',
  "docs/update": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10"/><path d="M20.49 15a9 9 0 0 1-14.85 3.36L1 14"/></svg>',
  "docs/routing": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="12" r="3"/><path d="M8.5 8.5L13.5 9.5"/><path d="M8.5 15.5L13.5 14.5"/></svg>',
  "docs/controllers": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="2" width="20" height="8" rx="2"/><rect x="2" y="14" width="20" height="8" rx="2"/><line x1="6" y1="6" x2="6.01" y2="6"/><line x1="6" y1="18" x2="6.01" y2="18"/></svg>',
  "docs/views": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>',
  "docs/record": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/></svg>',
  "docs/sessions": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/><circle cx="12" cy="16" r="1"/></svg>',
  "docs/configuration": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M12 1v4"/><path d="M12 19v4"/><path d="M4.22 4.22l2.83 2.83"/><path d="M16.97 16.97l2.83 2.83"/><path d="M1 12h4"/><path d="M19 12h4"/><path d="M4.22 19.78l2.83-2.83"/><path d="M16.97 7.03l2.83-2.83"/></svg>',
  "docs/security": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>',
  "docs/uploads": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>',
  "docs/console": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>',
  "docs/testing": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>',
  "docs/features": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>',
  "docs/cli": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>',
  "docs/benchmarks": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/></svg>',
  "docs/index": '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>',
};

const flatOrder = docsNav.flatMap((group) => group.pages.map((p) => p.page));

function renderSidebar(current) {
  let out = '<nav class="docs-sidebar" aria-label="Docs">';
  for (const group of docsNav) {
    out += `<h4>${group.heading}</h4><ul>`;
    for (const page of group.pages) {
      const active = page.page === current ? ' class="is-active" aria-current="page"' : "";
      const href = page.page === "docs/index" ? "index.html" : `${page.page.replace("docs/", "")}.html`;
      const icon = icons[page.page] || "";
      out += `<li><a href="${href}"${active}><span class="sidebar-icon">${icon}</span>${page.title}</a></li>`;
    }
    out += "</ul>";
  }
  out += "</nav>";
  return out;
}

function renderBreadcrumbs(current) {
  for (const group of docsNav) {
    const hit = group.pages.find((p) => p.page === current);
    if (hit) {
      return `<nav class="breadcrumbs" aria-label="Breadcrumb"><a href="index.html">Docs</a><span class="sep">/</span><span>${group.heading}</span><span class="sep">/</span><span aria-current="page">${hit.title}</span></nav>`;
    }
  }
  return "";
}

function renderPager(current) {
  const idx = flatOrder.indexOf(current);
  if (idx === -1) return "";
  const total = flatOrder.length;
  const prev = idx > 0 ? flatOrder[idx - 1] : null;
  const next = idx < flatOrder.length - 1 ? flatOrder[idx + 1] : null;
  const title = (page) => {
    for (const group of docsNav) {
      const hit = group.pages.find((p) => p.page === page);
      if (hit) return hit.title;
    }
    return "";
  };
  const arrowLeft = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>';
  const arrowRight = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>';
  let out = `<div class="docs-pager"><div class="pager-progress">Page ${idx + 1} of ${total}</div><div class="pager-links">`;
  out += prev
    ? `<a class="pager-card" href="${prev.replace("docs/", "")}.html"><span class="pager-icon">${arrowLeft}</span><span><span class="label">Previous</span><span class="pager-title">${title(prev)}</span></span></a>`
    : '<span></span>';
  out += next
    ? `<a class="pager-card right" href="${next.replace("docs/", "")}.html"><span><span class="label">Next</span><span class="pager-title">${title(next)}</span></span><span class="pager-icon">${arrowRight}</span></a>`
    : '<span></span>';
  out += "</div></div>";
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
    const breadcrumbs = renderBreadcrumbs(page);
    const pageIcon = icons[page] ? `<span class="docs-page-icon">${icons[page]}</span>` : "";
    // Wrap the first H1 with icon if present
    let bodyWithHeader = body;
    if (pageIcon && body.includes("<h1>")) {
      bodyWithHeader = body.replace("<h1>", `<div class="docs-page-header">${pageIcon}<h1>`);
      bodyWithHeader = bodyWithHeader.replace("</h1>", "</h1></div>");
    }
    docsLayout = `<div class="docs-layout">${renderSidebar(page)}<article class="docs-content"><div class="reading-progress" aria-hidden="true"><div class="reading-progress-bar"></div></div>${breadcrumbs}${bodyWithHeader}${renderPager(page)}</article></div>`;
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
  const pages = ["index", "install", "usage", "update", "features", "cli", "routing", "controllers", "views", "record", "sessions", "configuration", "security", "uploads", "console", "testing", "benchmarks"];
for (const page of pages) {
  writeFileSync(join(root, "docs", `${page}.html`), render(`docs/${page}`));
}

console.log(`Built website/: index.html + docs/{${pages.join(",")}}.html`);
