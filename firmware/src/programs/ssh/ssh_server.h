#pragma once

#include "../../config.h"

namespace programs::ssh_fingerprint {
void registerCmd();
}

namespace services::sshd {

bool initialize();
bool requestExit();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
