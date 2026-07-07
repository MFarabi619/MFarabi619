#include <errno.h>
#include <stdio.h>

#include <zephyr/kernel.h>
#include <zephyr/shell/shell.h>

#include <sqlite3.h>

static sqlite3 *current_db;

static int print_row(void *context, int column_count, char **values, char **names)
{
	const struct shell *sh = context;
	for (int i = 0; i < column_count; i++) {
		shell_fprintf(sh, SHELL_NORMAL, "%s=%s%s", names[i],
			      values[i] ? values[i] : "NULL",
			      i + 1 < column_count ? "  " : "\n");
	}
	return 0;
}

static int cmd_open(const struct shell *sh, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	if (current_db) {
		shell_warn(sh, "database already open; close it first");
		return -EALREADY;
	}
	int rc = sqlite3_open(argv[1], &current_db);
	if (rc != SQLITE_OK) {
		shell_error(sh, "open failed: %s", sqlite3_errmsg(current_db));
		sqlite3_close(current_db);
		current_db = NULL;
		return -EIO;
	}
	shell_print(sh, "opened %s", argv[1]);
	return 0;
}

static int cmd_close(const struct shell *sh, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);
	if (!current_db) {
		shell_warn(sh, "no database open");
		return -ENODEV;
	}
	sqlite3_close(current_db);
	current_db = NULL;
	shell_print(sh, "closed");
	return 0;
}

static int cmd_exec(const struct shell *sh, size_t argc, char **argv)
{
	if (!current_db) {
		shell_error(sh, "no database open; run 'sqlite open <path>' first");
		return -ENODEV;
	}

	char sql[CONFIG_SHELL_CMD_BUFF_SIZE];
	size_t offset = 0;
	for (size_t i = 1; i < argc; i++) {
		int needed = snprintf(sql + offset, sizeof(sql) - offset, "%s%s",
				      i > 1 ? " " : "", argv[i]);
		if (needed < 0 || (size_t)needed >= sizeof(sql) - offset) {
			shell_error(sh, "SQL exceeds buffer (%zu bytes)", sizeof(sql));
			return -EMSGSIZE;
		}
		offset += needed;
	}

	char *err = NULL;
	int rc = sqlite3_exec(current_db, sql, print_row, (void *)sh, &err);
	if (rc != SQLITE_OK) {
		shell_error(sh, "SQL error (%d): %s", rc,
			    err ? err : sqlite3_errmsg(current_db));
		sqlite3_free(err);
		return -EINVAL;
	}
	return 0;
}

static int cmd_version(const struct shell *sh, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);
	shell_print(sh, "SQLite %s", sqlite3_libversion());
	return 0;
}

SHELL_STATIC_SUBCMD_SET_CREATE(sub_sqlite,
	SHELL_CMD_ARG(open,    NULL, "Open a database file: open <path>",  cmd_open,    2, 0),
	SHELL_CMD_ARG(close,   NULL, "Close the current database",         cmd_close,   1, 0),
	SHELL_CMD_ARG(exec,    NULL, "Execute SQL: exec <sql tokens...>",  cmd_exec,    2, 62),
	SHELL_CMD_ARG(version, NULL, "Print SQLite library version",       cmd_version, 1, 0),
	SHELL_SUBCMD_SET_END
);

SHELL_CMD_REGISTER(sqlite, &sub_sqlite, "SQLite database operations", NULL);
