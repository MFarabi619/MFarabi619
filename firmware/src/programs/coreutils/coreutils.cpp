#include "coreutils.h"

#include <Console.h>

void programs::coreutils::registerAll() {
  Console.addCmd("date",     "show local date and time",       cmd_date);
  Console.addCmd("uptime",   "show system uptime",             cmd_uptime);
  Console.addCmd("free",     "show memory usage",              cmd_free);
  Console.addCmd("hostname", "read or set hostname",           "<new-name>", cmd_hostname);
  Console.addCmd("ifconfig", "show network interface status",  cmd_ifconfig);
  Console.addCmd("print",    "print argument to shell",        "<text>", cmd_print);
  Console.addCmd("sensors",  "show sensor inventory summary",  cmd_sensors);
  Console.addCmd("whoami",   "print current user",             cmd_whoami);
}
