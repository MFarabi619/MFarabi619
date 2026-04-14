#include "microfetch.h"
#include "../../config.h"
#include "../../console/icons.h"
#include "../../hardware/storage.h"
#include "../../hardware/i2c.h"
#include "../../networking/wifi.h"
#include "../../sensors/manager.h"
#include "../../services/identity.h"
#include "../../services/system.h"

#include <Arduino.h>
#include <Console.h>

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

const char *programs::shell::microfetch::generate(const char *transport) {
  fetch_pos = 0;
  fetch_remaining = sizeof(fetch_buf) - 1;

  SystemQuery system_query = {
    .preferred_storage = StorageKind::LittleFS,
    .snapshot = {},
  };
  services::system::accessSnapshot(&system_query);
  const SystemSnapshot &snapshot = system_query.snapshot;
  SensorInventorySnapshot inventory = {};
  sensors::manager::accessInventory(&inventory);
  uint32_t heap_pct = snapshot.heap_total > 0
      ? ((snapshot.heap_total - snapshot.heap_free) * 100) / snapshot.heap_total
      : 0;

  int n;

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "\r\n");
  fetch_pos += n; fetch_remaining -= n;

  const char *hostname = services::identity::accessHostname();

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

  row("33", NF_FA_MICROCHIP, "OS", "\x1b[1mceratina\x1b[0m (%s)", config::PLATFORM);
  row("35", NF_FA_DESKTOP, "Host", "\x1b[1m%s\x1b[0m (rev %d)", snapshot.chip_model, snapshot.chip_revision);
  row("36", NF_FA_COG, "Kernel", "\x1b[1mArduino\x1b[0m / ESP-IDF %s", snapshot.sdk_version);

  uint32_t d = snapshot.uptime_seconds / 86400, h = (snapshot.uptime_seconds % 86400) / 3600;
  uint32_t m = (snapshot.uptime_seconds % 3600) / 60, s = snapshot.uptime_seconds % 60;
  if (d > 0) row("34", NF_FA_CLOCK, "Uptime", "\x1b[1m%u\x1b[0md %uh %um %us", d, h, m, s);
  else if (h > 0) row("34", NF_FA_CLOCK, "Uptime", "\x1b[1m%u\x1b[0mh %um %us", h, m, s);
  else row("34", NF_FA_CLOCK, "Uptime", "\x1b[1m%u\x1b[0mm %us", m, s);

  row("32", NF_FA_TERMINAL, "Shell", "\x1b[1mMicroshell\x1b[0m (%s)", transport);
  row("31", NF_FA_MICROCHIP, "CPU", "\x1b[1mXtensa LX7\x1b[0m (%d) @ \x1b[1m%u MHz\x1b[0m",
      snapshot.chip_cores, (unsigned)snapshot.cpu_mhz);
  row("36", NF_FA_MEMORY, "RAM", "\x1b[1m%u/%u KiB\x1b[0m (\x1b[1;32m%u%%\x1b[0m)",
      (snapshot.heap_total - snapshot.heap_free) / 1024, snapshot.heap_total / 1024, heap_pct);

  StorageQuery sd_query = {
    .kind = StorageKind::SD,
    .snapshot = {},
  };
  if (hardware::storage::accessSnapshot(&sd_query))
    row("32", NF_FA_HDD, "Disk (SD)", "\x1b[1m%llu MiB\x1b[0m", sd_query.snapshot.total_bytes / (1024*1024));
  else
    row("32", NF_FA_HDD, "Disk (SD)", "\x1b[2mnot detected\x1b[0m");

  if (snapshot.storage.mounted)
    row("32", NF_FA_DATABASE, "Disk (LFS)", "\x1b[1m%u/%u KiB\x1b[0m",
        (unsigned)(snapshot.storage.used_bytes/1024), (unsigned)(snapshot.storage.total_bytes/1024));

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "\r\n");
  fetch_pos += n; fetch_remaining -= n;

  if (snapshot.network.connected) {
    row("33", NF_FA_WIFI, "WiFi", "\x1b[1m%s\x1b[0m (%ld dBm)", snapshot.network.ssid, snapshot.network.rssi);
    row("33", NF_FA_GLOBE, "Local IP", "\x1b[1m%s\x1b[0m", snapshot.network.ip);
  } else if (snapshot.network.ap.active) {
    row("33", NF_FA_WIFI, "WiFi", "\x1b[1mAP mode\x1b[0m (%u clients)", snapshot.network.ap.clients);
    row("33", NF_FA_GLOBE, "AP IP", "\x1b[1m%s\x1b[0m", snapshot.network.ap.ip);
  } else {
    row("33", NF_FA_WIFI, "WiFi", "\x1b[2mnot connected\x1b[0m");
  }

  row("35", NF_FA_SERVER, "Hostname", "\x1b[1m%s\x1b[0m.local", hostname);
  row("34", NF_FA_GLOBE, "NTP", "\x1b[1m%s\x1b[0m", config::sntp::SERVER_1);
  row("36", NF_FA_PLUG, "Ports", "SSH:\x1b[1m%d\x1b[0m  HTTP:\x1b[1m%d\x1b[0m", config::ssh::PORT, config::http::PORT);

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "\r\n");
  fetch_pos += n; fetch_remaining -= n;

  row("36", NF_FA_SITEMAP, "I2C Mux", "\x1b[1mTCA9548A\x1b[0m @ 0x%02X", config::i2c::MUX_ADDR);

  if (inventory.temperature_humidity_count > 0)
    row("35", NF_FA_THERMOMETER, "Temp/Hum", "\x1b[1mI2C sensors\x1b[0m x%d",
        inventory.temperature_humidity_count);
  

  row("35", NF_FA_SIGNAL, "Voltage", "\x1b[1mADS1115\x1b[0m @ 0x%02X", config::voltage::I2C_ADDR);

  n = snprintf(fetch_buf + fetch_pos, fetch_remaining, "\r\n");
  fetch_pos += n; fetch_remaining -= n;

  fetch_buf[fetch_pos] = '\0';
  return fetch_buf;
}

static int cmd_microfetch(int argc, char **argv) {
  (void)argc; (void)argv;
  printf("%s", programs::shell::microfetch::generate());
  return 0;
}

void programs::shell::microfetch::registerCmd() {
  Console.addCmd("microfetch", "system info summary", cmd_microfetch);
}
