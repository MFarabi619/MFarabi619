#include "database.h"

#include <sqlite.h>
#include <AsyncJson.h>
#include <ArduinoJson.h>

namespace {

struct QueryContext {
  JsonArray columns;
  JsonArray rows;
  bool first_row;
};

int collect_row(void *ctx, int cols, char **values, char **names) {
  auto *qc = static_cast<QueryContext *>(ctx);
  if (qc->first_row) {
    for (int i = 0; i < cols; i++)
      qc->columns.add(names[i]);
    qc->first_row = false;
  }
  JsonArray row = qc->rows.add<JsonArray>();
  for (int i = 0; i < cols; i++)
    row.add(values[i] ? (const char *)values[i] : nullptr);
  return 0;
}

void handle_status(AsyncWebServerRequest *request) {
  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  root["ok"] = true;
  JsonObject data = root["data"].to<JsonObject>();
  data["open"] = programs::sqlite::isOpen();
  data["path"] = programs::sqlite::currentPath();
  if (programs::sqlite::lastErrorCode() != SQLITE_OK) {
    data["last_error_code"] = programs::sqlite::lastErrorCode();
    data["last_error"] = programs::sqlite::lastError();
  }
  data["sqlite_memory_used"] = (long long)programs::sqlite::memoryUsed();
  data["sqlite_memory_highwater"] = (long long)programs::sqlite::memoryHighwater();
  response->setLength();
  request->send(response);
}

void handle_tables(AsyncWebServerRequest *request) {
  if (!programs::sqlite::isOpen()) {
    request->send(400, "application/json", "{\"ok\":false,\"error\":\"not open\"}");
    return;
  }

  AsyncJsonResponse *response = new AsyncJsonResponse();
  JsonObject root = response->getRoot().to<JsonObject>();
  JsonArray tables = root["data"].to<JsonArray>();

  struct TablesCtx { JsonArray *arr; };
  TablesCtx ctx = {&tables};

  char *err = nullptr;
  int rc = sqlite3_exec(programs::sqlite::handle(),
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      [](void *ctx, int cols, char **values, char **) -> int {
        auto *tc = static_cast<TablesCtx *>(ctx);
        if (cols > 0 && values[0]) tc->arr->add(values[0]);
        return 0;
      }, &ctx, &err);

  root["ok"] = (rc == SQLITE_OK);
  if (rc != SQLITE_OK) {
    root["error"] = err ? err : "unknown";
    sqlite3_free(err);
  }
  response->setLength();
  request->send(response);
}

}

void services::http::api::database::registerRoutes(AsyncWebServer &server) {
  server.on("/api/database/status", HTTP_GET, handle_status);
  server.on("/api/database/tables", HTTP_GET, handle_tables);

  server.on("/api/database/close", HTTP_POST,
      [](AsyncWebServerRequest *request) {
    programs::sqlite::close();
    request->send(200, "application/json", "{\"ok\":true}");
  });

  AsyncCallbackJsonWebHandler &open_handler =
      server.on("/api/database/open", HTTP_POST,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject body = json.as<JsonObject>();
    const char *path = body["path"] | (const char *)nullptr;
    bool ok = programs::sqlite::open(path);

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    root["ok"] = ok;
    if (ok) {
      root["path"] = programs::sqlite::currentPath();
    } else {
      root["error"] = programs::sqlite::lastError();
    }
    response->setLength();
    request->send(response);
  });
  open_handler.setMaxContentLength(256);

  AsyncCallbackJsonWebHandler &exec_handler =
      server.on("/api/database/exec", HTTP_POST,
          [](AsyncWebServerRequest *request, JsonVariant &json) {
    if (!programs::sqlite::isOpen()) {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"not open\"}");
      return;
    }

    JsonObject body = json.as<JsonObject>();
    const char *sql = body["sql"] | (const char *)nullptr;
    if (!sql || sql[0] == '\0') {
      request->send(400, "application/json", "{\"ok\":false,\"error\":\"missing sql\"}");
      return;
    }

    AsyncJsonResponse *response = new AsyncJsonResponse();
    JsonObject root = response->getRoot().to<JsonObject>();
    JsonObject data = root["data"].to<JsonObject>();
    JsonArray columns = data["columns"].to<JsonArray>();
    JsonArray rows = data["rows"].to<JsonArray>();

    QueryContext qc = {columns, rows, true};
    char *err = nullptr;
    unsigned long start = micros();
    int rc = sqlite3_exec(programs::sqlite::handle(), sql, collect_row, &qc, &err);
    unsigned long elapsed = micros() - start;

    root["ok"] = (rc == SQLITE_OK);
    data["elapsed_us"] = elapsed;
    if (rc == SQLITE_OK) {
      int changes = programs::sqlite::changes();
      if (changes > 0) {
        data["changes"] = changes;
        data["last_insert_rowid"] = (long long)programs::sqlite::lastInsertRowid();
      }
    } else {
      root["error"] = err ? err : "unknown";
      root["error_code"] = sqlite3_extended_errcode(programs::sqlite::handle());
      sqlite3_free(err);
    }
    response->setLength();
    request->send(response);
  });
  exec_handler.setMaxContentLength(512);
}

