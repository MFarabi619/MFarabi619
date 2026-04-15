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
int cmd_ls(int argc, char **argv);
int cmd_cat(int argc, char **argv);
int cmd_mkdir(int argc, char **argv);
int cmd_rm(int argc, char **argv);
int cmd_touch(int argc, char **argv);
int cmd_cp(int argc, char **argv);
int cmd_mv(int argc, char **argv);
int cmd_df(int argc, char **argv);

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
