#include <Arduino.h>

#include <WiFi.h>
#include <ESPmDNS.h>
#include <SPIFFS.h>
#include <ESPAsyncWebServer.h>

#include "esp_system.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define CLR_RED   "\033[31m"
#define CLR_GREEN "\033[32m"
#define CLR_BLUE_B    "\033[94m"
#define CLR_YELLOW "\033[33m"
#define CLR_MAGENTA_B "\033[95m"
#define CLR_RESET "\033[0m"

#ifdef LED_BUILTIN
  #define REQUEST_INDICATOR_LED_PIN LED_BUILTIN
#else
  #define REQUEST_INDICATOR_LED_PIN 38
#endif
