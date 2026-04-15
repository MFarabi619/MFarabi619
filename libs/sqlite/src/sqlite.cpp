#include "sqlite.h"

#include <Arduino.h>
#include <Console.h>
#include <string.h>

namespace {

sqlite3 *db = nullptr;
char db_path[128] = "/sd/app.db";
char last_err[128] = "";
int last_err_code = SQLITE_OK;
bool is_initialized = false;

constexpr const char *TUNING_PRAGMAS =
    "PRAGMA journal_mode=OFF;"
    "PRAGMA locking_mode=EXCLUSIVE;"
    "PRAGMA synchronous=OFF;"
    "PRAGMA temp_store=MEMORY;";

void record_error() {
  last_err_code = sqlite3_extended_errcode(db);
  strlcpy(last_err, sqlite3_errmsg(db), sizeof(last_err));
}

void clear_error() {
  last_err_code = SQLITE_OK;
  last_err[0] = '\0';
}

//------------------------------------------
//  Row printer for sqlite3_exec callback
//------------------------------------------
int print_row(void *ctx, int cols, char **values, char **names) {
  (void)ctx; (void)names;
  for (int i = 0; i < cols; i++) {
    if (i > 0) printf("\t");
    printf("%s", values[i] ? values[i] : "NULL");
  }
  printf("\n");
  return 0;
}

//------------------------------------------
//  Subcommands
//------------------------------------------
void subcmd_open(int argc, char **argv) {
  if (db) {
    printf("already open: %s\n", db_path);
    return;
  }
  const char *path = (argc >= 3) ? argv[2] : nullptr;
  if (programs::sqlite::open(path))
    printf("opened %s\n", db_path);
  else
    printf("error: %s\n", last_err);
}

void subcmd_close() {
  programs::sqlite::close();
  printf("closed\n");
}

void subcmd_status() {
  printf("open=%s\npath=%s\n", db ? "true" : "false", db_path);
  if (last_err_code != SQLITE_OK)
    printf("last_error=%d %s\n", last_err_code, last_err);
  printf("sqlite_memory_used=%lld\nsqlite_memory_highwater=%lld\n",
         (long long)sqlite3_memory_used(),
         (long long)sqlite3_memory_highwater(0));
  printf("extensions=shox96_0_2c,shox96_0_2d,unishox1c,unishox1d\n");
}

void subcmd_tables() {
  if (!db) { printf("not open\n"); return; }
  char *err = nullptr;
  int rc = sqlite3_exec(db,
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      print_row, nullptr, &err);
  if (rc != SQLITE_OK) {
    printf("error: %s\n", err ? err : "unknown");
    sqlite3_free(err);
  }
}

void subcmd_exec(int argc, char **argv) {
  if (!db) { printf("not open\n"); return; }
  if (argc < 3) { printf("usage: sqlite exec <sql>\n"); return; }

  char sql[512];
  size_t pos = 0;
  for (int i = 2; i < argc && pos < sizeof(sql) - 1; i++) {
    if (i > 2 && pos < sizeof(sql) - 1) sql[pos++] = ' ';
    size_t len = strlen(argv[i]);
    if (pos + len >= sizeof(sql)) break;
    memcpy(sql + pos, argv[i], len);
    pos += len;
  }
  sql[pos] = '\0';

  char *err = nullptr;
  unsigned long start = micros();
  int rc = sqlite3_exec(db, sql, print_row, nullptr, &err);
  unsigned long elapsed = micros() - start;

  if (rc != SQLITE_OK) {
    record_error();
    printf("error %d: %s\n", last_err_code, err ? err : last_err);
    sqlite3_free(err);
  } else {
    clear_error();
    int changes = sqlite3_changes(db);
    if (changes > 0)
      printf("ok %d row(s) affected, last_rowid=%lld (%lu us)\n",
             changes, (long long)sqlite3_last_insert_rowid(db), elapsed);
    else
      printf("ok (%lu us)\n", elapsed);
  }
}

//------------------------------------------
//  Console command
//------------------------------------------
int cmd_sqlite(int argc, char **argv) {
  if (argc < 2) {
    printf("usage: sqlite open [path]   open database (default /sd/app.db)\n"
           "       sqlite close         close database\n"
           "       sqlite exec <sql>    execute SQL statement\n"
           "       sqlite tables        list tables\n"
           "       sqlite status        show connection status\n");
    return 0;
  }

  const char *sub = argv[1];
  if      (strcmp(sub, "open")   == 0) subcmd_open(argc, argv);
  else if (strcmp(sub, "close")  == 0) subcmd_close();
  else if (strcmp(sub, "exec")   == 0) subcmd_exec(argc, argv);
  else if (strcmp(sub, "tables") == 0) subcmd_tables();
  else if (strcmp(sub, "status") == 0) subcmd_status();
  else printf("unknown subcommand: %s\n", sub);
  return 0;
}

} // anonymous namespace

