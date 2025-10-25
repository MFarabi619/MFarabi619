#include "Arduino.h"

#define LED_R 39
#define LED_Y 38
#define LED_G 37

void setup() {
  pinMode(LED_R, OUTPUT);
  pinMode(LED_Y, OUTPUT);
  pinMode(LED_G, OUTPUT);
}

void loop() {
  digitalWrite(LED_R, HIGH);
  digitalWrite(LED_Y, LOW);
  digitalWrite(LED_G, LOW);
  delay(1000);

  digitalWrite(LED_R, LOW);
  digitalWrite(LED_Y, HIGH);
  digitalWrite(LED_G, LOW);
  delay(1000);

  digitalWrite(LED_R, LOW);
  digitalWrite(LED_Y, LOW);
  digitalWrite(LED_G, HIGH);
  delay(1000);
}
