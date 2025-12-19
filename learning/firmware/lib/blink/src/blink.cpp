#include "blink.h"

void blink_once(unsigned int delay_ms){
  Serial.println("LED ON");
  digitalWrite(LED_BUILTIN, HIGH);
  delay(delay_ms);
  Serial.println("LED OFF");
  digitalWrite(LED_BUILTIN, LOW);
  delay(delay_ms);
}
