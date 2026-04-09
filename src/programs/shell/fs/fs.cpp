#include "fs.h"

void root_mount(struct ush_object *ush);
void etc_mount(struct ush_object *ush);
void dev_mount(struct ush_object *ush);
void dev_bus_mount(struct ush_object *ush);
void dev_mem_mount(struct ush_object *ush);
void dev_ssh_mount(struct ush_object *ush);
void dev_sensors_mount(struct ush_object *ush);
void dev_sd_mount(struct ush_object *ush);
void bin_mount(struct ush_object *ush);

void fs_mount(struct ush_object *ush) {
  root_mount(ush);          // /
  etc_mount(ush);           // /etc
  dev_mount(ush);           // /dev
  dev_bus_mount(ush);       // /dev/bus
  dev_mem_mount(ush);       // /dev/mem
  dev_ssh_mount(ush);       // /dev/ssh
  dev_sensors_mount(ush);   // /dev/sensors
  dev_sd_mount(ush);        // /dev/sd
  bin_mount(ush);           // /bin
}
