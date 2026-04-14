#pragma once
namespace networking::ble {

void initialize(void);
void service(void);
bool isConnected(void);
int clientCount(void);

#ifdef PIO_UNIT_TESTING
void test(void);
#endif

} // namespace networking::ble

