#include "shell.h"
#include "commands.h"
#include "microfetch.h"
#include "console/path.h"
#include "console/prompt.h"
#include <identity.h>
#include <storage.h>
#include "../coreutils/coreutils.h"
#include "../ssh/ssh_client.h"
#include "../ssh/ssh_server.h"
#include <sqlite.h>

#include <Arduino.h>
#include <Console.h>
#include <SD.h>

//------------------------------------------
//  Serial shell state
//------------------------------------------
char g_cwd[128] = "/";

static void update_prompt() {
  Console.setPrompt(console::prompt::build(g_cwd));
}

static int cmd_resize(int argc, char **argv) {
  (void)argc; (void)argv;
  console::prompt::detect_width();
  update_prompt();
  return 0;
}

static int cmd_cd(int argc, char **argv) {
  char prev[128];
  strlcpy(prev, g_cwd, sizeof(prev));

  if (argc == 1)
    strlcpy(g_cwd, console::path::home_dir(), sizeof(g_cwd));
  else
    console::path::apply_cd(g_cwd, sizeof(g_cwd), argv[1]);

  if (!SD.exists(g_cwd)) {
    strlcpy(g_cwd, prev, sizeof(g_cwd));
    printf("no such directory\n");
    return 1;
  }

  update_prompt();
  return 0;
}

static int cmd_pwd(int argc, char **argv) {
  (void)argc; (void)argv;
  printf("%s\n", g_cwd);
  return 0;
}

static int cmd_clear(int argc, char **argv) {
  (void)argc; (void)argv;
  printf("\x1b[2J\x1b[H");
  return 0;
}

void programs::shell::initialize() {
  services::identity::initialize();

  Console.setMaxHistory(32);
  if (!Console.begin()) {
    Serial.println(F("[console] init failed"));
    return;
  }

  programs::shell::commands::registerAll();
  programs::coreutils::registerAll();
  programs::shell::microfetch::registerCmd();
  Console.addCmd("cd",     "change directory",        "[dir]", cmd_cd);
  Console.addCmd("pwd",    "print working directory",  cmd_pwd);
  Console.addCmd("clear",  "clear the screen",         cmd_clear);
  Console.addCmd("resize", "detect terminal width",    cmd_resize);
  programs::ssh_client::registerCommands();
  programs::ssh_fingerprint::registerCmd();
  programs::sqlite::registerCmd();
  Console.addHelpCmd();

  printf("%s", console::prompt::build_motd());
  printf("%s", programs::shell::microfetch::generate());
  fflush(stdout);

  console::prompt::detect_width();
  strlcpy(g_cwd, console::path::home_dir(), sizeof(g_cwd));
  update_prompt();

  Console.attachToSerial(true);
}

void programs::shell::service() {
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_shell_initializes(void) {
  WHEN("the console is initialized");
  programs::shell::initialize();
  THEN("it completes without error");
}

void programs::shell::test(void) {
  MODULE("Shell");
  RUN_TEST(test_shell_initializes);
}

#endif
