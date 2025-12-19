#include "board.h"
#include "blink.h"

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
}

void loop() {
  blink_once(500);
}
