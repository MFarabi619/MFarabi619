<script setup lang="ts">
import { useTemplateRef } from "vue";
import AnimatedBeam from "@/components/animated-beam.vue";

const containerRef = useTemplateRef<HTMLElement>("containerRef");
const div1Ref = useTemplateRef<HTMLElement>("div1Ref");
const div2Ref = useTemplateRef<HTMLElement>("div2Ref");
const div3Ref = useTemplateRef<HTMLElement>("div3Ref");
const div4Ref = useTemplateRef<HTMLElement>("div4Ref");
const div5Ref = useTemplateRef<HTMLElement>("div5Ref");
const div6Ref = useTemplateRef<HTMLElement>("div6Ref");
const div7Ref = useTemplateRef<HTMLElement>("div7Ref");

const beam = {
  gradientStartColor: "var(--color-fd-primary)",
  gradientStopColor: "var(--color-fd-ring)",
  pathColor: "var(--color-fd-border)",
  duration: 4,
};

const nodeClass = "z-10 flex items-center justify-center";

const steps = [
  { title: "Deploy", body: "Roll the robot out to the site and power on." },
  { title: "Map", body: "Drive the perimeter once; the robot builds its map." },
  {
    title: "Operate",
    body: "It runs autonomous routes, avoiding obstacles on its own.",
  },
  { title: "Monitor", body: "Watch live telemetry from any browser." },
];
</script>

<template>
  <section>
    <h2 class="font-display mb-6 text-xl">How it works</h2>
    <div class="flex flex-col gap-6 border-l border-fd-border pl-8">
      <div v-for="(step, i) in steps" :key="step.title" class="relative">
        <span
          class="absolute top-0 -left-[2.35rem] flex size-6 items-center justify-center rounded-full border border-fd-border bg-fd-background text-xs"
        >
          {{ i + 1 }}
        </span>
        <h3 class="font-semibold">{{ step.title }}</h3>
        <p class="text-fd-muted-foreground">{{ step.body }}</p>
      </div>
    </div>

    <div
      ref="containerRef"
      class="relative flex w-full items-center justify-center overflow-hidden py-10"
    >
    <div
      class="flex size-full max-h-[200px] max-w-lg flex-col items-stretch justify-between gap-10"
    >
      <div class="flex flex-row items-center justify-between">
        <div ref="div1Ref" :class="[nodeClass, 'size-12']">
          <img src="/logos/ros.svg" alt="ROS 2" class="size-full object-contain" />
        </div>
        <div ref="div5Ref" :class="[nodeClass, 'size-12']">
          <img src="/logos/nav2.svg" alt="Nav2" class="size-full object-contain" />
        </div>
      </div>
      <div class="flex flex-row items-center justify-between">
        <div ref="div2Ref" :class="[nodeClass, 'size-12']">
          <img src="/logos/gazebo.svg" alt="Gazebo" class="size-full object-contain" />
        </div>
        <div ref="div4Ref" :class="[nodeClass, 'size-16']">
          <img src="/symbol.png" alt="Tandem Robotics" class="size-full object-contain" />
        </div>
        <div ref="div6Ref" :class="[nodeClass, 'size-12']">
          <img src="/logos/foxglove.svg" alt="Foxglove" class="size-full object-contain" />
        </div>
      </div>
      <div class="flex flex-row items-center justify-between">
        <div ref="div3Ref" :class="[nodeClass, 'size-12']">
          <img src="/logos/zenoh.png" alt="Zenoh" class="size-full object-contain" />
        </div>
        <div ref="div7Ref" :class="[nodeClass, 'size-12']">
          <img src="/logos/lichtblick.svg" alt="Lichtblick" class="size-full object-contain" />
        </div>
      </div>
    </div>

    <AnimatedBeam v-bind="beam" :container-ref="containerRef!" :from-ref="div1Ref!" :to-ref="div4Ref!" :curvature="-75" :end-y-offset="-10" />
    <AnimatedBeam v-bind="beam" :container-ref="containerRef!" :from-ref="div2Ref!" :to-ref="div4Ref!" :curvature="0" :end-y-offset="0" />
    <AnimatedBeam v-bind="beam" :container-ref="containerRef!" :from-ref="div3Ref!" :to-ref="div4Ref!" :curvature="75" :end-y-offset="10" />
    <AnimatedBeam v-bind="beam" :container-ref="containerRef!" :from-ref="div5Ref!" :to-ref="div4Ref!" :curvature="-75" :end-y-offset="-10" />
    <AnimatedBeam v-bind="beam" :container-ref="containerRef!" :from-ref="div6Ref!" :to-ref="div4Ref!" :curvature="0" :end-y-offset="0" />
    <AnimatedBeam v-bind="beam" :container-ref="containerRef!" :from-ref="div7Ref!" :to-ref="div4Ref!" :curvature="75" :end-y-offset="10" />
    </div>
  </section>
</template>
