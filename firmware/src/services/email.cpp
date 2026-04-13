#include "email.h"

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
  if (!prefs.begin("smtp", true)) return false;
  out = prefs.isKey(config::smtp::NVS_KEY)
      ? prefs.getString(config::smtp::NVS_KEY, "")
      : "";
  prefs.end();
  return true;
}

static bool config_is_valid(const String &password) {
  if (strlen(config::smtp::HOST) == 0 || strlen(config::smtp::DOMAIN) == 0)
    return false;
  if (config::smtp::AUTH_ENABLED == 1
      && (strlen(config::smtp::LOGIN_EMAIL) == 0 || password.length() == 0))
    return false;
  return true;
}

static void status_callback(SMTPStatus status) {
  if (status.progress.available) {
    Serial.printf("[email] uploading %s %u%%\n",
                  status.progress.filename.c_str(),
                  (unsigned)status.progress.value);
    return;
  }
  if (status.text.length() > 0)
    Serial.printf("[email] %s\n", status.text.c_str());
}

static SMTPClient *select_session(void) {
  if (config::smtp::SSL_ENABLED == 1 || config::smtp::STARTTLS_ENABLED == 1) {
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
  if (strlen(config::smtp::FROM_NAME) == 0)
    return String(config::smtp::FROM_EMAIL);
  return String(config::smtp::FROM_NAME) + " <" + config::smtp::FROM_EMAIL + ">";
}

static uint32_t message_timestamp(void) {
  const time_t now = time(nullptr);
  return now < 0 ? 0 : static_cast<uint32_t>(now);
}

static bool do_connect(const String &password) {
  if (config::smtp::STARTTLS_ENABLED == 1) {
    Serial.println("[email] STARTTLS configured but not supported in this build");
    return false;
  }

  active_session = select_session();
  if (!active_session) return false;

  if (!active_session->connect(config::smtp::HOST, config::smtp::PORT,
                                config::smtp::DOMAIN, status_callback,
                                config::smtp::SSL_ENABLED == 1)
      || !active_session->isConnected()) {
    SMTPStatus s = active_session->status();
    Serial.printf("[email] connect failed: %d/%d %s\n",
                  s.statusCode, s.errorCode, s.text.c_str());
    return false;
  }

  if (config::smtp::AUTH_ENABLED == 1) {
    if (!active_session->authenticate(config::smtp::LOGIN_EMAIL, password,
                                       readymail_auth_password)
        || !active_session->isAuthenticated()) {
      SMTPStatus s = active_session->status();
      Serial.printf("[email] auth failed: %d/%d %s\n",
                    s.statusCode, s.errorCode, s.text.c_str());
      return false;
    }
    Serial.println("[email] connected and authenticated");
  } else {
    Serial.println("[email] connected (no auth)");
  }
  return true;
}

bool services::email::accessEndpoint(char *host, size_t host_len, uint16_t *port) {
  if (!host || host_len == 0 || !port) return false;

  String password;
  load_password(password);
  if (!config_is_valid(password)) return false;

  strncpy(host, config::smtp::HOST, host_len - 1);
  host[host_len - 1] = '\0';
  *port = config::smtp::PORT;
  return host[0] != '\0';
}

bool services::email::connect() {
  String password;
  load_password(password);
  if (!config_is_valid(password)) {
    Serial.println("[email] invalid config");
    return false;
  }

  if (connected && active_session && active_session->isConnected())
    return true;

  if (!WiFi.isConnected()) {
    Serial.println("[email] WiFi not connected");
    return false;
  }

  if (active_session && active_session->isConnected())
    active_session->stop();

  if (!do_connect(password))
    return false;

  connected = true;
  return true;
}

bool services::email::sendTest() {
  if (strlen(config::smtp::HOST) == 0 || strlen(config::smtp::DOMAIN) == 0) {
    Serial.println("[email] invalid config for test email");
    return false;
  }
  if (strlen(config::smtp::FROM_EMAIL) == 0 || strlen(config::smtp::TO_EMAIL) == 0) {
    Serial.println("[email] missing from/to email");
    return false;
  }
  if (!services::email::connect()) return false;

  SMTPMessage message;
  message.headers.add(rfc822_from, format_sender());
  message.headers.add(rfc822_to, config::smtp::TO_EMAIL);
  message.headers.add(rfc822_subject,
                      String(config::smtp::SUBJECT_PREFIX) + " SMTP test");
  message.headers.addCustom("Importance", "High");
  message.headers.addCustom("X-Priority", "1");

  message.text.body(
      String("SMTP test from ceratina firmware.\r\n")
      + "Host: " + config::smtp::HOST + ":" + String(config::smtp::PORT));

  message.html.body(
      String("<html><body>")
      + "<p>SMTP test from ceratina firmware.</p>"
      + "<p>Host: " + config::smtp::HOST + ":" + String(config::smtp::PORT) + "</p>"
      + "<p>Chip: " + ESP.getChipModel() + " rev" + String(ESP.getChipRevision())
      + " &bull; Heap: " + String(ESP.getFreeHeap() / 1024) + " KB free</p>"
      + "</body></html>");

  message.timestamp = message_timestamp();

  if (!active_session->send(message)) {
    SMTPStatus s = active_session->status();
    Serial.printf("[email] send failed: %d/%d %s\n",
                  s.statusCode, s.errorCode, s.text.c_str());
    return false;
  }

  Serial.println("[email] test email sent");
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Tests
// ─────────────────────────────────────────────────────────────────────────────
#ifdef PIO_UNIT_TESTING


#include "email.h"
#include "../testing/it.h"

#include <Arduino.h>
#include <string.h>

static void test_endpoint_matches_flags(void) {
  char host[128] = {0};
  uint16_t port = 0;

#if CERATINA_SMTP_ENABLED
  bool ok = services::email::accessEndpoint(host, sizeof(host), &port);
  TEST_ASSERT_TRUE_MESSAGE(ok, "get_endpoint returned false");
  TEST_ASSERT_EQUAL_STRING(config::smtp::HOST, host);
  TEST_ASSERT_EQUAL_UINT16(config::smtp::PORT, port);
#else
  bool ok = services::email::accessEndpoint(host, sizeof(host), &port);
  TEST_ASSERT_FALSE_MESSAGE(ok, "should fail when SMTP not configured");

#endif
}

static void test_flags_are_valid(void) {
#if CERATINA_SMTP_ENABLED
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, (int)strlen(config::smtp::HOST),
    "SMTP host must not be empty when enabled");
  TEST_ASSERT_GREATER_THAN_MESSAGE(0, (int)strlen(config::smtp::DOMAIN),
    "SMTP domain must not be empty when enabled");
  TEST_ASSERT_GREATER_THAN_UINT16_MESSAGE(0, config::smtp::PORT,
    "SMTP port must be > 0 when enabled");
#else
  TEST_IGNORE_MESSAGE("SMTP not enabled");
#endif
}

static void test_connects_with_flags(void) {
#if CERATINA_SMTP_ENABLED
  if (!WiFi.isConnected()) {
    TEST_IGNORE_MESSAGE("WiFi not connected — skipping SMTP connect test");
    return;
  }

  bool ok = services::email::connect();
  TEST_ASSERT_TRUE_MESSAGE(ok, "SMTP connect should succeed with configured flags");
#else
  TEST_IGNORE_MESSAGE("SMTP not enabled");
#endif
}

static void test_sends_test_email(void) {
#if CERATINA_SMTP_ENABLED
  if (!WiFi.isConnected()) {
    TEST_IGNORE_MESSAGE("WiFi not connected — skipping SMTP send test");
    return;
  }

  bool ok = services::email::sendTest();
  TEST_ASSERT_TRUE_MESSAGE(ok, "SMTP test email should send successfully");
#else
  TEST_IGNORE_MESSAGE("SMTP not enabled");
#endif
}

void services::email::test() {
  it("email endpoint matches build flags", test_endpoint_matches_flags);
  it("email build flags are valid",        test_flags_are_valid);
  it("email connects with build flags",    test_connects_with_flags);
  it("email sends test email",             test_sends_test_email);
}

#endif
