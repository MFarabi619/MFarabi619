#ifndef ESP_HOSTED_H
#define ESP_HOSTED_H

#include <zephyr/kernel.h>

enum esp_hosted_if_type {
	ESP_INVALID_IF,
	ESP_STA_IF,
	ESP_AP_IF,
	ESP_SERIAL_IF,
	ESP_HCI_IF,
	ESP_PRIV_IF,
	ESP_TEST_IF,
	ESP_ETH_IF,
};

int esp_hosted_transport_init(void);

int esp_hosted_tx(uint8_t if_type, uint8_t if_num, const uint8_t *payload, uint16_t len);

/*
 * Poll for one packet from the slave. Returns 1 with if_type, payload and len
 * set (payload points into an internal buffer, valid until the next call), 0
 * if nothing is pending, negative on error. Priv-interface init events are
 * consumed internally and reported as 0.
 */
int esp_hosted_rx(uint8_t *if_type, uint8_t **payload, uint16_t *len);

#endif /* ESP_HOSTED_H */
