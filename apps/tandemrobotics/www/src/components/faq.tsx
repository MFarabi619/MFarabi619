import { Accordion, Accordions } from "fumadocs-ui/components/accordion";
// import {Link} from "next";

export function Faq() {
  return (
    <section>
      <h2 className="font-display mb-6 text-xl">FAQ</h2>
      <Accordions>
        <Accordion title="What's the warranty?">Work-in-progress.</Accordion>
        <Accordion title="What hardware does it run on?">
                                                           Please see docs.
        </Accordion>
      </Accordions>
    </section>
  );
}
