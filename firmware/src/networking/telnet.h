#pragma once
#include <config.h>

namespace networking::telnet {

void initialize();
void service();
bool isConnected();
const char *clientIP();
void disconnect();

#ifdef PIO_UNIT_TESTING
void test();
#endif

} // namespace networking::telnet

