#pragma once
#include <config.h>

namespace networking::tunnel {

void initialize();
void service();
bool isReady();
const char *accessURL();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
