#ifndef FIRMWARE_BDD_H
#define FIRMWARE_BDD_H

#include <zephyr/sys/printk.h>

#define GIVEN(fmt, ...)                                                        \
  printk("  \x1b[1;30;46m[GIVEN]\x1b[0m \x1b[36m" fmt "\x1b[0m\n",             \
         ##__VA_ARGS__)
#define WHEN(fmt, ...)                                                         \
  printk("    \x1b[1;30;103m[WHEN]\x1b[0m \x1b[33m" fmt "\x1b[0m\n",           \
         ##__VA_ARGS__)
#define THEN(fmt, ...)                                                         \
  printk("      \x1b[1;30;105m[THEN]\x1b[0m \x1b[35m" fmt "\x1b[0m\n",         \
         ##__VA_ARGS__)
#define AND(fmt, ...)                                                          \
  printk("      \x1b[1;30;105m[AND]\x1b[0m  \x1b[35m" fmt "\x1b[0m\n",         \
         ##__VA_ARGS__)

#endif
