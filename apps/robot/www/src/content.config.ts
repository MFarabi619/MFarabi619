import { glob } from "astro/loaders";
import { defineCollection, z } from "astro:content";

const docs = defineCollection({
  loader: glob({ pattern: "**/*.{md,mdx,org}", base: "./src/content/docs" }),
  schema: z.object({
    title: z.string(),
    description: z.string().optional(),
    icon: z.string().optional(),
    headings: z
      .array(
        z.object({
          depth: z.number(),
          title: z.string(),
          url: z.string(),
        }),
      )
      .optional(),
    structuredData: z
      .object({
        headings: z.array(z.object({ id: z.string(), content: z.string() })),
        contents: z.array(
          z.object({
            heading: z.string().optional(),
            content: z.string(),
          }),
        ),
      })
      .optional(),
  }),
});

const meta = defineCollection({
  loader: glob({ pattern: "**/*.{json,yaml}", base: "./src/content/docs" }),
  schema: z.object({
    title: z.string().optional(),
    description: z.string().optional(),
    pages: z.array(z.string()).optional(),
    icon: z.string().optional(),
  }),
});

export const collections = {
  docs,
  meta,
};
