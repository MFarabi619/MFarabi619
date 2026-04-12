#include "commands.h"
#include "../../networking/wifi.h"
extern void network_services_start(void);
#include "../ssh/ssh_server.h"

#include <Arduino.h>
#include <WiFi.h>
#include <Esp.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <microshell.h>

static void cmd_reboot(struct ush_object *self,
                       struct ush_file_descriptor const *file,
                       int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  ush_print(self, (char *)"rebooting...\r\n");
  delay(100);
  ESP.restart();
}

static void cmd_reset(struct ush_object *self,
                      struct ush_file_descriptor const *file,
                      int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  ush_reset(self);
}

static void cmd_wifi_set(struct ush_object *self,
                         struct ush_file_descriptor const *file,
                         int argc, char *argv[]) {
  (void)file;
  if (argc != 3) {
    ush_print(self, (char *)"usage: wifi-set <ssid> <password>\r\n");
    return;
  }
  WiFi.begin(argv[1], argv[2]);
  ush_print(self, (char *)"saved. reboot to connect.\r\n");
}

static void cmd_wifi_connect(struct ush_object *self,
                             struct ush_file_descriptor const *file,
                             int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  ush_print(self, (char *)"connecting...\r\n");
  if (networking::wifi::sta::connect()) {
    ush_print(self, (char *)"connected, starting services...\r\n");
    network_services_start();
  } else {
    ush_print(self, (char *)"failed\r\n");
  }
}

static void cmd_exit(struct ush_object *self,
                     struct ush_file_descriptor const *file,
                     int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  if (services::sshd::requestExit(self)) {
    ush_print(self, (char *)"logout\r\n");
  } else {
    ush_print(self, (char *)"no remote session to exit\r\n");
  }
}

static void cmd_ps(struct ush_object *self,
                   struct ush_file_descriptor const *file,
                   int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;

  uint32_t count = uxTaskGetNumberOfTasks();
  TaskStatus_t *tasks = (TaskStatus_t *)malloc(count * sizeof(TaskStatus_t));
  if (!tasks) {
    ush_print(self, (char *)"out of memory\r\n");
    return;
  }

  uint32_t total_runtime = 0;
  uint32_t filled = uxTaskGetSystemState(tasks, count, &total_runtime);

  static const char *states[] = {"Run", "Rdy", "Blk", "Sus", "Del", "Inv"};

  ush_printf(self, "%-16s %4s %4s %5s %4s\r\n",
             "NAME", "STAT", "PRI", "STACK", "CORE");

  for (uint32_t i = 0; i < filled; i++) {
    int state = (int)tasks[i].eCurrentState;
    if (state > 5) state = 5;
    int core = (int)tasks[i].xCoreID;

    ush_printf(self, "%-16s %4s %4lu %5lu %4s\r\n",
               tasks[i].pcTaskName, states[state],
               (unsigned long)tasks[i].uxCurrentPriority,
               (unsigned long)tasks[i].usStackHighWaterMark,
               core == tskNO_AFFINITY ? "*" : (core == 0 ? "0" : "1"));
  }

  free(tasks);
}

static void cmd_cpu(struct ush_object *self,
                    struct ush_file_descriptor const *file,
                    int argc, char *argv[]) {
  (void)file;

  if (argc == 2) {
    uint32_t mhz = atoi(argv[1]);
    if (mhz != 80 && mhz != 160 && mhz != 240) {
      ush_print(self, (char *)"usage: cpu [80|160|240]\r\n");
      return;
    }
    setCpuFrequencyMhz(mhz);
    ush_printf(self, "CPU set to %lu MHz\r\n", (unsigned long)mhz);
    return;
  }

  ush_printf(self, "%lu MHz\r\n", (unsigned long)ESP.getCpuFreqMHz());
}

static const struct ush_file_descriptor cmd_files[] = {
  { .name = "reboot",       .description = "reboot the device",
    .help = "usage: reboot\r\n",           .exec = cmd_reboot },
  { .name = "reset",        .description = "reset shell",
    .help = "usage: reset\r\n",            .exec = cmd_reset },
  { .name = "exit",         .description = "close current ssh session",
    .help = "usage: exit\r\n",             .exec = cmd_exit },
  { .name = "wifi-set",     .description = "save WiFi credentials to NVS",
    .help = "usage: wifi-set <ssid> <password>\r\n", .exec = cmd_wifi_set },
  { .name = "wifi-connect", .description = "connect to saved WiFi network",
    .help = "usage: wifi-connect\r\n",     .exec = cmd_wifi_connect },
  { .name = "ps",           .description = "list running tasks",
    .help = "usage: ps\r\n",              .exec = cmd_ps },
  { .name = "cpu",          .description = "read or set CPU frequency",
    .help = "usage: cpu [80|160|240]\r\n", .exec = cmd_cpu },
};

static struct ush_node_object cmd;

void programs::shell::commands::registerAll(struct ush_object *ush) {
  ush_commands_add(ush, &cmd, cmd_files,
                   sizeof(cmd_files) / sizeof(cmd_files[0]));
}
