#include "suite.h"
#include <Arduino.h>
#include <unity.h>

void setUp(void) {}
void tearDown(void) {}

void setup(void) {
  delay(500);
  UNITY_BEGIN();
  boot::provisioning::test();

  hardware::system::test();
  hardware::i2c::test();

  sensors::soil::test();
  sensors::voltage::test();
  sensors::current::test();
  sensors::carbon_dioxide::test();
  sensors::solar_radiation::test();
  sensors::rainfall::test();
  sensors::barometric_pressure::test();
  sensors::temperature_and_humidity::test();

  filesystems::sd::test();
  filesystems::api::test();
  filesystems::eeprom::test();
  filesystems::littlefs::test();

  networking::ble::test();
  networking::ota::test();
  networking::sntp::test();
  networking::wifi::test();
  networking::telnet::test();
  networking::tunnel::test();
  networking::update::test();

  services::rtc::test();
  services::http::test();
  services::sshd::test();
  services::email::test();
  services::ws_shell::test();
  services::http_e2e::test();
  services::identity::test();
  services::cloudevents::test();
  services::data_logger::test();
  services::http::api::database::test();

  programs::led::test();
  programs::shell::test();
  programs::buttons::test();
  programs::coreutils::test();
  programs::sqlite::test();
  programs::ssh_client::test();

  power::sleep::test();
  UNITY_END();
}

void loop(void) { delay(50); }
