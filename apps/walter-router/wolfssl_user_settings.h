/*
 * Apidae Systems — wolfSSL settings for Walter (ESP32-S3 / Zephyr).
 * Adapted from modules/lib/wolfssh/zephyr/samples/tests/wolfssl_user_settings.h.
 * Bypasses the default zephyr/user_settings.h PSA path (which has header-ordering
 * issues when MBEDTLS_PSA_CRYPTO_C is already enabled via wpa_supplicant).
 */

#ifndef WOLFSSL_USER_SETTINGS_H
#define WOLFSSL_USER_SETTINGS_H

#ifdef __cplusplus
extern "C" {
#endif

#define WOLFSSL_ZEPHYR
#define WOLFSSL_WOLFSSH
#define WOLFSSL_NO_ASM
#define WC_NO_ASYNC_THREADING

#define TFM_TIMING_RESISTANT
#define ECC_TIMING_RESISTANT
#define WC_RSA_BLINDING

#define HAVE_HASHDRBG

#define HAVE_AESGCM
#define HAVE_CHACHA
#define HAVE_POLY1305
#define HAVE_ONE_TIME_AUTH

#define WOLFSSL_SHA224
#define WOLFSSL_SHA384
#define WOLFSSL_SHA512
#define WOLFSSL_SHA3

#define HAVE_ECC
#define TFM_ECC256
#define WOLFSSL_BASE64_ENCODE

#define HAVE_HKDF
#define HAVE_TLS_EXTENSIONS
#define HAVE_SUPPORTED_CURVES
#define HAVE_EXTENDED_MASTER
#define WOLFSSL_TLS13
#define WC_RSA_PSS
#define HAVE_FFDHE_2048

#define USE_FAST_MATH

#define NO_DSA
#define NO_DES3
#define NO_RC4
#define NO_MD4
#define NO_PSK
#define NO_PWDBASED

#ifdef __cplusplus
}
#endif

#endif /* WOLFSSL_USER_SETTINGS_H */
