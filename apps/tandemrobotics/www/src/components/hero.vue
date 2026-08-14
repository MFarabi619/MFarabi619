<script setup lang="ts">
import { ContactShadows, Environment, OrbitControls } from "@tresjs/cientos";
import { TresCanvas } from "@tresjs/core";
import { onMounted, onUnmounted, ref } from "vue";
import LampEffect from "@/components/lamp-effect.vue";
import Rover from "@/components/rover.vue";

const isGrabbed = ref(false);
const isZoomEnabled = ref(false);

function syncZoomFromCtrlKey(event: KeyboardEvent) {
  isZoomEnabled.value = event.ctrlKey;
}
function releaseZoom() {
  isZoomEnabled.value = false;
}
onMounted(() => {
  window.addEventListener("keydown", syncZoomFromCtrlKey);
  window.addEventListener("keyup", syncZoomFromCtrlKey);
  window.addEventListener("blur", releaseZoom);
});
onUnmounted(() => {
  window.removeEventListener("keydown", syncZoomFromCtrlKey);
  window.removeEventListener("keyup", syncZoomFromCtrlKey);
  window.removeEventListener("blur", releaseZoom);
});
</script>

<template>
  <section class="relative mx-auto flex min-h-[calc(100svh-3.5rem)] w-full max-w-6xl flex-col px-6 pt-8 pb-8">
    <p class="relative z-10 mt-2 text-center font-display text-sm tracking-widest text-fd-primary uppercase">Metal to Motion</p>
    <LampEffect class="absolute inset-x-0 top-[7%] h-[34%] min-h-0 [mask-image:linear-gradient(to_bottom,transparent,black_35%,black)]" />
    <div class="relative z-10 mx-auto mt-20 max-w-3xl text-center sm:mt-24">
      <h1 class="font-display text-4xl leading-tight sm:text-6xl">
        Autonomous Robots for the Rows
      </h1>
      <p class="mx-auto mt-12 max-w-2xl text-lg text-fd-foreground text-balance">
        Skilled hands are scarce and the rows never stop. Tandem maps your field,
        drives the rows on its own, and steers around whatever's in the way —
        watched live from any browser.
      </p>
      <div class="mt-8 flex flex-wrap justify-center gap-3">
        <a
          href="/docs"
          class="border border-fd-primary bg-fd-primary px-6 py-2.5 font-medium text-fd-primary-foreground"
        >
          Read the docs
        </a>
        <a
          href="/sim"
          class="border border-fd-border px-6 py-2.5 font-medium hover:bg-fd-accent"
        >
          Open the simulator
        </a>
      </div>
    </div>
    <div class="relative z-10 mt-auto aspect-[16/9] w-full">
      <TresCanvas class="h-full w-full" :alpha="true" :clear-alpha="0" clear-color="#000000">
        <TresPerspectiveCamera :position="[0.92, 0.64, 1.48]" :fov="42" :look-at="[0, 0.1, 0]" />
        <OrbitControls
          make-default
          :enable-damping="true"
          :enable-pan="false"
          :enable-zoom="isZoomEnabled"
          :min-distance="1"
          :max-distance="4.5"
          :max-polar-angle="1.5"
          @start="isGrabbed = true"
        />
        <TresAmbientLight :intensity="0.5" />
        <TresDirectionalLight :position="[4, 6, 3]" :intensity="1.4" />
        <Suspense>
          <Environment :files="'/env/studio.hdr'" />
        </Suspense>
        <ContactShadows
          :position="[0, 0, 0]"
          :opacity="0.5"
          :blur="2.6"
          :scale="2.8"
          :resolution="512"
        />
        <Rover :paused="isGrabbed" />
      </TresCanvas>
    </div>
  </section>
</template>
