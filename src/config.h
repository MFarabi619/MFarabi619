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
#endif // CONFIG_H
