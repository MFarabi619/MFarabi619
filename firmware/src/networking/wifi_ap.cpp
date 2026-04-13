#include "wifi_internal.h"

#include "../services/identity.h"

#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>

namespace {

void configure_ap(const char *ssid, const char *password) {
  Preferences prefs;
  if (!networking::wifi::internal::openPreferences(false, &prefs)) return;
  prefs.putString("ap_ssid", ssid);
  prefs.putString("ap_pass", password);
  prefs.end();
  Serial.printf("[wifi] AP config saved: ssid=%s\n", ssid);
}

}

void networking::wifi::ap::accessConfig(APConfig *config) {
  Preferences prefs;
  bool prefs_ok = networking::wifi::internal::openPreferences(true, &prefs);
  if (!prefs_ok || prefs.getString("ap_ssid", config->ssid, sizeof(config->ssid)) == 0) {
    strncpy(config->ssid, config::wifi::ap::SSID, sizeof(config->ssid) - 1);
    config->ssid[sizeof(config->ssid) - 1] = '\0';
  }
  if (!prefs_ok || prefs.getString("ap_pass", config->password, sizeof(config->password)) == 0) {
    strncpy(config->password, config::wifi::ap::PASSWORD, sizeof(config->password) - 1);
    config->password[sizeof(config->password) - 1] = '\0';
  }
  if (prefs_ok) prefs.end();
}

bool networking::wifi::ap::accessSnapshot(APSnapshot *snapshot) {
  if (!snapshot) return false;
  memset(snapshot, 0, sizeof(*snapshot));
  snapshot->active = networking::wifi::internal::ap_active;
  APConfig config = {};
  networking::wifi::ap::accessConfig(&config);
  strncpy(snapshot->ssid, config.ssid, sizeof(snapshot->ssid) - 1);
  strncpy(snapshot->password, config.password, sizeof(snapshot->password) - 1);
  strncpy(snapshot->ip, WiFi.softAPIP().toString().c_str(), sizeof(snapshot->ip) - 1);
  snapshot->clients = WiFi.softAPgetStationNum();
  strncpy(snapshot->hostname, services::identity::accessHostname(), sizeof(snapshot->hostname) - 1);
  strncpy(snapshot->mac, WiFi.softAPmacAddress().c_str(), sizeof(snapshot->mac) - 1);
  return true;
}

bool networking::wifi::ap::applyConfig(APConfigureCommand *command) {
  if (!command) return false;
  configure_ap(command->config.ssid, command->config.password);
  if (networking::wifi::ap::isActive()) {
    networking::wifi::ap::disable();
    networking::wifi::ap::enable();
  }
  networking::wifi::ap::accessSnapshot(&command->snapshot);
  return true;
}

void networking::wifi::ap::enable() {
  {
    Preferences prefs;
    if (networking::wifi::internal::openPreferences(false, &prefs)) {
      prefs.putBool("ap_on", true);
      prefs.end();
    }
  }

  if (networking::wifi::internal::ap_active) return;

  APConfig cfg = {};
  networking::wifi::ap::accessConfig(&cfg);

  WiFi.mode(WIFI_AP_STA);

  IPAddress ap_ip(192, 168, 4, 1);
  IPAddress gateway(192, 168, 4, 1);
  IPAddress subnet(255, 255, 255, 0);
  WiFi.softAPConfig(ap_ip, gateway, subnet);
  WiFi.softAP(cfg.ssid, cfg.password, config::wifi::ap::CHANNEL);

#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 4, 2)
  WiFi.AP.enableDhcpCaptivePortal();
#endif

  networking::wifi::internal::ap_active = true;
  Serial.printf("[wifi] AP started: %s (%s)\n",
                cfg.ssid, ap_ip.toString().c_str());
}

bool networking::wifi::ap::setEnabled(APEnabledCommand *command) {
  if (!command) return false;
  if (command->enabled) networking::wifi::ap::enable();
  else networking::wifi::ap::disable();
  networking::wifi::ap::accessSnapshot(&command->snapshot);
  return true;
}

void networking::wifi::ap::disable() {
  {
    Preferences prefs;
    if (networking::wifi::internal::openPreferences(false, &prefs)) {
      prefs.putBool("ap_on", false);
      prefs.end();
    }
  }

  if (!networking::wifi::internal::ap_active) return;

  WiFi.softAPdisconnect(true);

  if (WiFi.isConnected()) {
    WiFi.mode(WIFI_MODE_STA);
  }

  networking::wifi::internal::ap_active = false;
  Serial.println(F("[wifi] AP stopped"));
}

bool networking::wifi::ap::isActive() {
  return networking::wifi::internal::ap_active;
}
