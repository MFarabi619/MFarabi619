#ifndef SHELL_H
#define SHELL_H

#include <microshell.h>

//------------------------------------------
//  Configuration
//------------------------------------------
#define SHELL_HOSTNAME      "microvisor"
#define SHELL_BUF_IN_SIZE   256
#define SHELL_BUF_OUT_SIZE  256
#define SHELL_PATH_MAX_SIZE 128
#define SHELL_HOSTNAME_SIZE 32

//------------------------------------------
//  Public API
//------------------------------------------

// Initialize MicroShell with Serial I/O and mount the filesystem.
void shell_init(void);

// Call from loop() or a FreeRTOS task — non-blocking.
void shell_service(void);

// Initialize a MicroShell instance with custom I/O + shared filesystem.
// Used by SSH to create its own shell instance over the SSH channel.
void shell_init_instance(struct ush_object *ush,
                         const struct ush_descriptor *desc);

// Hostname accessors (mutable at runtime via /etc/hostname).
char *shell_get_hostname(void);
void shell_set_hostname(const char *hostname);

#ifdef PIO_UNIT_TESTING
void shell_run_tests(void);
#endif

#endif // SHELL_H
