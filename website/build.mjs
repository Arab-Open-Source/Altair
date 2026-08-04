import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { marked } from "marked";

const root = new URL(".", import.meta.url).pathname;
const layout = readFileSync(join(root, "templates", "layout.html"), "utf8");

const meta = {
  "index": { title: "Altair — batteries-included web framework for Crystal", description: "Altair is a batteries-included web framework for Crystal: routing, controllers, views, an ORM, generators and a CLI." },
  "docs/index": { title: "Documentation — Altair", description: "The Altair documentation: install, usage, features and the CLI reference." },
  "docs/install": { title: "Install — Altair", description: "Download and set up Altair on Linux, macOS or Windows with one command and checksum verification." },
  "docs/usage": { title: "Usage — Altair", description: "Create a project, generate a scaffold and run the server with the Altair CLI." },
  "docs/features": { title: "What is implemented — Altair", description: "The current state of the Altair framework, phase by phase." },
  "docs/cli": { title: "CLI reference — Altair", description: "Every Altair command and generator." },
};

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
    .replaceAll('src="/', `src="${rootPrefix}`);
  const m = meta[page];
  return layout
    .replaceAll("{{home}}", rootPrefix ? rootPrefix : "index.html")
    .replaceAll("{{root}}", rootPrefix)
    .replaceAll("{{title}}", m.title)
    .replaceAll("{{description}}", m.description)
    .replaceAll("{{content}}", body);
}

const indexHtml = render("index");
writeFileSync(join(root, "index.html"), indexHtml);

mkdirSync(join(root, "docs"), { recursive: true });
for (const page of ["index", "install", "usage", "features", "cli"]) {
  writeFileSync(join(root, "docs", `${page}.html`), render(`docs/${page}`));
}

console.log("Built website/: index.html + docs/{index,install,usage,features,cli}.html");