#ifdef PIO_UNIT_TESTING

#include <testing/it.h>
#include "../../../hardware/storage.h"
#include <SD.h>

static void db_api_test_collect_row_populates_columns_once(void) {
  TEST_MESSAGE("user verifies collect_row captures column names on first row only");

  JsonDocument doc;
  JsonArray columns = doc["columns"].to<JsonArray>();
  JsonArray rows = doc["rows"].to<JsonArray>();
  QueryContext qc = {columns, rows, true};

  char *names[] = {(char *)"id", (char *)"name"};
  char *vals1[] = {(char *)"1", (char *)"alice"};
  char *vals2[] = {(char *)"2", (char *)"bob"};

  collect_row(&qc, 2, vals1, names);
  collect_row(&qc, 2, vals2, names);

  TEST_ASSERT_EQUAL_INT_MESSAGE(2, columns.size(),
      "device: should have 2 column names");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("id", columns[0].as<const char *>(),
      "device: first column should be 'id'");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("name", columns[1].as<const char *>(),
      "device: second column should be 'name'");
  TEST_ASSERT_EQUAL_INT_MESSAGE(2, rows.size(),
      "device: should have 2 rows");
  TEST_ASSERT_EQUAL_STRING("alice", rows[0][1].as<const char *>());
  TEST_ASSERT_EQUAL_STRING("bob", rows[1][1].as<const char *>());
}

static void db_api_test_collect_row_handles_null_values(void) {
  TEST_MESSAGE("user verifies collect_row represents SQL NULL as JSON null");

  JsonDocument doc;
  JsonArray columns = doc["columns"].to<JsonArray>();
  JsonArray rows = doc["rows"].to<JsonArray>();
  QueryContext qc = {columns, rows, true};

  char *names[] = {(char *)"v"};
  char *vals[] = {nullptr};

  collect_row(&qc, 1, vals, names);

  TEST_ASSERT_EQUAL_INT(1, rows.size());
  TEST_ASSERT_TRUE_MESSAGE(rows[0][0].isNull(),
      "device: NULL value should serialize as JSON null");
}

static void db_api_test_exec_roundtrip(void) {
  TEST_MESSAGE("user opens a database, creates a table, inserts, and queries via collect_row");

  TEST_ASSERT_TRUE(programs::sqlite::open("/sd/test_db_api.db"));
  sqlite3 *h = programs::sqlite::handle();
  char *err = nullptr;

  sqlite3_exec(h, "CREATE TABLE items(id INTEGER PRIMARY KEY, label TEXT);",
               nullptr, nullptr, &err);
  TEST_ASSERT_NULL(err);
  sqlite3_exec(h, "INSERT INTO items(label) VALUES('sensor_a');",
               nullptr, nullptr, &err);
  TEST_ASSERT_NULL(err);

  JsonDocument doc;
  JsonArray columns = doc["columns"].to<JsonArray>();
  JsonArray rows = doc["rows"].to<JsonArray>();
  QueryContext qc = {columns, rows, true};

  int rc = sqlite3_exec(h, "SELECT id, label FROM items;", collect_row, &qc, &err);
  TEST_ASSERT_EQUAL_INT_MESSAGE(SQLITE_OK, rc, "device: SELECT should succeed");
  TEST_ASSERT_EQUAL_INT(2, columns.size());
  TEST_ASSERT_EQUAL_INT(1, rows.size());
  TEST_ASSERT_EQUAL_STRING("sensor_a", rows[0][1].as<const char *>());

  programs::sqlite::close();
  SD.remove("/sd/test_db_api.db");
}

void services::http::api::database::test(void) {
  it("user verifies collect_row populates columns once", db_api_test_collect_row_populates_columns_once);
  it("user verifies collect_row handles NULL values", db_api_test_collect_row_handles_null_values);
  it("user verifies exec roundtrip through collect_row", db_api_test_exec_roundtrip);
}

#endif
