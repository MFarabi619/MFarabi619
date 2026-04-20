#include <console/prompt.h>
#include <console/ansi.h>
#include <console/icons.h>

#include <stdio.h>
#include <string.h>
#include <zephyr/kernel.h>
#include <zephyr/net/hostname.h>
#include <zephyr/shell/shell.h>
#include <zephyr/shell/shell_types.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(prompt);

static const struct shell *g_shell;
static char g_prompt[2048];

//---

int visible_width(const char *s)
{
	int w = 0;
	bool in_esc = false;

	while (*s) {
		if (*s == '\x1b') {
			in_esc = true;
			s++;
			continue;
		}
		if (in_esc) {
			if ((*s >= 'A' && *s <= 'Z') || (*s >= 'a' && *s <= 'z')) {
				in_esc = false;
			}
			s++;
			continue;
		}
		unsigned char c = (unsigned char)*s;
		if (c < 0x80) {
			w++;
			s++;
		} else if ((c & 0xE0) == 0xC0) {
			w++; s += 2;
		} else if ((c & 0xF0) == 0xE0) {
			w++; s += 3;
		} else if ((c & 0xF8) == 0xF0) {
			w++; s += 4;
		} else {
			s++;
		}
	}
	return w;
}

const char *last_path_component(const char *path)
{
	const char *p = strrchr(path, '/');
	if (!p || *(p + 1) == '\0') {
		return path;
	}
	return p + 1;
}

const char *cwd_glyph(const char *cwd)
{
	if (strcmp(cwd, "/") == 0) {
		return NF_FA_LOCK;
	}
	if (strcmp(cwd, "~") == 0 || strncmp(cwd, "~/", 2) == 0) {
		return NF_FA_HOME;
	}
	return NF_FA_FOLDER_OPEN;
}

//---

uint16_t prompt_terminal_width(void)
{
	if (g_shell) {
		return g_shell->ctx->vt100_ctx.cons.terminal_wid;
	}
	return CONFIG_SHELL_DEFAULT_TERMINAL_WIDTH;
}

static const char *build_prompt(const char *cwd)
{
	const char *display = last_path_component(cwd);
	const char *glyph = cwd_glyph(cwd);
	const char *hostname = net_hostname_get();

	/* Uptime string */
	char time_str[24];
	uint32_t uptime_s = k_uptime_get() / 1000;
	snprintf(time_str, sizeof(time_str), "%lum%lus",
		 (unsigned long)(uptime_s / 60),
		 (unsigned long)(uptime_s % 60));

	/* RAM */
	char ram_str[16];
	char ram_pct[8];
#ifdef CONFIG_SYS_HEAP_RUNTIME_STATS
	extern struct k_heap _system_heap;
	struct sys_memory_stats stats;
	sys_heap_runtime_stats_get(&_system_heap.heap, &stats);
	uint32_t heap_free = stats.free_bytes;
	uint32_t heap_total = stats.free_bytes + stats.allocated_bytes;
	uint32_t pct = heap_total > 0
		? ((heap_total - heap_free) * 100) / heap_total : 0;
	if (heap_free >= 1024 * 1024) {
		snprintf(ram_str, sizeof(ram_str), "%.1fM",
			 heap_free / (1024.0f * 1024.0f));
	} else {
		snprintf(ram_str, sizeof(ram_str), "%.1fK",
			 heap_free / 1024.0f);
	}
	snprintf(ram_pct, sizeof(ram_pct), "%lu%%", (unsigned long)pct);
#else
	snprintf(ram_str, sizeof(ram_str), "?");
	snprintf(ram_pct, sizeof(ram_pct), "?");
#endif

	/* Context */
	char context[80];
	snprintf(context, sizeof(context), "root@%s", hostname);

	/* Left segment */
	char left[256];
	snprintf(left, sizeof(left),
		ANSI_DIM FRAME_TOP_LEFT ANSI_RESET
		PROMPT_OS_BG PROMPT_OS_FG " " NF_FA_MICROCHIP " "
		PROMPT_DIR_BG PROMPT_OS_BG_AS_FG NF_PLE_LEFT_HARD
		PROMPT_DIR_BG PROMPT_DIR_FG " %s %s "
		ANSI_RESET PROMPT_DIR_BG_AS_FG NF_PLE_LEFT_HARD ANSI_RESET,
		glyph, display);

	/* Right segment */
	char right[384];
	snprintf(right, sizeof(right),
		PROMPT_CTX_BG_AS_FG NF_PLE_RIGHT_HARD
		PROMPT_CTX_BG PROMPT_CTX_FG " %s "
		PROMPT_RAM_BG PROMPT_RAM_FG NF_PLE_RIGHT_HARD " "
		PROMPT_RAM_BG PROMPT_RAM_FG "%s " NF_MD_RAM " %s "
		NF_PLE_RIGHT_SOFT " xtensa " NF_MD_ARCH " "
		PROMPT_ARCH_BG PROMPT_CLOCK_BG_AS_FG NF_PLE_RIGHT_HARD
		PROMPT_CLOCK_BG PROMPT_CLOCK_FG " %s " NF_FA_CLOCK " " ANSI_RESET
		ANSI_DIM "\xe2\x94\x80\xe2\x95\xae" ANSI_RESET,
		context, ram_pct, ram_str, time_str);

	int left_vis = visible_width(left);
	int right_vis = visible_width(right);

	int fill = (int)prompt_terminal_width() - left_vis - right_vis;
	if (fill < 1) {
		fill = 1;
	}

	/* Assemble into g_prompt */
	int pos = snprintf(g_prompt, sizeof(g_prompt), "%s" ANSI_DIM, left);
	for (int i = 0; i < fill && pos < (int)sizeof(g_prompt) - 4; i++) {
		g_prompt[pos++] = '\xe2';
		g_prompt[pos++] = '\x94';
		g_prompt[pos++] = '\x80';
	}
	snprintf(g_prompt + pos, sizeof(g_prompt) - pos,
		ANSI_RESET "%s\r\n" ANSI_DIM FRAME_BOT_LEFT ANSI_RESET " ",
		right);

	return g_prompt;
}

