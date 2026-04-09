#include "../../../networking/sntp.h"
#include "../../../helpers.h"

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
//  /dev/led — Neopixel status LED (GPIO 48)
//------------------------------------------
static uint8_t led_state = 0;

static size_t led_get_data(struct ush_object *self,
                           struct ush_file_descriptor const *file,
                           uint8_t **data) {
  (void)self; (void)file;
  *data = (uint8_t *)((led_state) ? "1\r\n" : "0\r\n");
  return strlen((char *)*data);
}

static void led_set_data(struct ush_object *self,
                         struct ush_file_descriptor const *file,
                         uint8_t *data, size_t size) {
  (void)self; (void)file;
  if (size < 1) return;
  if (data[0] == '1') {
    led_state = 1;
    digitalWrite(LED_BUILTIN, HIGH);
  } else if (data[0] == '0') {
    led_state = 0;
    digitalWrite(LED_BUILTIN, LOW);
  }
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
  { .name = "time",    .description = "millis() counter",
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
