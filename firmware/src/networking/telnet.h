#ifndef NETWORKING_TELNET_H
#define NETWORKING_TELNET_H

#include "../config.h"

namespace networking::telnet {

void initialize();
void service();
bool isConnected();
const char *clientIP();
void disconnect();

} // namespace networking::telnet

#endif
