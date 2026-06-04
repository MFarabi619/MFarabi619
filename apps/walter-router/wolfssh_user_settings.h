/*
 * Apidae Systems — wolfSSH settings for Walter.
 * Adapted from modules/lib/wolfssh/zephyr/samples/tests/wolfssh_user_settings.h
 * with test-only buffer overrides removed.
 */

#ifndef WOLFSSH_USER_SETTINGS_H
#define WOLFSSH_USER_SETTINGS_H

#ifdef __cplusplus
extern "C" {
#endif

#include <wolfssl/wolfcrypt/types.h>

#define WOLFSSH_SFTP

#define NO_MAIN_DRIVER
#define WS_NO_SIGNAL
#define NO_WOLFSSL_DIR
#define WOLFSSH_NO_NONBLOCKING

#define DEFAULT_WINDOW_SZ (128 * 128)
#define WOLFSSH_MAX_SFTP_RW 8192

#ifdef __cplusplus
}
#endif

#endif /* WOLFSSH_USER_SETTINGS_H */
