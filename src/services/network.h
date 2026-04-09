#ifndef SERVICES_NETWORK_H
#define SERVICES_NETWORK_H

// Start NTP, SSH, and HTTP. Idempotent — safe to call multiple times.
void network_services_start(void);

#endif // SERVICES_NETWORK_H
