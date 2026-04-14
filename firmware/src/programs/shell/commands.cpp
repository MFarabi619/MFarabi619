#include "commands.h"
#include <boot/system.h>
#include <networking/wifi.h>
#include "power/sleep.h"
#include "services/data_logger.h"
#include "../ssh/ssh_server.h"

#include <Arduino.h>
#include <Console.h>
#include <Esp.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <stdio.h>

static int cmd_reboot(int argc, char **argv) {
  (void)argc; (void)argv;
  printf("rebooting...\n");
  delay(100);
  ESP.restart();
  return 0;
}

static int cmd_wifi_set(int argc, char **argv) {
  if (argc != 3) {
    printf("usage: wifi-set <ssid> <password>\n");
    return 1;
  }
  WifiSavedConfig config = {};
  strlcpy(config.ssid, argv[1], sizeof(config.ssid));
  strlcpy(config.password, argv[2], sizeof(config.password));
  if (networking::wifi::storeConfig(&config))
    printf("saved. use wifi-connect to connect.\n");
  else
    printf("failed to save config.\n");
  return 0;
}

static int cmd_wifi_connect(int argc, char **argv) {
  (void)argc; (void)argv;
  printf("connecting...\n");
  if (networking::wifi::sta::connect()) {
    printf("connected, starting services...\n");
    boot::system::startServices();
  } else {
    printf("failed\n");
  }
  return 0;
}

static int cmd_ps(int argc, char **argv) {
  (void)argc; (void)argv;

  uint32_t count = uxTaskGetNumberOfTasks();
  TaskStatus_t *tasks = (TaskStatus_t *)malloc(count * sizeof(TaskStatus_t));
  if (!tasks) { printf("out of memory\n"); return 1; }

  uint32_t total_runtime = 0;
  uint32_t filled = uxTaskGetSystemState(tasks, count, &total_runtime);

  static const char *states[] = {"Run", "Rdy", "Blk", "Sus", "Del", "Inv"};

  printf("%-16s %4s %4s %5s %4s\n", "NAME", "STAT", "PRI", "STACK", "CORE");

  for (uint32_t i = 0; i < filled; i++) {
    int state = (int)tasks[i].eCurrentState;
    if (state > 5) state = 5;
    int core = (int)tasks[i].xCoreID;

    printf("%-16s %4s %4lu %5lu %4s\n",
           tasks[i].pcTaskName, states[state],
           (unsigned long)tasks[i].uxCurrentPriority,
           (unsigned long)tasks[i].usStackHighWaterMark,
           core == tskNO_AFFINITY ? "*" : (core == 0 ? "0" : "1"));
  }

  ::free(tasks);
  return 0;
}

static int cmd_cpu(int argc, char **argv) {
  if (argc == 2) {
    uint32_t mhz = atoi(argv[1]);
    if (mhz != 80 && mhz != 160 && mhz != 240) {
      printf("usage: cpu [80|160|240]\n");
      return 1;
    }
    setCpuFrequencyMhz(mhz);
    printf("CPU set to %lu MHz\n", (unsigned long)mhz);
    return 0;
  }
  printf("%lu MHz\n", (unsigned long)ESP.getCpuFreqMHz());
  return 0;
}

static int cmd_sleep(int argc, char **argv) {
  if (argc != 1 && argc != 2) {
    printf("usage: sleep [seconds]\n");
    return 1;
  }

  SleepCommand command = {};
  bool ok = false;
  if (argc == 2) {
    command.duration_seconds = static_cast<uint32_t>(atoi(argv[1]));
    ok = power::sleep::request(&command);
  } else {
    ok = power::sleep::requestConfigured(&command);
  }

  if (ok)
    printf("sleeping in %lu second(s)...\n", (unsigned long)command.duration_seconds);
  else
    printf("invalid or disabled sleep configuration\n");
  return ok ? 0 : 1;
}

static int cmd_wakecause(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: wakecause\n"); return 1; }
  printf("%s\n", power::sleep::accessWakeCause());
  return 0;
}

