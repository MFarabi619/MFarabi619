#include <microshell.h>
#include <string.h>

static size_t motd_get_data(struct ush_object *self,
                            struct ush_file_descriptor const *file,
                            uint8_t **data) {
  (void)self; (void)file;
  static const char *motd = "Welcome to Microvisor.\r\n";
  *data = (uint8_t *)motd;
  return strlen(motd);
}

static const struct ush_file_descriptor root_files[] = {
  {
    .name = "motd",
    .description = "message of the day",
    .help = NULL,
    .exec = NULL,
    .get_data = motd_get_data,
  },
};

static struct ush_node_object root;

void root_mount(struct ush_object *ush) {
  ush_node_mount(ush, "/", &root, root_files,
                 sizeof(root_files) / sizeof(root_files[0]));
}
