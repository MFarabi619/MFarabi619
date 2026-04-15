#include "suite.h"
#include <Arduino.h>
#include <unity.h>

void setUp(void) {}
void tearDown(void) {}

void setup(void) {
  delay(500);
  UNITY_BEGIN();

  boot::provisioning::test();

  hardware::i2c::test();
  hardware::system::test();

  filesystems::api::test();
  filesystems::eeprom::test();
  filesystems::littlefs::test();
  filesystems::sd::test();

  networking::ble::test();
  networking::ota::test();
  networking::sntp::test();
  networking::telnet::test();
  networking::update::test();
  networking::wifi::test();

  services::cloudevents::test();
  services::data_logger::test();
  services::email::test();
  services::http::api::database::test();
  services::http::test();
  services::http_e2e::test();
  services::identity::test();
  services::rtc::test();
  services::sshd::test();
  services::ws_shell::test();

  sensors::barometric_pressure::test();
  sensors::carbon_dioxide::test();
  sensors::current::test();
  sensors::soil::test();
  sensors::solar_radiation::test();
  sensors::temperature_and_humidity::test();
  sensors::voltage::test();

  programs::buttons::test();
  programs::coreutils::test();
  programs::led::test();
  programs::shell::test();
  programs::ssh_client::test();

  power::sleep::test();

  UNITY_END();
}

void loop(void) { delay(50); }
