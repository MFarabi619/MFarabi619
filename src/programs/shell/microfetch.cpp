#include "microfetch.h"
#include "../../config.h"
#include "../../console/icons.h"
#include "../../drivers/tca9548a.h"
#include "../../networking/wifi.h"
#include "../../services/temperature_and_humidity.h"

#include <Arduino.h>
#include <WiFi.h>
#include <LittleFS.h>
#include <SD.h>
#include <microshell.h>

static char fetch_buf[2048];

static int fetch_pos;
static int fetch_remaining;

static void row(const char *color, const char *icon, const char *label, const char *fmt, ...) {
  int space = fetch_remaining;
  if (space <= 0) return;

  int n = snprintf(fetch_buf + fetch_pos, space,
    "  \x1b[1;%sm%s %-14s\x1b[0m ", color, icon, label);
  if (n > 0 && n < space) { fetch_pos += n; fetch_remaining -= n; }

  va_list args;
  va_start(args, fmt);
  n = vsnprintf(fetch_buf + fetch_pos, fetch_remaining, fmt, args);
  va_end(args);
  if (n > 0 && n < fetch_remaining) { fetch_pos += n; fetch_remaining -= n; }

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "\r\n");
  if (n > 0 && n < fetch_remaining) { fetch_pos += n; fetch_remaining -= n; }
}

