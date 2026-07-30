import type { AstroProviderProps } from "fumadocs-core/framework/astro";
import type { ReactNode } from "react";
import { Faq } from "@/components/faq";
import { Home } from "@/layouts/fumadocs";

// const lichtblickUrl =
//   "https://app.tandemrobotics.ca/?openIn=web&ds=foxglove-websocket&ds.url=wss://bridge.tandemrobotics.ca";

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
        {/* <section
          className="tui-frame aspect-[16/10] w-full"
          data-label="live control"
        >
          <iframe
            src={lichtblickUrl}
            title="Live robot telemetry"
            loading="lazy"
            className="h-full w-full"
            allow="camera; microphone"
          />
        </section> */}

        {features}

        {howItWorks}

        <Faq />

        {contact}
      </div>
    </Home>
  );
}
