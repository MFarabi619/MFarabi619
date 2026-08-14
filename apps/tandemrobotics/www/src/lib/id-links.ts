import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { visit } from "unist-util-visit";

const DOCS_DIR = fileURLToPath(new URL("../content/docs/", import.meta.url));
const ID_PROPERTY = /:ID:\s+(\S+)/;

export function docsUrl(slug: string): string {
  return slug === "index" ? "/docs" : `/docs/${slug}`;
}

function orgFiles(dir: string): string[] {
  const found: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) found.push(...orgFiles(full));
    else if (entry.name.endsWith(".org")) found.push(full);
  }
  return found;
}

export function buildIdMap(): Map<string, string> {
  const idToUrl = new Map<string, string>();
  for (const file of orgFiles(DOCS_DIR)) {
    const match = fs.readFileSync(file, "utf8").match(ID_PROPERTY);
    if (!match) continue;
    const slug = path.relative(DOCS_DIR, file).replace(/\.org$/, "");
    idToUrl.set(match[1], docsUrl(slug));
  }
  return idToUrl;
}

export function resolveIdLinks(idToUrl: Map<string, string>) {
  return () => (tree: unknown) => {
    // biome-ignore lint/suspicious/noExplicitAny: hast nodes
    visit(tree as any, "element", (node: any) => {
      if (node.tagName !== "a") return;
      const href = node.properties?.href;
      if (typeof href !== "string" || !href.startsWith("id:")) return;
      const url = idToUrl.get(href.slice(3));
      if (url) node.properties.href = url;
    });
  };
}
