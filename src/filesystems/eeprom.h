#ifndef FILESYSTEMS_EEPROM_H
#define FILESYSTEMS_EEPROM_H

#include <at24c32.h>

namespace filesystems::eeprom {

extern AT24C32 IC;

bool initialize() noexcept;

#ifdef PIO_UNIT_TESTING
void test() noexcept;
#endif

}

#endif
