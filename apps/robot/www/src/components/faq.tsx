import { Accordion, Accordions } from "fumadocs-ui/components/accordion";

export function Faq() {
  return (
    <section>
      <h2 className="font-display mb-6 text-xl">FAQ</h2>
      <Accordions>
        <Accordion title="Is it ....?">Answer answer</Accordion>
        <Accordion title="What hardware does it run on?">
          Something something
        </Accordion>
      </Accordions>
    </section>
  );
}
