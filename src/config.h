#ifndef CONFIG_H
#define CONFIG_H

// ─────────────────────────────────────────────────────────────────────────────
//  Deployment
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_HOSTNAME
#define CONFIG_HOSTNAME             "microvisor"
#endif

#ifndef CONFIG_PLATFORM
#define CONFIG_PLATFORM             "esp32s3"
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  System
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SYSTEM_TASK_STACK
#define CONFIG_SYSTEM_TASK_STACK    8192
#endif

#ifndef CONFIG_SERIAL_BAUD
#define CONFIG_SERIAL_BAUD          115200
#endif

#ifndef CONFIG_SHELL_SERVICE_INTERVAL_MS
#define CONFIG_SHELL_SERVICE_INTERVAL_MS 10
#endif

// ─────────────────────────────────────────────────────────────────────────────
//  SSH
// ─────────────────────────────────────────────────────────────────────────────

#ifndef CONFIG_SSH_PORT
#define CONFIG_SSH_PORT             22
#endif

#ifndef CONFIG_SSH_USER
#define CONFIG_SSH_USER             "root"
#endif

#ifndef CONFIG_SSH_HOSTKEY_PATH
#define CONFIG_SSH_HOSTKEY_PATH     "/littlefs/.ssh/id_ed25519"
#endif

#ifndef CONFIG_SSH_BUF_SIZE
#define CONFIG_SSH_BUF_SIZE         2048
#endif

#ifndef CONFIG_SSH_TASK_STACK
#define CONFIG_SSH_TASK_STACK       32768
#endif

#ifndef CONFIG_SSH_WRITE_BUF_SIZE
#define CONFIG_SSH_WRITE_BUF_SIZE   1024
#endif

#ifndef CONFIG_SSH_RING_SIZE
#define CONFIG_SSH_RING_SIZE        512
#endif
#endif // CONFIG_H
