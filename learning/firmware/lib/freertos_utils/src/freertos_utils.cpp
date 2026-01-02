#include "freertos_utils.h"

void toggleLED(void *parameter) {
  while (1) {
    digitalWrite(LED_BUILTIN, HIGH);
    vTaskDelay(LED_DELAY / portTICK_PERIOD_MS);
    digitalWrite(LED_BUILTIN, LOW);
    vTaskDelay(LED_DELAY / portTICK_PERIOD_MS);
  }
}

void freertosSetup() {
  Serial.begin(MONITOR_SPEED);

  Serial.println("ESP32 booted.");
  pinMode(LED_BUILTIN, OUTPUT);

  xTaskCreatePinnedToCore( // Use xTaskCreate() in vanilla FreeRTOS
      toggleLED,           // function to be called
      "Toggle LED",        // name of task
      1024,                // stack size (bytes in ESP32, words in FreeRTOS)
      NULL,                // parameter to pass to function
      1,                   // task priority (0 to configMAX_PRIORITIES - 1)
      NULL,                // task handle
      app_cpu);            // run on one core for demo purposes (ESP32 only)

  // in vanilla FreeRTOS, call vTaskStartScheduler() in main after setting up
  // tasks
}
