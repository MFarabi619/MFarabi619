#include "fs.h"

// Forward declarations — each mountpoint is in its own file
void root_mount(struct ush_object *ush);
void etc_mount(struct ush_object *ush);
void dev_mount(struct ush_object *ush);
void dev_bus_mount(struct ush_object *ush);
void dev_mem_mount(struct ush_object *ush);
void bin_mount(struct ush_object *ush);

void fs_mount(struct ush_object *ush) {
  root_mount(ush);      // /
  etc_mount(ush);       // /etc
  dev_mount(ush);       // /dev
  dev_bus_mount(ush);   // /dev/bus
  dev_mem_mount(ush);   // /dev/mem
  bin_mount(ush);       // /bin
}
