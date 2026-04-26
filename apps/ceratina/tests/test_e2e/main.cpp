#include "suite.h"
#include <testing/utils.h>

#include <Arduino.h>
#include <LittleFS.h>
#include <SD.h>
#include <storage.h>
#include <unity.h>

namespace {

WifiNvsSnapshot wifi_snapshot = {};
ProvisioningNvsSnapshot provisioning_snapshot = {};
TunnelNvsSnapshot tunnel_snapshot = {};
SleepNvsSnapshot sleep_snapshot = {};

const char *test_sd_files[] = {
  "/sd/test_sqlite.db",
  "/sd/test_sqlite_idem.db",
  "/sd/test_sqlite_cis.db",
  "/sd/test_sqlite_err.db",
  "/sd/test_sqlite_persist.db",
  "/sd/test_sqlite_errclr.db",
  "/sd/test_sqlite_path.db",
  "/sd/test_sqlite_txcommit.db",
  "/sd/test_sqlite_txrollback.db",
  "/sd/test_sqlite_null.db",
  "/sd/test_sqlite_empty.db",
  "/sd/test_sqlite_long.db",
  "/sd/test_sqlite_fk.db",
  "/sd/test_sqlite_idx.db",
  "/sd/test_sqlite_mem.db",
  "/sd/test_sqlite_lgblob.db",
  "/sd/test_sqlite_mixed.db",
  "/sd/test_sqlite_conc.db",
  "/sd/test_db_api.db",
  "/sd/.test_roundtrip.tmp",
  "/sd/.test_append.tmp",
  "/sd/.test_nested/sub/file.txt",
  "/sd/.test_dir/a.txt",
  "/sd/.test_dir/b.txt",
};

const char *test_sd_directories[] = {
  "/sd/.test_nested/sub",
  "/sd/.test_nested",
  "/sd/.test_dir",
};

void cleanup_test_filesystem_artifacts() {
  if (hardware::storage::ensureSD()) {
    for (const char *path : test_sd_files) {
      SD.remove(path);
    }
    for (const char *path : test_sd_directories) {
      SD.rmdir(path);
    }
  }

  if (hardware::storage::ensureLittleFS()) {
    LittleFS.remove("/.test_roundtrip.tmp");
    LittleFS.remove("/.test_append.tmp");
    LittleFS.remove("/.test_lfs.tmp");
    LittleFS.remove("/.test_nest/deep/file.txt");
    LittleFS.rmdir("/.test_nest/deep");
    LittleFS.rmdir("/.test_nest");
    LittleFS.remove("/.test_rmdir/child.txt");
    LittleFS.rmdir("/.test_rmdir");
    LittleFS.rmdir("/.test_rm_dir");
    LittleFS.remove("/.test_rename_src.tmp");
    LittleFS.remove("/.test_rename_dst.tmp");
  }
}

} // namespace

void setUp(void) {
  wifi_nvs_save(&wifi_snapshot);
  provisioning_nvs_save(&provisioning_snapshot);
  tunnel_nvs_save(&tunnel_snapshot);
  sleep_nvs_save(&sleep_snapshot);
}

void tearDown(void) {
  wifi_nvs_restore(&wifi_snapshot);
  provisioning_nvs_restore(&provisioning_snapshot);
  tunnel_nvs_restore(&tunnel_snapshot);
  sleep_nvs_restore(&sleep_snapshot);
  cleanup_test_filesystem_artifacts();
}

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
