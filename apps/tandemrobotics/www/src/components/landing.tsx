import type { AstroProviderProps } from "fumadocs-core/framework/astro";
import type { ReactNode } from "react";
import { Faq } from "@/components/faq";
import { Home } from "@/layouts/fumadocs";

export function LandingPage({
  pathname,
  params,
  children,
  contact,
  howItWorks,
  features,
}: {
  pathname: string;
  params: AstroProviderProps["params"];
  children?: ReactNode;
  contact?: ReactNode;
  howItWorks?: ReactNode;
  features?: ReactNode;
}) {
  return (
    <Home pathname={pathname} params={params}>
      {children}
      <div className="mx-auto flex w-full max-w-5xl flex-col gap-20 px-6 py-16">
        {features}

        {howItWorks}

        <Faq />

        {contact}
      </div>
    </Home>
  );
}