static int cmd_sleep_status(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: sleep-status\n"); return 1; }

  SleepStatusSnapshot snapshot = {};
  power::sleep::accessStatus(&snapshot);
  printf("pending=%s\n"
         "requested_duration_seconds=%lu\n"
         "wake_cause=%s\n"
         "timer_wakeup_enabled=%s\n"
         "timer_wakeup_us=%llu\n"
         "config_enabled=%s\n"
         "default_duration_seconds=%lu\n",
         snapshot.pending ? "true" : "false",
         (unsigned long)snapshot.requested_duration_seconds,
         snapshot.wake_cause,
         snapshot.timer_wakeup_enabled ? "true" : "false",
         (unsigned long long)snapshot.timer_wakeup_us,
         snapshot.config_enabled ? "true" : "false",
         (unsigned long)snapshot.default_duration_seconds);
  return 0;
}

static int cmd_sleep_config(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: sleep-config\n"); return 1; }

  SleepConfig config = {};
  if (!power::sleep::accessConfig(&config)) {
    printf("sleep config unavailable\n");
    return 1;
  }
  printf("enabled=%s\nduration_seconds=%lu\n",
         config.enabled ? "true" : "false",
         (unsigned long)config.duration_seconds);
  return 0;
}

static int cmd_sleep_enable(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: sleep-enable\n"); return 1; }
  SleepConfig config = {};
  if (!power::sleep::accessConfig(&config)) { printf("sleep config unavailable\n"); return 1; }
  config.enabled = true;
  if (power::sleep::storeConfig(&config))
    printf("sleep config enabled\n");
  else
    printf("failed to save sleep config\n");
  return 0;
}

static int cmd_sleep_disable(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: sleep-disable\n"); return 1; }
  SleepConfig config = {};
  if (!power::sleep::accessConfig(&config)) { printf("sleep config unavailable\n"); return 1; }
  config.enabled = false;
  power::sleep::abortPending();
  if (power::sleep::storeConfig(&config))
    printf("sleep config disabled\n");
  else
    printf("failed to save sleep config\n");
  return 0;
}

static int cmd_sleep_duration(int argc, char **argv) {
  if (argc != 2) { printf("usage: sleep-duration <seconds>\n"); return 1; }
  SleepConfig config = {};
  if (!power::sleep::accessConfig(&config)) { printf("sleep config unavailable\n"); return 1; }
  config.duration_seconds = static_cast<uint32_t>(atoi(argv[1]));
  if (power::sleep::storeConfig(&config))
    printf("default sleep duration set to %lu second(s)\n", (unsigned long)config.duration_seconds);
  else
    printf("invalid sleep duration\n");
  return 0;
}

static int cmd_log_status(int argc, char **argv) {
  (void)argv;
  if (argc != 1) { printf("usage: log-status\n"); return 1; }

  DataLoggerStatusSnapshot snapshot = {};
  services::data_logger::accessStatus(&snapshot);
  printf("initialized=%s\n"
         "sd_ready=%s\n"
         "header_written=%s\n"
         "interval_ms=%lu\n"
         "last_log_ms=%lu\n"
         "path=%s\n",
         snapshot.initialized ? "true" : "false",
         snapshot.sd_ready ? "true" : "false",
         snapshot.header_written ? "true" : "false",
         (unsigned long)snapshot.interval_ms,
         (unsigned long)snapshot.last_log_ms,
         snapshot.path);
  return 0;
}

void programs::shell::commands::registerAll() {
  Console.addCmd("reboot",         "reboot the device",                    cmd_reboot);
  Console.addCmd("wifi-set",       "save WiFi credentials to NVS",        "<ssid> <password>", cmd_wifi_set);
  Console.addCmd("wifi-connect",   "connect to saved WiFi network",       cmd_wifi_connect);
  Console.addCmd("ps",             "list running tasks",                   cmd_ps);
  Console.addCmd("cpu",            "read or set CPU frequency",            "[80|160|240]", cmd_cpu);
  Console.addCmd("sleep",          "enter deep sleep for N seconds",       "[seconds]", cmd_sleep);
  Console.addCmd("sleep-config",   "show persisted deep sleep config",     cmd_sleep_config);
  Console.addCmd("sleep-enable",   "enable persisted deep sleep config",   cmd_sleep_enable);
  Console.addCmd("sleep-disable",  "disable persisted deep sleep config",  cmd_sleep_disable);
  Console.addCmd("sleep-duration", "set persisted deep sleep duration",    "<seconds>", cmd_sleep_duration);
  Console.addCmd("wakecause",      "show the last wake cause",             cmd_wakecause);
  Console.addCmd("sleep-status",   "show deep sleep status",               cmd_sleep_status);
  Console.addCmd("log-status",     "show CSV logger status",               cmd_log_status);
}
