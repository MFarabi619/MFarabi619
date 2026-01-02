#ifndef ASYNC_WEB_SERVER_H
#define ASYNC_WEB_SERVER_H

#include "serial_logger_utils.h"
#include "spiffs_utils.h"
#include "wifi_utils.h"

#include <ESPAsyncWebServer.h>

#define LED_RED 39
#define LED_YELLOW 38
#define LED_GREEN 37

#define LED_TOGGLE 38
// #define LED_TOGGLE LED_BUILTIN

#define REQUEST_INDICATOR_LED_PIN 37
/* #define REQUEST_INDICATOR_LED_PIN LED_BUILTIN */

/* #ifdef LED_BUILTIN */
/* #define REQUEST_INDICATOR_LED_PIN LED_BUILTIN */
/* #else */
/* #define REQUEST_INDICATOR_LED_PIN LED_YELLOW */
/* #endif */

static int led_toggle_state = 0;

void initialize_led_pins();
String formatUptime(unsigned long ms);
void begin_async_web_server();

#endif
