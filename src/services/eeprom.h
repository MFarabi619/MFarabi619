#ifndef SERVICES_EEPROM_H
#define SERVICES_EEPROM_H

#include "../config.h"
#include <at24c32.h>

bool eeprom_init(void);
uint8_t eeprom_last_error(void);
uint16_t eeprom_size(void);

// The AT24C32 instance — exposed so callers can use put<T>/get<T> directly
extern AT24C32 eeprom;

#ifdef PIO_UNIT_TESTING
void eeprom_run_tests(void);
#endif

#endif // SERVICES_EEPROM_H
