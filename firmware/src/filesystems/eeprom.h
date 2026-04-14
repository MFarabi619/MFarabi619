#pragma once
#include <at24c32.h>

namespace filesystems::eeprom {

extern AT24C32 IC;

bool initialize();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}

