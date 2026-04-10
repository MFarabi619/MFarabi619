#ifndef NETWORKING_BLE_H
#define NETWORKING_BLE_H

void ble_init(void);
void ble_service(void);
bool ble_is_connected(void);
int ble_client_count(void);

#ifdef PIO_UNIT_TESTING
void ble_run_tests(void);
#endif

#endif
