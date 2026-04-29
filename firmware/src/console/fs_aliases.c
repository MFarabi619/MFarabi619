#include <zephyr/shell/shell.h>
#include <zephyr/fs/fs.h>

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

static int recursive_delete(const char *path)
{
	struct fs_dirent entry;
	int result = fs_stat(path, &entry);

	if (result < 0) {
		return result;
	}

	if (entry.type == FS_DIR_ENTRY_FILE) {
		return fs_unlink(path);
	}

	struct fs_dir_t dir;

	fs_dir_t_init(&dir);
	result = fs_opendir(&dir, path);
	if (result < 0) {
		return result;
	}

	char child[256];

	while (true) {
		result = fs_readdir(&dir, &entry);
		if (result < 0) {
			break;
		}

		if (entry.name[0] == '\0') {
			break;
		}

		snprintf(child, sizeof(child), "%s/%s", path, entry.name);
		result = recursive_delete(child);
		if (result < 0) {
			break;
		}
	}

	fs_closedir(&dir);

	if (result < 0) {
		return result;
	}

	return fs_unlink(path);
}

static int cmd_rm(const struct shell *sh, size_t argc, char **argv)
{
	if (argv[1][0] != '/') {
		shell_error(sh, "rm requires an absolute path (e.g. /sd:/public)");
		return -EINVAL;
	}

	int result = recursive_delete(argv[1]);

	if (result < 0) {
		shell_error(sh, "Failed to remove %s (%d)", argv[1], result);
	}

	return result;
}

SHELL_CMD_ARG_REGISTER(ls, NULL, "List files", cmd_ls, 1, 1);
SHELL_CMD_ARG_REGISTER(cd, NULL, "Change directory", cmd_cd, 1, 1);
SHELL_CMD_REGISTER(pwd, NULL, "Print working directory", cmd_pwd);
SHELL_CMD_ARG_REGISTER(mkdir, NULL, "Create directory", cmd_mkdir, 2, 0);
SHELL_CMD_ARG_REGISTER(cat, NULL, "Display file", cmd_cat, 2, 0);
SHELL_CMD_ARG_REGISTER(mount, NULL, "Mount filesystem", cmd_mount, 1, 255);
SHELL_CMD_ARG_REGISTER(rm, NULL, "Remove file or directory (absolute path)", cmd_rm, 2, 0);
