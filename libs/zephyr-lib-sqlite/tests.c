#include <string.h>

#include <zephyr/fs/fs.h>
#include <zephyr/ztest.h>

struct sqlite_fixture {
	const char *path;
};

static struct sqlite_fixture fixture = { .path = "/lfs/sqlite_test.db" };

static void *sqlite_setup(void)
{
	return &fixture;
}

static void sqlite_unlink_before(const struct ztest_unit_test *test, void *data)
{
	if (strcmp(test->test_suite_name, "sqlite") == 0) {
		struct sqlite_fixture *f = data;
		fs_unlink(f->path);
	}
}

ZTEST_RULE(sqlite_clean, sqlite_unlink_before, NULL);

extern int rust_test_sqlite_engine_announces_version(const char *path);
extern int rust_test_sqlite_opens_and_closes_cleanly(const char *path);
extern int rust_test_sqlite_inserts_and_queries_back_one_row(const char *path);
extern int rust_test_sqlite_prepared_statement_binds_and_steps(const char *path);
extern int rust_test_sqlite_transaction_commit_persists(const char *path);
extern int rust_test_sqlite_transaction_rollback_discards(const char *path);
extern int rust_test_sqlite_invalid_sql_returns_error(const char *path);
extern int rust_test_sqlite_data_persists_across_reopen(const char *path);
extern int rust_test_sqlite_empty_table_step_returns_done(const char *path);

ZTEST_SUITE(sqlite, NULL, sqlite_setup, NULL, NULL, NULL);

ZTEST_F(sqlite, engine_announces_version)
{
	zassert_equal(rust_test_sqlite_engine_announces_version(fixture->path), 0, "");
}

ZTEST_F(sqlite, opens_and_closes_cleanly)
{
	zassert_equal(rust_test_sqlite_opens_and_closes_cleanly(fixture->path), 0, "");
}

ZTEST_F(sqlite, inserts_and_queries_back_one_row)
{
	zassert_equal(rust_test_sqlite_inserts_and_queries_back_one_row(fixture->path), 0, "");
}

ZTEST_F(sqlite, prepared_statement_binds_and_steps)
{
	zassert_equal(rust_test_sqlite_prepared_statement_binds_and_steps(fixture->path), 0, "");
}

ZTEST_F(sqlite, transaction_commit_persists)
{
	zassert_equal(rust_test_sqlite_transaction_commit_persists(fixture->path), 0, "");
}

ZTEST_F(sqlite, transaction_rollback_discards)
{
	zassert_equal(rust_test_sqlite_transaction_rollback_discards(fixture->path), 0, "");
}

ZTEST_F(sqlite, invalid_sql_returns_error)
{
	zassert_equal(rust_test_sqlite_invalid_sql_returns_error(fixture->path), 0, "");
}

ZTEST_F(sqlite, data_persists_across_reopen)
{
	zassert_equal(rust_test_sqlite_data_persists_across_reopen(fixture->path), 0, "");
}

ZTEST_F(sqlite, empty_table_step_returns_done)
{
	zassert_equal(rust_test_sqlite_empty_table_step_returns_done(fixture->path), 0, "");
}
