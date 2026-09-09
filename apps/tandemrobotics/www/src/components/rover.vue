<script setup lang="ts">
import { useGLTF } from "@tresjs/cientos";
import { useLoop } from "@tresjs/core";
import { Box3, MathUtils, Vector3 } from "three";
import { onMounted, onUnmounted, shallowRef, watch } from "vue";

const props = defineProps<{ paused?: boolean }>();

const { state: model } = useGLTF("/robot.glb", { draco: true });

const group = shallowRef();

watch(model, (loaded) => {
  const scene = loaded?.scene;
  if (!scene) return;
  const box = new Box3().setFromObject(scene);
  const size = box.getSize(new Vector3());
  const center = box.getCenter(new Vector3());
  const scale = 1 / Math.max(size.x, size.y, size.z);
  scene.scale.setScalar(scale);
  scene.position.set(-center.x * scale, -box.min.y * scale, -center.z * scale);
});

const pointer = { x: 0 };
function onPointerMove(event: PointerEvent) {
  pointer.x = (event.clientX / window.innerWidth) * 2 - 1;
}
onMounted(() => window.addEventListener("pointermove", onPointerMove));
onUnmounted(() => window.removeEventListener("pointermove", onPointerMove));

const { onBeforeRender } = useLoop();
onBeforeRender(() => {
  if (!group.value || props.paused) return;
  group.value.rotation.y = MathUtils.lerp(group.value.rotation.y, pointer.x * 0.5, 0.06);
});
</script>

<template>
  <TresGroup ref="group">
    <primitive v-if="model?.scene" :object="model.scene" />
  </TresGroup>
</template>
