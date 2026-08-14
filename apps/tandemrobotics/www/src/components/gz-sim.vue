<script setup lang="ts">
import { SceneManager } from "gzweb";
import { onBeforeUnmount, onMounted, ref } from "vue";

const props = withDefaults(
  defineProps<{ websocketUrl?: string; websocketKey?: string }>(),
  {
    websocketUrl: import.meta.env.PUBLIC_GZ_WS_URL ?? "ws://localhost:9002",
    websocketKey: import.meta.env.PUBLIC_GZ_WS_KEY ?? "",
  },
);

const elementId = "gz-scene";
const status = ref("disconnected");
const models = ref<string[]>([]);
const followTarget = ref("");

let manager: SceneManager | undefined;
let pollTimer: ReturnType<typeof setInterval> | undefined;

function resize() {
  manager?.resize();
}

function refreshModels() {
  models.value = (manager?.getModels() ?? [])
    .map((model) => model?.name ?? "")
    .filter(Boolean);
}

onMounted(() => {
  manager = new SceneManager({
    elementId,
    websocketUrl: props.websocketUrl,
    websocketKey: props.websocketKey || undefined,
  });
  window.addEventListener("resize", resize);
  pollTimer = setInterval(() => {
    status.value = manager?.getConnectionStatus() ?? "disconnected";
    if (status.value === "connected" || status.value === "ready")
      refreshModels();
  }, 1000);
});

onBeforeUnmount(() => {
  window.removeEventListener("resize", resize);
  if (pollTimer) clearInterval(pollTimer);
  manager?.destroy();
});

const isLive = () => status.value === "connected" || status.value === "ready";
</script>

<template>
  <div class="relative h-full w-full">
    <div :id="elementId" class="h-full w-full" />

    <div
      class="tui-frame absolute right-4 top-4 flex flex-col gap-3 bg-fd-background/80 p-3 backdrop-blur"
    >
      <div class="flex items-center gap-2 text-sm">
        <span
          class="inline-block size-2"
          :class="{
            'bg-green-500': status === 'ready' || status === 'connected',
            'bg-yellow-500': status === 'connecting',
            'bg-red-500': status === 'error',
            'bg-fd-muted-foreground': status === 'disconnected',
          }"
        />
        <span class="font-display">{{ status }}</span>
      </div>

      <div class="flex gap-2">
        <button
          type="button"
          class="tui-frame px-3 py-1 text-sm hover:bg-fd-accent"
          @click="manager?.resetView()"
        >
          Reset view
        </button>
        <button
          type="button"
          class="tui-frame px-3 py-1 text-sm hover:bg-fd-accent"
          @click="manager?.snapshot()"
        >
          Screenshot
        </button>
      </div>

      <div v-if="models.length" class="flex gap-2">
        <select
          v-model="followTarget"
          class="tui-frame bg-fd-background px-2 py-1 text-sm"
        >
          <option value="">Follow model…</option>
          <option v-for="name in models" :key="name" :value="name">
            {{ name }}
          </option>
        </select>
        <button
          type="button"
          class="tui-frame px-3 py-1 text-sm hover:bg-fd-accent disabled:opacity-40"
          :disabled="!followTarget"
          @click="manager?.follow(followTarget)"
        >
          Follow
        </button>
      </div>
    </div>

    <p
      v-if="!isLive()"
      class="absolute inset-x-0 bottom-6 text-center text-sm text-fd-muted-foreground"
    >
      Connecting to <code>{{ websocketUrl }}</code> — start a Gazebo
      <code>WebsocketServer</code> to see the live scene.
    </p>
  </div>
</template>
