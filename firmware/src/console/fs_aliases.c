#include <zephyr/shell/shell.h>

#include <stdio.h>

static int fs_forward(const struct shell *sh, size_t argc, char **argv,
                      const char *cmd)
{
	char buf[256];
	int off = snprintf(buf, sizeof(buf), "fs %s", cmd);

	for (size_t i = 1; i < argc && off < (int)sizeof(buf); i++) {
		off += snprintf(buf + off, sizeof(buf) - off, " %s", argv[i]);
	}

	return shell_execute_cmd(sh, buf);
}

static int cmd_ls(const struct shell *sh, size_t argc, char **argv)
{
	return fs_forward(sh, argc, argv, "ls");
}

static int cmd_cd(const struct shell *sh, size_t argc, char **argv)
{
	return fs_forward(sh, argc, argv, "cd");
}

static int cmd_pwd(const struct shell *sh, size_t argc, char **argv)
{
	return fs_forward(sh, argc, argv, "pwd");
}

static int cmd_mkdir(const struct shell *sh, size_t argc, char **argv)
{
	return fs_forward(sh, argc, argv, "mkdir");
}

static int cmd_cat(const struct shell *sh, size_t argc, char **argv)
{
	return fs_forward(sh, argc, argv, "cat");
}

static int cmd_mount(const struct shell *sh, size_t argc, char **argv)
{
	return fs_forward(sh, argc, argv, "mount");
}

SHELL_CMD_ARG_REGISTER(ls, NULL, "List files", cmd_ls, 1, 1);
SHELL_CMD_ARG_REGISTER(cd, NULL, "Change directory", cmd_cd, 1, 1);
SHELL_CMD_REGISTER(pwd, NULL, "Print working directory", cmd_pwd);
SHELL_CMD_ARG_REGISTER(mkdir, NULL, "Create directory", cmd_mkdir, 2, 0);
SHELL_CMD_ARG_REGISTER(cat, NULL, "Display file", cmd_cat, 2, 0);
SHELL_CMD_ARG_REGISTER(mount, NULL, "Mount filesystem", cmd_mount, 1, 255);
