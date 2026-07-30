import type { Element, Root as HastRoot } from "hast";
import type { Plugin } from "unified";
import type { Headline, OrgData } from "uniorg";
import { toString } from "orgast-util-to-string";
import type { VFile } from "vfile";
import { SKIP, visit } from "unist-util-visit";

interface TocHeading {
  depth: number;
  title: string;
  url: string;
}

function headingId(headline: Headline): string | undefined {
  const data = headline.data as { hProperties?: { id?: unknown } } | undefined;
  const id = data?.hProperties?.id;
  return typeof id === "string" ? id : undefined;
}

function astroFrontmatter(file: VFile): Record<string, unknown> {
  const data = file.data as {
    astro?: { frontmatter: Record<string, unknown> };
  };
  return (data.astro ??= { frontmatter: {} }).frontmatter;
}

function isHeadline(node: unknown): node is Headline {
  return (node as { type?: string }).type === "headline";
}

export const normalizeHeadingLevels: Plugin<[], HastRoot> = () => (tree) => {
  visit(tree, "element", (node: Element) => {
    const match = /^h([1-5])$/.exec(node.tagName);
    if (match) {
      node.tagName = `h${Number(match[1]) + 1}`;
    }
  });
};

export const collectTableOfContents: Plugin<[], OrgData> =
  () => (tree, file) => {
    const headings: TocHeading[] = [];
    visit(tree, isHeadline, (headline) => {
      const id = headingId(headline);
      if (!id) return;
      headings.push({
        depth: headline.level + 1,
        title: toString(headline),
        url: `#${id}`,
      });
    });
    astroFrontmatter(file).headings = headings;
  };

export const collectSearchIndex: Plugin<[], OrgData> = () => (tree, file) => {
  const headings: { id: string; content: string }[] = [];
  const contents: { heading: string | undefined; content: string }[] = [];
  let enclosingHeading: string | undefined;
  visit(tree, (node) => {
    if (isHeadline(node)) {
      const id = headingId(node);
      if (id) {
        enclosingHeading = id;
        headings.push({ id, content: toString(node) });
      }
      return SKIP;
    }
    if (node.type === "paragraph") {
      const content = toString(node).trim();
      if (content) contents.push({ heading: enclosingHeading, content });
      return SKIP;
    }
  });
  astroFrontmatter(file).structuredData = { headings, contents };
};
