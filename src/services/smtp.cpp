#include "smtp.h"

#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <time.h>

#define ENABLE_SMTP
#include <ReadyMail.h>

static WiFiClient smtp_plain_client;
static WiFiClientSecure smtp_secure_client;
static SMTPClient smtp_plain_session;
static SMTPClient smtp_secure_session;
static SMTPClient *active_session = nullptr;
static bool plain_initialized = false;
static bool secure_initialized = false;
static bool connected = false;

static bool load_password(String &out) {
  Preferences prefs;
  prefs.begin("smtp", true);
  out = prefs.isKey(CONFIG_SMTP_NVS_KEY)
      ? prefs.getString(CONFIG_SMTP_NVS_KEY, "")
      : "";
  prefs.end();
  return true;
}

static bool config_is_valid(const String &password) {
  if (strlen(CONFIG_SMTP_HOST) == 0 || strlen(CONFIG_SMTP_DOMAIN) == 0)
    return false;
  if (CONFIG_SMTP_AUTH_ENABLED == 1
      && (strlen(CONFIG_SMTP_LOGIN_EMAIL) == 0 || password.length() == 0))
    return false;
  return true;
}

static void status_callback(SMTPStatus status) {
  if (status.progress.available) {
    Serial.printf("[SMTP] uploading %s %u%%\n",
                  status.progress.filename.c_str(),
                  (unsigned)status.progress.value);
    return;
  }
  if (status.text.length() > 0)
    Serial.printf("[SMTP] %s\n", status.text.c_str());
}

static SMTPClient *select_session(void) {
  if (CONFIG_SMTP_SSL_ENABLED == 1 || CONFIG_SMTP_STARTTLS_ENABLED == 1) {
    smtp_secure_client.setInsecure();
    if (!secure_initialized) {
      smtp_secure_session.begin(smtp_secure_client);
      secure_initialized = true;
    }
    return &smtp_secure_session;
  }
  if (!plain_initialized) {
    smtp_plain_session.begin(smtp_plain_client);
    plain_initialized = true;
  }
  return &smtp_plain_session;
}

static String format_sender(void) {
  if (strlen(CONFIG_SMTP_FROM_NAME) == 0)
    return String(CONFIG_SMTP_FROM_EMAIL);
  return String(CONFIG_SMTP_FROM_NAME) + " <" + CONFIG_SMTP_FROM_EMAIL + ">";
}

static uint32_t message_timestamp(void) {
  const time_t now = time(nullptr);
  return now < 0 ? 0 : static_cast<uint32_t>(now);
}

static bool do_connect(const String &password) {
  if (CONFIG_SMTP_STARTTLS_ENABLED == 1) {
    Serial.println("[SMTP] STARTTLS configured but not supported in this build");
    return false;
  }

  active_session = select_session();
  if (!active_session) return false;

  if (!active_session->connect(CONFIG_SMTP_HOST, CONFIG_SMTP_PORT,
                                CONFIG_SMTP_DOMAIN, status_callback,
                                CONFIG_SMTP_SSL_ENABLED == 1)
      || !active_session->isConnected()) {
    SMTPStatus s = active_session->status();
    Serial.printf("[SMTP] connect failed: %d/%d %s\n",
                  s.statusCode, s.errorCode, s.text.c_str());
    return false;
  }

  if (CONFIG_SMTP_AUTH_ENABLED == 1) {
    if (!active_session->authenticate(CONFIG_SMTP_LOGIN_EMAIL, password,
                                       readymail_auth_password)
        || !active_session->isAuthenticated()) {
      SMTPStatus s = active_session->status();
      Serial.printf("[SMTP] auth failed: %d/%d %s\n",
                    s.statusCode, s.errorCode, s.text.c_str());
      return false;
    }
    Serial.println("[SMTP] connected and authenticated");
  } else {
    Serial.println("[SMTP] connected (no auth)");
  }
  return true;
}

bool smtp_get_endpoint(char *host, size_t host_len, uint16_t *port) {
  if (!host || host_len == 0 || !port) return false;

  String password;
  load_password(password);
  if (!config_is_valid(password)) return false;

  strncpy(host, CONFIG_SMTP_HOST, host_len - 1);
  host[host_len - 1] = '\0';
  *port = CONFIG_SMTP_PORT;
  return host[0] != '\0';
}

bool smtp_connect(void) {
  String password;
  load_password(password);
  if (!config_is_valid(password)) {
    Serial.println("[SMTP] invalid config");
    return false;
  }

  if (connected && active_session && active_session->isConnected())
    return true;

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[SMTP] WiFi not connected");
    return false;
  }

  if (active_session && active_session->isConnected())
    active_session->stop();

  if (!do_connect(password))
    return false;

  connected = true;
  return true;
}

bool smtp_send_test_email(void) {
  if (strlen(CONFIG_SMTP_HOST) == 0 || strlen(CONFIG_SMTP_DOMAIN) == 0) {
    Serial.println("[SMTP] invalid config for test email");
    return false;
  }
  if (strlen(CONFIG_SMTP_FROM_EMAIL) == 0 || strlen(CONFIG_SMTP_TO_EMAIL) == 0) {
    Serial.println("[SMTP] missing from/to email");
    return false;
  }
  if (!smtp_connect()) return false;

  SMTPMessage message;
  message.headers.add(rfc822_from, format_sender());
  message.headers.add(rfc822_to, CONFIG_SMTP_TO_EMAIL);
  message.headers.add(rfc822_subject,
                      String(CONFIG_SMTP_SUBJECT_PREFIX) + " SMTP test");
  message.headers.addCustom("Importance", "High");
  message.headers.addCustom("X-Priority", "1");

  message.text.body(
      String("SMTP test from ceratina firmware.\r\n")
      + "Host: " + CONFIG_SMTP_HOST + ":" + String(CONFIG_SMTP_PORT));

  message.html.body(
      String("<html><body>")
      + "<p>SMTP test from ceratina firmware.</p>"
      + "<p>Host: " + CONFIG_SMTP_HOST + ":" + String(CONFIG_SMTP_PORT) + "</p>"
      + "<p>Chip: " + ESP.getChipModel() + " rev" + String(ESP.getChipRevision())
      + " &bull; Heap: " + String(ESP.getFreeHeap() / 1024) + " KB free</p>"
      + "</body></html>");

  message.timestamp = message_timestamp();

  if (!active_session->send(message)) {
    SMTPStatus s = active_session->status();
    Serial.printf("[SMTP] send failed: %d/%d %s\n",
                  s.statusCode, s.errorCode, s.text.c_str());
    return false;
  }

  Serial.println("[SMTP] test email sent");
  return true;
}
