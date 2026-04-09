#ifndef SSH_SERVER_H
#define SSH_SERVER_H

#include <stdint.h>

//------------------------------------------
//  Configuration
//------------------------------------------
#define SSH_DEFAULT_PORT        22
#ifndef SSH_DEFAULT_USER
#define SSH_DEFAULT_USER        "root"
#endif
#define SSH_DEFAULT_HOSTKEY     "/littlefs/.ssh/id_ed25519"
#define SSH_BUF_SIZE            2048
#define SSH_TASK_STACK_SIZE     32768

//------------------------------------------
//  Public API
//------------------------------------------

// Start the SSH server as a FreeRTOS task.
// Call after WiFi is connected and LittleFS is mounted.
void ssh_server_start(void);

#ifdef PIO_UNIT_TESTING
void ssh_server_run_tests(void);
#endif

#endif // SSH_SERVER_H
