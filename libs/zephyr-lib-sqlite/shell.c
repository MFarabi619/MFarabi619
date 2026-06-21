#include <errno.h>
#include <stdio.h>

#include <zephyr/kernel.h>
#include <zephyr/shell/shell.h>

extern int rust_sqlite_open(const struct shell *sh, const char *path);
extern int rust_sqlite_close(const struct shell *sh);
extern int rust_sqlite_exec(const struct shell *sh, const char *sql);
extern int rust_sqlite_version(const struct shell *sh);

void sqlite_shell_print_line(const struct shell *sh, const char *line)
{
	shell_print(sh, "%s", line);
}

void sqlite_shell_error_line(const struct shell *sh, const char *line)
{
	shell_error(sh, "%s", line);
}

static int cmd_open(const struct shell *sh, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	return rust_sqlite_open(sh, argv[1]);
}

static int cmd_close(const struct shell *sh, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);
	return rust_sqlite_close(sh);
}

static int cmd_exec(const struct shell *sh, size_t argc, char **argv)
{
	char *sql_buffer = k_malloc(CONFIG_SHELL_CMD_BUFF_SIZE);
	if (!sql_buffer) {
		shell_error(sh, "k_malloc(%d) failed", CONFIG_SHELL_CMD_BUFF_SIZE);
		return -ENOMEM;
	}
	size_t offset = 0;
	for (size_t index = 1; index < argc; index++) {
		int needed = snprintf(sql_buffer + offset, CONFIG_SHELL_CMD_BUFF_SIZE - offset,
				      "%s%s", index > 1 ? " " : "", argv[index]);
		if (needed < 0 || (size_t)needed >= CONFIG_SHELL_CMD_BUFF_SIZE - offset) {
			shell_error(sh, "SQL exceeds buffer (%d bytes)", CONFIG_SHELL_CMD_BUFF_SIZE);
			k_free(sql_buffer);
			return -EMSGSIZE;
		}
		offset += needed;
	}
	int rc = rust_sqlite_exec(sh, sql_buffer);
	k_free(sql_buffer);
	return rc;
}

static int cmd_version(const struct shell *sh, size_t argc, char **argv)
{
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);
	return rust_sqlite_version(sh);
}

SHELL_STATIC_SUBCMD_SET_CREATE(sub_sqlite,
	SHELL_CMD_ARG(open,    NULL, "Open a database file: open <path>",  cmd_open,    2, 0),
	SHELL_CMD_ARG(close,   NULL, "Close the current database",         cmd_close,   1, 0),
	SHELL_CMD_ARG(exec,    NULL, "Execute SQL: exec <sql tokens...>",  cmd_exec,    2, 62),
	SHELL_CMD_ARG(version, NULL, "Print SQLite library version",       cmd_version, 1, 0),
	SHELL_SUBCMD_SET_END
);

SHELL_CMD_REGISTER(sqlite, &sub_sqlite, "SQLite database operations", NULL);
