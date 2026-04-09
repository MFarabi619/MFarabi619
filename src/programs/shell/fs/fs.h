#ifndef SHELL_FS_H
#define SHELL_FS_H

#include <microshell.h>

// Mount the full virtual filesystem onto a shell instance.
void fs_mount(struct ush_object *ush);

#endif // SHELL_FS_H
