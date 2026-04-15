#include "shell.h"
#include "commands.h"
#include "microfetch.h"
#include "console/prompt.h"
#include <identity.h>
#include "../coreutils/coreutils.h"
#include "../ssh/ssh_client.h"
#include "../ssh/ssh_server.h"
#include <sqlite.h>

#include <Arduino.h>
#include <Console.h>

static int cmd_resize(int argc, char **argv) {
  (void)argc; (void)argv;
  console::prompt::detect_width();
  Console.setPrompt(console::prompt::build("/"));
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
  Console.addCmd("resize", "detect terminal width", cmd_resize);
  programs::ssh_client::registerCommands();
  programs::ssh_fingerprint::registerCmd();
  programs::sqlite::registerCmd();
  Console.addHelpCmd();

  printf("%s", console::prompt::build_motd());
  printf("%s", programs::shell::microfetch::generate());
  fflush(stdout);

  console::prompt::detect_width();
  Console.setPrompt(console::prompt::build("/"));

  Console.attachToSerial(true);
}

void programs::shell::service() {
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void shell_test_initializes(void) {
  TEST_MESSAGE("user asks the device to initialize the console");
  programs::shell::initialize();
  TEST_MESSAGE("console initialized with serial I/O");
}

void programs::shell::test(void) {
  it("user observes that the console initializes",
     shell_test_initializes);
}

#endif