//------------------------------------------
//  Public API
//------------------------------------------
bool programs::sqlite::open(const char *path) {
  if (db) return true;

  if (!is_initialized) {
    sqlite3_initialize();
    is_initialized = true;
  }

  if (path && path[0] != '\0')
    strlcpy(db_path, path, sizeof(db_path));

  int rc = sqlite3_open_v2(db_path, &db,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX,
      nullptr);
  if (rc != SQLITE_OK) {
    record_error();
    sqlite3_close(db);
    db = nullptr;
    return false;
  }

  clear_error();
  sqlite3_busy_timeout(db, 1000);
  sqlite3_limit(db, SQLITE_LIMIT_SQL_LENGTH, 512);
  sqlite3_exec(db, TUNING_PRAGMAS, nullptr, nullptr, nullptr);
  return true;
}

void programs::sqlite::close() {
  if (db) {
    sqlite3_close(db);
    db = nullptr;
  }
}

bool programs::sqlite::isOpen()              { return db != nullptr; }
const char *programs::sqlite::currentPath()  { return db_path; }
sqlite3 *programs::sqlite::handle()          { return db; }
int programs::sqlite::lastErrorCode()        { return last_err_code; }
const char *programs::sqlite::lastError()    { return last_err; }

int programs::sqlite::changes() {
  return db ? sqlite3_changes(db) : 0;
}

sqlite3_int64 programs::sqlite::lastInsertRowid() {
  return db ? sqlite3_last_insert_rowid(db) : 0;
}

sqlite3_int64 programs::sqlite::memoryUsed() {
  return sqlite3_memory_used();
}

sqlite3_int64 programs::sqlite::memoryHighwater(bool reset) {
  return sqlite3_memory_highwater(reset ? 1 : 0);
}

void programs::sqlite::registerCmd() {
  Console.addCmd("sqlite3", "SQLite3 database shell",
                 "<open|close|exec|tables|status> [...]", cmd_sqlite);
}

//------------------------------------------
//  Tests
//------------------------------------------
#ifdef PIO_UNIT_TESTING

#include <unity.h>
#include <SD.h>

static char _it_buf[256];
static inline void _it_run(void (*func)(void), const char *desc, int line) {
  strncpy(_it_buf, desc, sizeof(_it_buf) - 1);
  _it_buf[sizeof(_it_buf) - 1] = '\0';
  for (char *p = _it_buf; *p; p++) { if (*p == ' ') *p = '_'; }
  UnityDefaultTestRun(func, _it_buf, line);
}
#define it(description, test_func) _it_run(test_func, description, __LINE__)

static void sqlite_test_open_close(void) {
  TEST_MESSAGE("user opens and closes a database");

  TEST_ASSERT_FALSE_MESSAGE(programs::sqlite::isOpen(),
      "device: database should start closed");

  TEST_ASSERT_TRUE_MESSAGE(programs::sqlite::open("/sd/test_sqlite.db"),
      "device: open should succeed on SD card");
  TEST_ASSERT_TRUE_MESSAGE(programs::sqlite::isOpen(),
      "device: isOpen should return true after open");

  programs::sqlite::close();
  TEST_ASSERT_FALSE_MESSAGE(programs::sqlite::isOpen(),
      "device: isOpen should return false after close");

  SD.remove("/sd/test_sqlite.db");
}

static void sqlite_test_open_idempotent(void) {
  TEST_MESSAGE("user opens an already-open database without error");

  TEST_ASSERT_TRUE(programs::sqlite::open("/sd/test_sqlite_idem.db"));
  TEST_ASSERT_TRUE_MESSAGE(programs::sqlite::open("/sd/test_sqlite_idem.db"),
      "device: second open should return true without error");

  programs::sqlite::close();
  SD.remove("/sd/test_sqlite_idem.db");
}

static void sqlite_test_create_insert_select(void) {
  TEST_MESSAGE("user creates a table, inserts a row, and queries it back");

  TEST_ASSERT_TRUE(programs::sqlite::open("/sd/test_sqlite_cis.db"));
  sqlite3 *h = programs::sqlite::handle();
  char *err = nullptr;

  TEST_ASSERT_EQUAL_INT_MESSAGE(SQLITE_OK,
      sqlite3_exec(h, "CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT);",
                   nullptr, nullptr, &err),
      "device: CREATE TABLE should succeed");
  TEST_ASSERT_NULL(err);

  TEST_ASSERT_EQUAL_INT_MESSAGE(SQLITE_OK,
      sqlite3_exec(h, "INSERT INTO t(v) VALUES('hello');",
                   nullptr, nullptr, &err),
      "device: INSERT should succeed");
  TEST_ASSERT_NULL(err);

  sqlite3_stmt *stmt = nullptr;
  TEST_ASSERT_EQUAL_INT(SQLITE_OK,
      sqlite3_prepare_v2(h, "SELECT v FROM t LIMIT 1;", -1, &stmt, nullptr));
  TEST_ASSERT_EQUAL_INT(SQLITE_ROW, sqlite3_step(stmt));
  TEST_ASSERT_EQUAL_STRING_MESSAGE("hello",
      (const char *)sqlite3_column_text(stmt, 0),
      "device: queried value should match inserted value");
  sqlite3_finalize(stmt);

  programs::sqlite::close();
  SD.remove("/sd/test_sqlite_cis.db");
}

