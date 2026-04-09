#ifndef TESTING_IT_H
#define TESTING_IT_H

#ifdef PIO_UNIT_TESTING

#include <unity.h>
#include <string.h>

// Spaces → underscores so PlatformIO's test regex can parse the name
static char _it_buf[256];
static inline void _it_run(void (*func)(void), const char *desc, int line) {
  strncpy(_it_buf, desc, sizeof(_it_buf) - 1);
  _it_buf[sizeof(_it_buf) - 1] = '\0';
  for (char *p = _it_buf; *p; p++) {
    if (*p == ' ') *p = '_';
  }
  UnityDefaultTestRun(func, _it_buf, line);
}

#define it(description, test_func) \
  _it_run(test_func, description, __LINE__)

#endif // PIO_UNIT_TESTING
#endif // TESTING_IT_H
