import type { APIRoute } from "astro";
import { createFromSource } from "fumadocs-core/search/server";
import { source } from "@/lib/source";

const server = createFromSource(source);

export const GET: APIRoute = () => server.staticGET();
