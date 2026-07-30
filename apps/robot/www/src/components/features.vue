<script setup lang="ts">
// import FeyCards from "@/components/fey-cards.vue";

// const feyImages = [
//   "https://cdn.inspira-ui.com/images/1.webp",
//   "https://cdn.inspira-ui.com/images/2.webp",
//   "https://cdn.inspira-ui.com/images/3.webp",
//   "https://cdn.inspira-ui.com/images/4.webp",
//   "https://cdn.inspira-ui.com/images/5.webp",
// ];

const iconBase =
  "https://raw.githubusercontent.com/MFarabi619/MFarabi619/main/assets/icons";

const tech: Record<string, { img: string; href: string }> = {
  Rust: { img: `${iconBase}/rust.svg`, href: "https://www.rust-lang.org" },
  Zephyr: { img: `${iconBase}/zephyr.png`, href: "https://zephyrproject.org" },
  "ROS 2": {
    img: `${iconBase}/ros2-jazzy-robot.png`,
    href: "https://www.ros.org",
  },
  Zig: { img: `${iconBase}/zig.svg`, href: "https://ziglang.org" },
  "C++": { img: `${iconBase}/cplusplus.svg`, href: "https://isocpp.org" },
  Devicetree: {
    img: `${iconBase}/devicetree.svg`,
    href: "https://www.devicetree.org",
  },
  Nix: { img: `${iconBase}/nix.svg`, href: "https://nixos.org" },
};

const features = [
  {
    label: "01",
    title: "Runs the rows on its own",
    body: "Map your field once and Tandem drives it for you — planning its path, holding the line down every row, and steering around obstacles as they appear. Depth cameras, an IMU, and GPS keep it located to field-grade accuracy.",
    image: "/robot-backyard-1.webp",
    stack: ["ROS 2", "Zephyr"],
  },
  {
    label: "02",
    title: "Built to take the field",
    body: "A full-metal chassis and a dead-simple drivetrain mean fewer parts to fail and a machine that shrugs off rough ground. Built in Canada, for Canadian farms.",
    image: "/robot-backyard-2.webp",
    stack: ["Devicetree", "C++", "Zephyr"],
  },
  {
    label: "03",
    title: "Yours to keep",
    body: "You own it end to end — no subscriptions, no lock-in, no strings. Full right to repair, right down to the source.",
    image: "/rutebega-data-logger-with-robot.webp",
    stack: ["Rust", "Zig", "Nix", "C++"],
  },
];
</script>

<template>
  <section class="flex flex-col gap-16">
    <h2 class="font-display text-2xl">Features</h2>
    <div
      v-for="(feature, index) in features"
      :key="feature.title"
      class="grid items-center gap-8 sm:grid-cols-2"
    >
      <div :class="index % 2 === 1 ? 'sm:order-2' : ''">
        <p class="font-display mb-3 text-fd-primary">{{ feature.label }}</p>
        <h3 class="mb-4 text-xl font-semibold">{{ feature.title }}</h3>
        <p class="mb-6 text-fd-muted-foreground">{{ feature.body }}</p>
        <div class="flex flex-wrap gap-2">
          <a
            v-for="name in feature.stack"
            :key="name"
            :href="tech[name].href"
            target="_blank"
            rel="noopener"
            :title="name"
            class="tui-frame flex size-11 items-center justify-center p-2 transition-colors hover:bg-fd-accent"
          >
            <img
              :src="tech[name].img"
              :alt="name"
              class="h-full w-full object-contain"
            />
          </a>
        </div>
      </div>
      <figure
        class="tui-frame p-2"
        :class="index % 2 === 1 ? 'sm:order-1' : ''"
        :data-label="feature.label"
      >
        <img
          :src="feature.image"
          :alt="feature.title"
          class="aspect-[4/3] w-full object-cover"
        />
      </figure>
    </div>

    <!-- <FeyCards
      :img-src="feyImages"
      main-img="https://cdn.inspira-ui.com/images/main.webp"
      idle-img="https://cdn.inspira-ui.com/images/idle.webp"
      class="text-black dark:text-white"
    >
      Inspired by the pros. Made for you.
    </FeyCards> -->
  </section>
</template>
