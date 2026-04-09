#include "../../../networking/sntp.h"
#include "../../../helpers.h"
#include "../../../drivers/neopixel.h"

#include <Arduino.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  /dev/null — discard writes, empty reads
//------------------------------------------
static size_t null_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file; (void)data;
  return 0;
}

static void null_set_data(struct ush_object *self,
                          struct ush_file_descriptor const *file,
                          uint8_t *data, size_t size) {
  (void)self; (void)file; (void)data; (void)size;
}

//------------------------------------------
//  /dev/random — hardware RNG
//------------------------------------------
static size_t random_get_data(struct ush_object *self,
                              struct ush_file_descriptor const *file,
                              uint8_t **data) {
  (void)self; (void)file;
  static uint32_t r;
  r = esp_random();
  *data = (uint8_t *)&r;
  return sizeof(r);
}

//------------------------------------------
//  /dev/uptime — system uptime
//------------------------------------------
static size_t uptime_get_data(struct ush_object *self,
                              struct ush_file_descriptor const *file,
                              uint8_t **data) {
  (void)self; (void)file;
  static char buf[32];
  format_uptime(buf, sizeof(buf));
  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /dev/heap — heap memory usage
//------------------------------------------
static size_t heap_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file;
  static char buf[128];
  format_heap(buf, sizeof(buf));
  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /dev/time — local time (NTP-synced) or millis if no sync
//------------------------------------------
static size_t time_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file;
  static char buf[48];
  if (sntp_is_synced()) {
    snprintf(buf, sizeof(buf), "%s\r\n", sntp_local_time_string());
  } else {
    snprintf(buf, sizeof(buf), "%lu ms (no NTP sync)\r\n", millis());
  }
  *data = (uint8_t *)buf;
  return strlen(buf);
}

//------------------------------------------
//  /dev/led — Neopixel (write: off/red/green/blue/yellow/magenta/cyan/white)
//------------------------------------------
static size_t led_get_data(struct ush_object *self,
                           struct ush_file_descriptor const *file,
                           uint8_t **data) {
  (void)self; (void)file;
  static char buf[16];
  uint32_t color = neopixel_get_color();
  snprintf(buf, sizeof(buf), "%06lX\r\n", (unsigned long)color);
  *data = (uint8_t *)buf;
  return strlen(buf);
}

static void led_set_data(struct ush_object *self,
                         struct ush_file_descriptor const *file,
                         uint8_t *data, size_t size) {
  (void)self; (void)file;
  if (size < 1) return;
  char buf[16];
  size_t len = (size < sizeof(buf) - 1) ? size : sizeof(buf) - 1;
  memcpy(buf, data, len);
  buf[len] = '\0';
  while (len > 0 && (buf[len-1] == '\r' || buf[len-1] == '\n' || buf[len-1] == ' '))
    buf[--len] = '\0';

  if (strcmp(buf, "off") == 0 || strcmp(buf, "0") == 0)   neopixel_off();
  else if (strcmp(buf, "red") == 0)                        neopixel_red();
  else if (strcmp(buf, "green") == 0 || strcmp(buf, "1") == 0) neopixel_green();
  else if (strcmp(buf, "blue") == 0)                       neopixel_blue();
  else if (strcmp(buf, "yellow") == 0)                     neopixel_yellow();
  else if (strcmp(buf, "magenta") == 0)                    neopixel_magenta();
  else if (strcmp(buf, "cyan") == 0)                       neopixel_cyan();
  else if (strcmp(buf, "white") == 0)                      neopixel_white();
}

static const struct ush_file_descriptor dev_files[] = {
  { .name = "null",    .description = "discard sink",
    .get_data = null_get_data, .set_data = null_set_data },
  { .name = "random",  .description = "hardware RNG",
    .get_data = random_get_data },
  { .name = "uptime",  .description = "system uptime",
    .get_data = uptime_get_data },
  { .name = "heap",    .description = "heap memory usage",
    .get_data = heap_get_data },
  { .name = "time",    .description = "local time (NTP-synced)",
    .get_data = time_get_data },
  { .name = "led",     .description = "status LED",
    .get_data = led_get_data, .set_data = led_set_data },
};

static struct ush_node_object dev;

void dev_mount(struct ush_object *ush) {
  pinMode(LED_BUILTIN, OUTPUT);
  ush_node_mount(ush, "/dev", &dev, dev_files,
                 sizeof(dev_files) / sizeof(dev_files[0]));
}
