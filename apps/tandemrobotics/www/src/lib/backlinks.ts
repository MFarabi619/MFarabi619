import { getCollection } from "astro:content";
import * as path from "node:path";
import { docsUrl } from "@/lib/id-links";

const ID_PROPERTY = /:ID:\s+(\S+)/;
const ID_LINK = /\[\[id:([^\]\[]+)\]/g;

export interface Backlink {
  title: string;
  url: string;
}

let cache: Map<string, Backlink[]> | null = null;

async function build(): Promise<Map<string, Backlink[]>> {
  const notes = (await getCollection("docs")).map((entry) => {
    const slug = path
      .relative("src/content/docs", entry.filePath!)
      .replace(/\.org$/, "");
    const body = entry.body ?? "";
    return {
      url: docsUrl(slug),
      title: entry.data.title,
      id: body.match(ID_PROPERTY)?.[1],
      outbound: [...body.matchAll(ID_LINK)].map((match) => match[1]),
    };
  });

  const idToUrl = new Map<string, string>();
  for (const note of notes) if (note.id) idToUrl.set(note.id, note.url);

  const backlinks = new Map<string, Backlink[]>();
  for (const note of notes) {
    for (const targetId of note.outbound) {
      const targetUrl = idToUrl.get(targetId);
      if (!targetUrl || targetUrl === note.url) continue;
      const list = backlinks.get(targetUrl) ?? [];
      if (!list.some((entry) => entry.url === note.url)) {
        list.push({ title: note.title, url: note.url });
      }
      backlinks.set(targetUrl, list);
    }
  }
  return backlinks;
}

export async function getBacklinks(url: string): Promise<Backlink[]> {
  cache ??= await build();
  return cache.get(url) ?? [];
}
