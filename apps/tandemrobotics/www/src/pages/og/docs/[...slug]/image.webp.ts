import type { APIRoute } from "astro";
import { createElement } from "react";
import { ImageResponse } from "takumi-js/response";
import { generate as DefaultImage } from "fumadocs-ui/og/takumi";
import { docsStaticPaths, source } from "@/lib/source";

export const getStaticPaths = docsStaticPaths;

export const GET: APIRoute = ({ params }) => {
  const slugs =
    params.slug?.split("/").filter((segment) => segment.length > 0) ?? [];
  const page = source.getPage(slugs);

  if (!page) return new Response(undefined, { status: 404 });

  return new ImageResponse(
    createElement(DefaultImage, {
      title: page.data.title,
      description: page.data.description,
      site: "Astro",
    }),
    {
      width: 1200,
      height: 630,
      format: "webp",
    },
  );
};
