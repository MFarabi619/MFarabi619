#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

#include "c_sum16.h"

#define SAMPLE_COUNT 16
#define CALIBRATION_OFFSET 100u

int main(void) {
	uint32_t samples[SAMPLE_COUNT];
	for (size_t index = 0; index < SAMPLE_COUNT; index++) {
		samples[index] = CALIBRATION_OFFSET + (uint32_t)index;
	}
	uint16_t sum = c_sum16(samples, SAMPLE_COUNT);
	printf("c: sum16=0x%04x\n", sum);
	return 0;
}
