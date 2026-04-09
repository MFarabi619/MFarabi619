#include "../../../config.h"
#include "../../../helpers.h"

#include <Arduino.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  /bin/uptime
//------------------------------------------
static void uptime_exec(struct ush_object *self,
                        struct ush_file_descriptor const *file,
                        int argc, char *argv[]) {
  (void)file; (void)argv;
  if (argc != 1) {
    ush_print_status(self, USH_STATUS_ERROR_COMMAND_WRONG_ARGUMENTS);
    return;
  }
  char buf[32];
  format_uptime(buf, sizeof(buf));
  ush_print(self, buf);
}

//------------------------------------------
//  /bin/print
//------------------------------------------
static void print_exec(struct ush_object *self,
                       struct ush_file_descriptor const *file,
                       int argc, char *argv[]) {
  (void)file;
  if (argc != 2) {
    ush_print_status(self, USH_STATUS_ERROR_COMMAND_WRONG_ARGUMENTS);
    return;
  }
  ush_print(self, argv[1]);
}

//------------------------------------------
//  /bin/whoami
//------------------------------------------
static void whoami_exec(struct ush_object *self,
                        struct ush_file_descriptor const *file,
                        int argc, char *argv[]) {
  (void)file; (void)argv;
  if (argc != 1) {
    ush_print_status(self, USH_STATUS_ERROR_COMMAND_WRONG_ARGUMENTS);
    return;
  }
  char buf[64];
  snprintf(buf, sizeof(buf), "%s\r\n", CONFIG_SSH_USER);
  ush_print(self, buf);
}

//------------------------------------------
//  /bin/free
//------------------------------------------
static void free_exec(struct ush_object *self,
                      struct ush_file_descriptor const *file,
                      int argc, char *argv[]) {
  (void)file; (void)argv;
  if (argc != 1) {
    ush_print_status(self, USH_STATUS_ERROR_COMMAND_WRONG_ARGUMENTS);
    return;
  }
  char buf[128];
  format_heap(buf, sizeof(buf));
  ush_print(self, buf);
}

static const struct ush_file_descriptor bin_files[] = {
  { .name = "uptime",  .description = "show system uptime",
    .help = "usage: uptime\r\n", .exec = uptime_exec },
  { .name = "print",   .description = "print argument to shell",
    .help = "usage: print <text>\r\n", .exec = print_exec },
  { .name = "whoami",  .description = "print current user",
    .help = "usage: whoami\r\n", .exec = whoami_exec },
  { .name = "free",    .description = "show memory usage",
    .help = "usage: free\r\n", .exec = free_exec },
};

static struct ush_node_object bin;

void bin_mount(struct ush_object *ush) {
  ush_node_mount(ush, "/bin", &bin, bin_files,
                 sizeof(bin_files) / sizeof(bin_files[0]));
}
