import type { StaticSource } from "fumadocs-core/source";
import { loader } from "fumadocs-core/source";
import { type CollectionEntry, getCollection } from "astro:content";
import * as path from "node:path";
import { structure, type StructuredData } from "fumadocs-core/mdx-plugins";
import { icons } from "lucide-react";
import { createElement } from "react";

export const source = loader({
  source: await createDocsSource(),
  baseUrl: "/docs",
  icon(name) {
    if (name && name in icons) {
      return createElement(icons[name as keyof typeof icons]);
    }
  },
});

export function docsStaticPaths() {
  return source.getPages().map((page) => ({
    params: { slug: page.slugs.length > 0 ? page.slugs.join("/") : undefined },
  }));
}

export function getPageImage(slugs: string[]) {
  const segments = [...slugs, "image.webp"];

  return {
    segments,
    url: `/og/docs/${segments.join("/")}`,
  };
}

async function createDocsSource() {
  const staticSource: StaticSource<{
    metaData: CollectionEntry<"meta">["data"];
    pageData: Omit<CollectionEntry<"docs">["data"], "structuredData"> & {
      _raw: CollectionEntry<"docs">;
      structuredData: StructuredData | (() => StructuredData);
    };
  }> = {
    files: [],
  };

  for (const page of await getCollection("docs")) {
    const virtualPath = path.relative("src/content/docs", page.filePath!);

    staticSource.files.push({
      type: "page",
      path: virtualPath,
      data: {
        ...page.data,
        _raw: page,
        structuredData:
          (page.data.structuredData as StructuredData | undefined) ??
          (() => structure(page.body ?? "")),
      },
    });
  }

  for (const meta of await getCollection("meta")) {
    const virtualPath = path.relative("src/content/docs", meta.filePath!);

    staticSource.files.push({
      type: "meta",
      path: virtualPath,
      data: meta.data,
    });
  }

  return staticSource;
}