bool prompt_init(const struct shell *sh)
{
	g_shell = sh;
	LOG_INF("prompt initialized (width=%u)", prompt_terminal_width());
	prompt_update(sh);
	return true;
}

void prompt_update(const struct shell *sh)
{
	const char *prompt = build_prompt("/");
	shell_prompt_change(sh, prompt);
}

void prompt_print_motd(const struct shell *sh, const char *remote_ip)
{
	const char *hostname = net_hostname_get();

	shell_fprintf(sh, SHELL_NORMAL,
		"\r\n"
		"Welcome to %s!\r\n"
		"\r\n"
		"System information:     microfetch\r\n"
		"Hardware sensors:       sensor get\r\n"
		"Network interfaces:     net iface\r\n"
		"Memory usage:           kernel stacks\r\n"
		"Show all commands:      help\r\n"
		"\r\n",
		hostname);
}

//---

#if defined(CONFIG_ZTEST) && defined(CONFIG_TEST_PROMPT)
#include <zephyr/ztest.h>

ZTEST_SUITE(prompt, NULL, NULL, NULL, NULL, NULL);

ZTEST(prompt, test_visible_width_plain)
{
	zassert_equal(visible_width("hello"), 5);
}

ZTEST(prompt, test_visible_width_ansi)
{
	zassert_equal(visible_width("\x1b[31mred\x1b[0m"), 3);
}

ZTEST(prompt, test_visible_width_utf8_2byte)
{
	zassert_equal(visible_width("\xc2\xb0"), 1);
}

ZTEST(prompt, test_cwd_glyph_root)
{
	zassert_str_equal(cwd_glyph("/"), NF_FA_LOCK);
}

ZTEST(prompt, test_cwd_glyph_home)
{
	zassert_str_equal(cwd_glyph("~"), NF_FA_HOME);
}

ZTEST(prompt, test_cwd_glyph_dir)
{
	zassert_str_equal(cwd_glyph("/var/log"), NF_FA_FOLDER_OPEN);
}

ZTEST(prompt, test_last_path_component_nested)
{
	zassert_str_equal(last_path_component("/var/log"), "log");
}

ZTEST(prompt, test_last_path_component_root)
{
	zassert_str_equal(last_path_component("/"), "/");
}
#endif
