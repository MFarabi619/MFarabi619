#include <spiffs_utils.h>

void setup_spiffs() {
  if (SPIFFS.begin(true)) {
    Serial.println(CLR_GREEN "[SPIFFS] Mounted" CLR_RESET);
  } else {
    Serial.println(CLR_RED "[SPIFFS] ERROR: mount failed" CLR_RESET);
  }
}
