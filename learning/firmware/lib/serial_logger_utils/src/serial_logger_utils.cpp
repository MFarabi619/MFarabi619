#include "serial_logger_utils.h"

void begin_serial_logger() {
  Serial.begin(MONITOR_SPEED);
  delay(200);

  Serial.println(CLR_BLUE_B "\n=== BOOT SEQUENCE ===" CLR_RESET);
  Serial.println(CLR_YELLOW "[Logger] Initializing..." CLR_RESET);

  Serial.println(CLR_BLUE_B "\n=== HARDWARE BRING-UP SUMMARY ===" CLR_RESET);
  Serial.println(CLR_GREEN "[Logger] OK" CLR_RESET);
}
