#ifndef NETWORKING_BLE_H
#define NETWORKING_BLE_H

namespace networking::ble {

void initialize(void);
void service(void);
[[nodiscard]] bool isConnected(void);
[[nodiscard]] int clientCount(void);

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

} // namespace networking::ble

#endif