const char *microfetch_generate(void) {
  fetch_pos = 0;
  fetch_remaining = sizeof(fetch_buf) - 1;

  uint32_t uptime = millis() / 1000;
  uint32_t heap_free = ESP.getFreeHeap();
  uint32_t heap_total = ESP.getHeapSize();
  uint32_t heap_pct = heap_total > 0 ? ((heap_total - heap_free) * 100) / heap_total : 0;

  int n;

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "\r\n");
  fetch_pos += n; fetch_remaining -= n;

  const char *hostname = WiFi.getHostname();
  if (!hostname || hostname[0] == '\0') hostname = CONFIG_HOSTNAME;

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining,
    "  \x1b[1;32m%s\x1b[0m\x1b[2m@\x1b[0m\x1b[1;36m%s\x1b[0m\r\n",
    CONFIG_SSH_USER, hostname);
  fetch_pos += n; fetch_remaining -= n;

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "  \x1b[2m");
  fetch_pos += n; fetch_remaining -= n;
  size_t sep_len = strlen(CONFIG_SSH_USER) + 1 + strlen(hostname);
  for (size_t i = 0; i < sep_len && fetch_remaining > 1; i++) {
    fetch_buf[fetch_pos++] = '-';
    fetch_remaining--;
  }
  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "\x1b[0m\r\n");
  fetch_pos += n; fetch_remaining -= n;

  row("33", NF_FA_MICROCHIP, "OS", "\x1b[1mceratina\x1b[0m (%s)", CONFIG_PLATFORM);
  row("35", NF_FA_DESKTOP, "Host", "\x1b[1m%s\x1b[0m (rev %d)", ESP.getChipModel(), ESP.getChipRevision());
  row("36", NF_FA_COG, "Kernel", "\x1b[1mArduino\x1b[0m / ESP-IDF %s", ESP.getSdkVersion());

  uint32_t d = uptime / 86400, h = (uptime % 86400) / 3600;
  uint32_t m = (uptime % 3600) / 60, s = uptime % 60;
  if (d > 0) row("34", NF_FA_CLOCK, "Uptime", "\x1b[1m%u\x1b[0md %uh %um %us", d, h, m, s);
  else if (h > 0) row("34", NF_FA_CLOCK, "Uptime", "\x1b[1m%u\x1b[0mh %um %us", h, m, s);
  else row("34", NF_FA_CLOCK, "Uptime", "\x1b[1m%u\x1b[0mm %us", m, s);

  row("32", NF_FA_TERMINAL, "Shell", "\x1b[1mMicroShell\x1b[0m (SSH + WS)");
  row("31", NF_FA_MICROCHIP, "CPU", "\x1b[1mXtensa LX7\x1b[0m (%d) @ \x1b[1m%u MHz\x1b[0m",
      ESP.getChipCores(), (unsigned)ESP.getCpuFreqMHz());
  row("36", NF_FA_MEMORY, "RAM", "\x1b[1m%u/%u KiB\x1b[0m (\x1b[1;32m%u%%\x1b[0m)",
      (heap_total - heap_free) / 1024, heap_total / 1024, heap_pct);

  if (SD.begin(CONFIG_SD_CS_GPIO))
    row("32", NF_FA_HDD, "Disk (SD)", "\x1b[1m%llu MiB\x1b[0m", SD.totalBytes() / (1024*1024));
  else
    row("32", NF_FA_HDD, "Disk (SD)", "\x1b[2mnot detected\x1b[0m");

  if (LittleFS.totalBytes() > 0)
    row("32", NF_FA_DATABASE, "Disk (LFS)", "\x1b[1m%u/%u KiB\x1b[0m",
        (unsigned)(LittleFS.usedBytes()/1024), (unsigned)(LittleFS.totalBytes()/1024));

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "\r\n");
  fetch_pos += n; fetch_remaining -= n;

  if (WiFi.isConnected()) {
    row("33", NF_FA_WIFI, "WiFi", "\x1b[1m%s\x1b[0m (%ld dBm)", WiFi.SSID().c_str(), WiFi.RSSI());
    row("33", NF_FA_GLOBE, "Local IP", "\x1b[1m%s\x1b[0m", WiFi.localIP().toString().c_str());
  } else if (wifi_is_ap_active()) {
    row("33", NF_FA_WIFI, "WiFi", "\x1b[1mAP mode\x1b[0m (%u clients)", WiFi.softAPgetStationNum());
    row("33", NF_FA_GLOBE, "AP IP", "\x1b[1m%s\x1b[0m", WiFi.softAPIP().toString().c_str());
  } else {
    row("33", NF_FA_WIFI, "WiFi", "\x1b[2mnot connected\x1b[0m");
  }

  row("35", NF_FA_SERVER, "Hostname", "\x1b[1m%s\x1b[0m.local", hostname);
  row("34", NF_FA_GLOBE, "NTP", "\x1b[1m%s\x1b[0m", CONFIG_NTP_SERVER);
  row("36", NF_FA_PLUG, "Ports", "SSH:\x1b[1m%d\x1b[0m  HTTP:\x1b[1m%d\x1b[0m", CONFIG_SSH_PORT, CONFIG_HTTP_PORT);

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "\r\n");
  fetch_pos += n; fetch_remaining -= n;

  row("36", NF_FA_SITEMAP, "I2C Mux", "\x1b[1mTCA9548A\x1b[0m @ 0x%02X", CONFIG_I2C_MUX_ADDR);

  uint8_t thm_count = temperature_and_humidity_sensor_count();
  if (thm_count > 0)
    row("35", NF_FA_THERMOMETER, "Temp/Hum", "\x1b[1mCHT832X\x1b[0m x%d", thm_count);

  row("35", NF_FA_SIGNAL, "Voltage", "\x1b[1mADS1115\x1b[0m @ 0x%02X", CONFIG_VOLTAGE_MONITOR_I2C_ADDR);

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "\r\n");
  fetch_pos += n; fetch_remaining -= n;

  fetch_buf[fetch_pos] = '\0';
  return fetch_buf;
}

static void cmd_microfetch(struct ush_object *self,
                           struct ush_file_descriptor const *file,
                           int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  ush_print(self, (char *)microfetch_generate());
}

static const struct ush_file_descriptor microfetch_files[] = {
  { .name = "microfetch", .description = "system info summary",
    .help = "usage: microfetch\r\n", .exec = cmd_microfetch },
};

static struct ush_node_object microfetch_node;

void microfetch_register(struct ush_object *ush) {
  ush_commands_add(ush, &microfetch_node, microfetch_files,
                   sizeof(microfetch_files) / sizeof(microfetch_files[0]));
}