static void sqlite_test_error_on_bad_sql(void) {
  TEST_MESSAGE("user executes invalid SQL and observes an error code");

  TEST_ASSERT_TRUE(programs::sqlite::open("/sd/test_sqlite_err.db"));
  sqlite3 *h = programs::sqlite::handle();
  char *err = nullptr;

  int rc = sqlite3_exec(h, "NOT VALID SQL;", nullptr, nullptr, &err);
  TEST_ASSERT_NOT_EQUAL_INT_MESSAGE(SQLITE_OK, rc,
      "device: invalid SQL should return an error");
  if (err) sqlite3_free(err);

  programs::sqlite::close();
  SD.remove("/sd/test_sqlite_err.db");
}

static void sqlite_test_pragmas_applied(void) {
  TEST_MESSAGE("user verifies tuning PRAGMAs are active after open");

  TEST_ASSERT_TRUE(programs::sqlite::open("/sd/test_sqlite_prag.db"));
  sqlite3 *h = programs::sqlite::handle();

  sqlite3_stmt *stmt = nullptr;
  TEST_ASSERT_EQUAL_INT(SQLITE_OK,
      sqlite3_prepare_v2(h, "PRAGMA journal_mode;", -1, &stmt, nullptr));
  TEST_ASSERT_EQUAL_INT(SQLITE_ROW, sqlite3_step(stmt));
  TEST_ASSERT_EQUAL_STRING_MESSAGE("off",
      (const char *)sqlite3_column_text(stmt, 0),
      "device: journal_mode should be OFF for SD card performance");
  sqlite3_finalize(stmt);

  programs::sqlite::close();
  SD.remove("/sd/test_sqlite_prag.db");
}

static void sqlite_test_changes_and_rowid(void) {
  TEST_MESSAGE("user inserts rows and checks changes count and last rowid");

  TEST_ASSERT_TRUE(programs::sqlite::open("/sd/test_sqlite_chg.db"));
  sqlite3 *h = programs::sqlite::handle();
  char *err = nullptr;

  sqlite3_exec(h, "CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT);",
               nullptr, nullptr, &err);
  TEST_ASSERT_NULL(err);

  sqlite3_exec(h, "INSERT INTO t(v) VALUES('a');", nullptr, nullptr, &err);
  TEST_ASSERT_NULL(err);
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, programs::sqlite::changes(),
      "device: changes should be 1 after single INSERT");
  TEST_ASSERT_EQUAL_INT64_MESSAGE(1, programs::sqlite::lastInsertRowid(),
      "device: last rowid should be 1 after first INSERT");

  sqlite3_exec(h, "INSERT INTO t(v) VALUES('b');", nullptr, nullptr, &err);
  TEST_ASSERT_NULL(err);
  TEST_ASSERT_EQUAL_INT64_MESSAGE(2, programs::sqlite::lastInsertRowid(),
      "device: last rowid should be 2 after second INSERT");

  programs::sqlite::close();
  SD.remove("/sd/test_sqlite_chg.db");
}

static void sqlite_test_memory_tracking(void) {
  TEST_MESSAGE("user checks SQLite memory usage stats");

  sqlite3_int64 used = programs::sqlite::memoryUsed();
  sqlite3_int64 high = programs::sqlite::memoryHighwater();

  char msg[96];
  snprintf(msg, sizeof(msg), "memory_used=%lld highwater=%lld",
           (long long)used, (long long)high);
  TEST_MESSAGE(msg);

  TEST_ASSERT_GREATER_OR_EQUAL_INT64_MESSAGE(0, used,
      "device: memory_used should be non-negative");
  TEST_ASSERT_GREATER_OR_EQUAL_INT64_MESSAGE(used, high,
      "device: highwater should be >= current usage");
}

void programs::sqlite::test() {
  it("user opens and closes a database", sqlite_test_open_close);
  it("user opens an already-open database without error", sqlite_test_open_idempotent);
  it("user creates a table inserts a row and queries it back", sqlite_test_create_insert_select);
  it("user executes invalid SQL and observes an error code", sqlite_test_error_on_bad_sql);
  it("user verifies tuning PRAGMAs are active after open", sqlite_test_pragmas_applied);
  it("user inserts rows and checks changes and rowid", sqlite_test_changes_and_rowid);
  it("user checks SQLite memory usage stats", sqlite_test_memory_tracking);
}

#endif
