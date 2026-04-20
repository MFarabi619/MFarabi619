#pragma once

namespace programs::shell {

void initialize();
void service();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
