#include "../../ssh/ssh_server.h"

#include <Arduino.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  /bin/uptime — formatted uptime (exec command)
//------------------------------------------
static void uptime_exec(struct ush_object *self,
                        struct ush_file_descriptor const *file,
                        int argc, char *argv[]) {
  (void)file; (void)argv;
  if (argc != 1) {
    ush_print_status(self, USH_STATUS_ERROR_COMMAND_WRONG_ARGUMENTS);
    return;
  }
  unsigned long secs = millis() / 1000;
  char buf[32];
  snprintf(buf, sizeof(buf), "%luh %lum %lus\r\n",
           secs / 3600, (secs / 60) % 60, secs % 60);
  ush_print(self, buf);
}

//------------------------------------------
//  /bin/print — print argument to shell
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
//  /bin/whoami — print current user
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
  snprintf(buf, sizeof(buf), "%s\r\n", SSH_DEFAULT_USER);
  ush_print(self, buf);
}

//------------------------------------------
//  /bin/free — formatted memory (exec command)
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
  snprintf(buf, sizeof(buf),
           "heap total: %u\r\nheap free:  %u\r\nheap used:  %u\r\n",
           ESP.getHeapSize(), ESP.getFreeHeap(),
           ESP.getHeapSize() - ESP.getFreeHeap());
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
