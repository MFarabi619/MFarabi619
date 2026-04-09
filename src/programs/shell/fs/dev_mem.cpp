#include <Arduino.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  /dev/mem/heap — detailed heap stats
//------------------------------------------
static size_t heap_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file;
  static char buf[256];
  snprintf(buf, sizeof(buf),
           "internal:\r\n"
           "  total:     %u\r\n"
           "  free:      %u\r\n"
           "  min_free:  %u\r\n"
           "  max_alloc: %u\r\n",
           ESP.getHeapSize(),
           ESP.getFreeHeap(),
           ESP.getMinFreeHeap(),
           ESP.getMaxAllocHeap());
  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /dev/mem/psram — PSRAM stats
//------------------------------------------
static size_t psram_get_data(struct ush_object *self,
                             struct ush_file_descriptor const *file,
                             uint8_t **data) {
  (void)self; (void)file;
  static char buf[128];
  if (ESP.getPsramSize() > 0) {
    snprintf(buf, sizeof(buf),
             "total: %u\r\nfree:  %u\r\nused:  %u\r\n",
             ESP.getPsramSize(),
             ESP.getFreePsram(),
             ESP.getPsramSize() - ESP.getFreePsram());
  } else {
    snprintf(buf, sizeof(buf), "PSRAM not available\r\n");
  }
  *data = (uint8_t *)buf;
  return strlen(buf);
}

static const struct ush_file_descriptor mem_files[] = {
  { .name = "heap",  .description = "internal heap stats",
    .get_data = heap_get_data },
  { .name = "psram", .description = "PSRAM stats",
    .get_data = psram_get_data },
};

static struct ush_node_object mem;

void dev_mem_mount(struct ush_object *ush) {
  ush_node_mount(ush, "/dev/mem", &mem, mem_files,
                 sizeof(mem_files) / sizeof(mem_files[0]));
}
