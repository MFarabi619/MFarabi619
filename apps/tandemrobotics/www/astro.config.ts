import mdx from "@astrojs/mdx";
import react from "@astrojs/react";
import { unified } from "@astrojs/markdown-remark";

import vue from "@astrojs/vue";
import { templateCompilerOptions } from "@tresjs/core";
import AstroPWA from "@vite-pwa/astro";
import org from "astro-org";
import { defineConfig, fontProviders } from "astro/config";

import tailwindcss from "@tailwindcss/vite";
import Icons from "unplugin-icons/vite";

import {
  collectSearchIndex,
  collectTableOfContents,
  normalizeHeadingLevels,
} from "./src/lib/org-plugins.ts";

import { buildIdMap, resolveIdLinks } from "./src/lib/id-links.ts";

const orgIdMap = buildIdMap();

import {
  rehypeCode,
  remarkCodeTab,
  remarkHeading,
  remarkNpm,
  remarkStructure,
} from "fumadocs-core/mdx-plugins";

const remarkPlugins = [
  remarkHeading,
  remarkCodeTab,
  remarkNpm,
  [remarkStructure, { exportAs: "structuredData" }],
];

const rehypePlugins = [rehypeCode];

type UnifiedOptions = NonNullable<Parameters<typeof unified>[0]>;

export default defineConfig({
  server: {
    port: 4321,
    host: true,
    allowedHosts: [".tandemrobotics.ca"],
  },

  site: "https://www.tandemrobotics.ca",
  srcDir: "./src",
  publicDir: "../../robot/assets/public",
  fonts: [
    {
      provider: fontProviders.fontsource(),
      name: "JetBrains Mono",
      cssVariable: "--font-jetbrains-mono",
      weights: [400, 500, 600, 700],
      fallbacks: ["monospace"],
    },
    {
      provider: fontProviders.fontsource(),
      name: "Silkscreen",
      cssVariable: "--font-silkscreen",
      weights: [400, 700],
      fallbacks: ["monospace"],
    },
  ],
  markdown: {
    processor: unified({
      remarkPlugins: remarkPlugins as UnifiedOptions["remarkPlugins"],
      rehypePlugins: rehypePlugins as UnifiedOptions["rehypePlugins"],
    }),
  },

  integrations: [
    react(),
    vue(templateCompilerOptions),
    org({
      uniorgPlugins: [collectTableOfContents, collectSearchIndex],
      rehypePlugins: [
        normalizeHeadingLevels,
        resolveIdLinks(orgIdMap),
        rehypeCode,
      ],
    }),
    mdx({
      extendMarkdownConfig: true,
      syntaxHighlight: false,
    }),
    AstroPWA({
      registerType: "autoUpdate",
      pwaAssets: { config: true },
      manifest: {
        name: "Tandem Robotics",
        short_name: "Tandem",
        description: "Autonomous mobile robots built for real-world work.",
        theme_color: "#282828",
        background_color: "#282828",
        display: "standalone",
      },
      workbox: {
        globPatterns: ["**/*.{js,css,html,svg,png,ico,webp,woff2,json}"],
        maximumFileSizeToCacheInBytes: 3_000_000,
      },
    }),
  ],

  vite: {
    plugins: [tailwindcss(), Icons({ compiler: "jsx", jsx: "react" })],
    preview: {
      allowedHosts: [".tandemrobotics.ca"],
    },
  },
});
