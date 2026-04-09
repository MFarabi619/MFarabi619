#include "commands.h"

#include <Arduino.h>
#include <microshell.h>

static void cmd_reboot(struct ush_object *self,
                       struct ush_file_descriptor const *file,
                       int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  ush_print(self, "rebooting...\r\n");
  delay(100);
  ESP.restart();
}

static void cmd_reset(struct ush_object *self,
                      struct ush_file_descriptor const *file,
                      int argc, char *argv[]) {
  (void)file; (void)argc; (void)argv;
  ush_reset(self);
}

static const struct ush_file_descriptor cmd_files[] = {
  {
    .name = "reboot",
    .description = "reboot the device",
    .help = "usage: reboot\r\n",
    .exec = cmd_reboot,
  },
  {
    .name = "reset",
    .description = "reset shell",
    .help = "usage: reset\r\n",
    .exec = cmd_reset,
  },
};

static struct ush_node_object cmd;

void commands_register(struct ush_object *ush) {
  ush_commands_add(ush, &cmd, cmd_files,
                   sizeof(cmd_files) / sizeof(cmd_files[0]));
}
