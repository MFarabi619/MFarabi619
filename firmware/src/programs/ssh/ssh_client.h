#pragma once

namespace programs::ssh_client {

void registerCommands();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
