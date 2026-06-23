#include "c_sum16.h"

uint16_t c_sum16(const uint32_t *samples, size_t len) {
	uint16_t sum = 0;
	for (size_t index = 0; index < len; index++) {
		sum += (uint16_t)(samples[index] & 0xFFFFu);
		sum += (uint16_t)(samples[index] >> 16);
	}
	return sum;
}
