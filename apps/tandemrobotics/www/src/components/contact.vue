<script setup lang="ts">
import BorderBeam from "@/components/border-beam.vue";
</script>

<template>
  <section class="tui-frame px-6 py-16 text-center" data-label="get-started">
    <BorderBeam
      :duration="8"
      color-from="var(--color-fd-primary)"
      color-to="var(--color-fd-ring)"
    />
    <h1 class="font-display mb-6 text-3xl sm:text-5xl">Tandem Robotics</h1>
    <p class="mx-auto mb-8 max-w-2xl text-lg text-fd-muted-foreground">
      Autonomous mobile robots built for farm work.
    </p>
    <div class="flex flex-wrap justify-center gap-3">
      <a
        href="/docs"
        class="border border-fd-primary bg-fd-primary px-6 py-2.5 font-medium text-fd-primary-foreground"
      >
        Read the docs
      </a>
      <a
        href="https://github.com/tandemrobotics"
        target="_blank"
        rel="noopener"
        class="border border-fd-border px-6 py-2.5 font-medium hover:bg-fd-accent"
      >
        View source
      </a>
    </div>
  </section>
</template>
