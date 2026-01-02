#include "async_web_server.h"
#include "freertos_utils.h"
#include "serial_logger_utils.h"

#include <ESP32Servo.h>

Servo servo;
const int SERVO_PIN = 5;

enum class ServoMode { Idle, Set, Sweep };

ServoMode servoMode = ServoMode::Idle;
int currentAngle = 90;
int targetAngle = 90;
bool sweepDirUp = true;
unsigned long lastServoStepMs = 0;

const int PIN_TO_SENSOR = 2;
int pinStateCurrent = LOW;
int pinStatePrevious = LOW;

extern AsyncWebServer server;

bool switchOn = false;

// const int gpio_pins[] = {
//   1, 2, 3, 4, 5, 6, 43,
//   44, 7, 8, 9
// };

// const int pin_count = sizeof(gpio_pins) / sizeof(gpio_pins[0]);

void setup() {
  begin_serial_logger();
  begin_async_web_server();

  pinMode(PIN_TO_SENSOR, INPUT);

  Serial.print("[Servo] Attaching to pin ");
  Serial.println(SERVO_PIN);
  int ch = servo.attach(SERVO_PIN);
  Serial.print("[Servo] attach() returned channel: ");
  Serial.println(ch);
  currentAngle = 90;
  targetAngle = 90;
  servo.write(currentAngle);
  Serial.print("[Servo] Initial angle set to ");
  Serial.println(currentAngle);

  // server.onNotFound([](AsyncWebServerRequest *req) {
  //   digitalWrite(REQUEST_INDICATOR_LED_PIN, HIGH);

  //   const String url = req->url();
  //   if (url.length() > 1) {
  //     bool numeric = true;
  //     for (size_t i = 1; i < url.length(); i++) {
  //       if (!isDigit(url[i])) {
  //         numeric = false;
  //         break;
  //       }
  //     }

  //     if (numeric) {
  //       int angle = constrain(url.substring(1).toInt(), 0, 180);
  //       targetAngle = angle;
  //       servoMode = ServoMode::Set;
  //       Serial.printf("[HTTP] %s -> targetAngle=%d\n", url.c_str(), angle);

  //       req->send(200, "text/plain; charset=utf-8",
  //                 String("Servo -> ") + angle);

  //       digitalWrite(REQUEST_INDICATOR_LED_PIN, LOW);
  //       return;
  //     }
  //   }

  //   req->send(404, "text/plain; charset=utf-8", "404: Not found");
  //   digitalWrite(REQUEST_INDICATOR_LED_PIN, LOW);
  // });

  server.on("/sweep", HTTP_GET, [](AsyncWebServerRequest *req) {
    Serial.println("[HTTP] GET /on");
    digitalWrite(LED_BUILTIN, HIGH);
    servoMode = ServoMode::Sweep;
    Serial.println("[Servo] Sweep mode enabled");
    req->send(200, "text/plain", "Servo SWEEP");
  });

  server.on("/left", HTTP_GET, [](AsyncWebServerRequest *req) {
    Serial.println("[HTTP] GET /left");
    targetAngle = 15;
    servoMode = ServoMode::Set;
    Serial.print("[Servo] targetAngle set to ");
    Serial.println(targetAngle);
    req->send(200, "text/plain", "Servo LEFT");
  });

  server.on("/right", HTTP_GET, [](AsyncWebServerRequest *req) {
    Serial.println("[HTTP] GET /right");
    targetAngle = 165;
    servoMode = ServoMode::Set;
    Serial.print("[Servo] targetAngle set to ");
    Serial.println(targetAngle);
    req->send(200, "text/plain", "Servo RIGHT");
  });

  server.on("/center", HTTP_GET, [](AsyncWebServerRequest *req) {
    Serial.println("[HTTP] GET /center");
    targetAngle = 90;
    servoMode = ServoMode::Set;
    Serial.print("[Servo] targetAngle set to ");
    Serial.println(targetAngle);
    req->send(200, "text/plain", "Servo CENTER");
  });

  //   for (int i = 0; i < pin_count; i++) {
  //   pinMode(gpio_pins[i], OUTPUT);
  //   digitalWrite(gpio_pins[i], LOW);
  // }
}

void loop() {
  //  for (int i = 0; i < pin_count; i++) {
  //   digitalWrite(gpio_pins[i], HIGH);
  //   delay(300);
  //   digitalWrite(gpio_pins[i], LOW);
  //   delay(200);
  // }

  unsigned long now = millis();

  switch (servoMode) {
  case ServoMode::Set:
    Serial.print("[Servo] Applying Set mode, angle = ");
    Serial.println(targetAngle);
    servo.write(targetAngle);
    currentAngle = targetAngle;
    servoMode = ServoMode::Idle;
    break;

  case ServoMode::Sweep:
    if (now - lastServoStepMs >= 1) {
      lastServoStepMs = now;

      if (sweepDirUp) {
        currentAngle++;
        if (currentAngle >= 180) {
          currentAngle = 180;
          sweepDirUp = false;
          Serial.println("[Servo] Sweep reached max, reversing");
        }
      } else {
        currentAngle--;
        if (currentAngle <= 0) {
          currentAngle = 0;
          sweepDirUp = true;
          Serial.println("[Servo] Sweep reached min, reversing");
        }
      }

      servo.write(currentAngle);
      Serial.print("[Servo] Sweep angle = ");
      Serial.println(currentAngle);
    }
    break;

  case ServoMode::Idle:
  default:
    break;
  }

  pinStatePrevious = pinStateCurrent;
  pinStateCurrent = digitalRead(PIN_TO_SENSOR);

  if (pinStatePrevious == LOW && pinStateCurrent == HIGH) {
    switchOn = !switchOn;

    Serial.println("Motion detected → toggle");

    targetAngle = switchOn ? 40 : 150;
    servoMode = ServoMode::Set;
    delay(2000);
  }
}
