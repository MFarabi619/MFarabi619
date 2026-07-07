#include <zephyr/kernel.h>

#include <sqlite3.h>

#define DB_PATH "/lfs/sample.db"

static int print_row(void *unused, int column_count, char **values, char **names)
{
	ARG_UNUSED(unused);
	for (int i = 0; i < column_count; i++) {
		printk("%s=%s%s", names[i], values[i] ? values[i] : "NULL",
		       i + 1 < column_count ? "  " : "\n");
	}
	return 0;
}

static int exec_sql(sqlite3 *db, const char *sql)
{
	char *err = NULL;
	int rc = sqlite3_exec(db, sql, NULL, NULL, &err);
	if (rc != SQLITE_OK) {
		printk("SQL error (%d): %s\n", rc, err ? err : sqlite3_errmsg(db));
		sqlite3_free(err);
	}
	return rc;
}

int main(void)
{
	printk("SQLite %s on %s\n", sqlite3_libversion(), CONFIG_BOARD);

	sqlite3 *db = NULL;
	int rc = sqlite3_open(DB_PATH, &db);
	if (rc != SQLITE_OK) {
		printk("open %s failed: %s\n", DB_PATH, sqlite3_errmsg(db));
		sqlite3_close(db);
		return 0;
	}

	exec_sql(db, "CREATE TABLE IF NOT EXISTS readings("
		"id INTEGER PRIMARY KEY, sensor TEXT, value REAL);");
	exec_sql(db, "DELETE FROM readings;");
	exec_sql(db, "INSERT INTO readings(sensor, value) VALUES"
		"('temp', 21.5), ('humidity', 48.0), ('pressure', 1013.2);");

	printk("--- readings ---\n");
	sqlite3_exec(db, "SELECT id, sensor, value FROM readings ORDER BY id;",
		     print_row, NULL, NULL);

	sqlite3_close(db);
	printk("done\n");
	return 0;
}
