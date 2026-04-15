#pragma once

namespace programs::coreutils {

void registerAll();

int cmd_date(int argc, char **argv);
int cmd_uptime(int argc, char **argv);
int cmd_free(int argc, char **argv);
int cmd_hostname(int argc, char **argv);
int cmd_ifconfig(int argc, char **argv);
int cmd_print(int argc, char **argv);
int cmd_sensors(int argc, char **argv);
int cmd_whoami(int argc, char **argv);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
