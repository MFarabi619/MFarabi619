import { DocsLayout } from "fumadocs-ui/layouts/notebook";
import {
  DocsPage,
  type DocsPageProps,
} from "fumadocs-ui/layouts/notebook/page";
import { HomeLayout } from "fumadocs-ui/layouts/home";
import {
  deserializePageTree,
  type SerializedPageTree,
} from "fumadocs-core/source/client";
import type { ReactNode } from "react";
import { navigate } from "astro:transitions/client";
import { RootProvider } from "fumadocs-ui/provider/astro";
import type { AstroProviderProps } from "fumadocs-core/framework/astro";
import { baseOptions } from "@/lib/layout.shared";
import SearchDialog from "@/components/search";

type AstroParams = AstroProviderProps["params"];

function Providers({
  pathname,
  params,
  children,
}: {
  pathname: string;
  params: AstroParams;
  children: ReactNode;
}) {
  return (
    <RootProvider
      pathname={pathname}
      params={params}
      navigate={navigate}
      search={{ SearchDialog }}
    >
      {children}
    </RootProvider>
  );
}

export function Docs({
  tree,
  page,
  pathname,
  params,
  children,
}: {
  tree: SerializedPageTree;
  page?: DocsPageProps;
  pathname: string;
  params: AstroParams;
  children: ReactNode;
}) {
  return (
    <Providers pathname={pathname} params={params}>
      <DocsLayout {...baseOptions} tree={deserializePageTree(structuredClone(tree))}>
        <DocsPage {...page}>{children}</DocsPage>
      </DocsLayout>
    </Providers>
  );
}

export function Home({
  pathname,
  params,
  children,
}: {
  pathname: string;
  params: AstroParams;
  children: ReactNode;
}) {
  return (
    <Providers pathname={pathname} params={params}>
      <HomeLayout {...baseOptions}>{children}</HomeLayout>
    </Providers>
  );
}
