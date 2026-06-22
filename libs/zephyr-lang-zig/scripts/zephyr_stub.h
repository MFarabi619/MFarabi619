/*
 * Pre-translation stub: defines typedefs that picolibc's <sys/_types.h>
 * references but doesn't fully provide under translate-c. Without these,
 * translate-c errors on undefined wint_t / incomplete _mbstate_t.
 */

/* Aro's xtensa target doesn't set __IEEE_LITTLE_ENDIAN; picolibc's machine/ieeefp.h #errors without it. */
#ifndef __IEEE_LITTLE_ENDIAN
#define __IEEE_LITTLE_ENDIAN 1
#endif
typedef unsigned int wint_t;
typedef int wctype_t;
typedef unsigned int wctrans_t;
#define __machine_mbstate_t_defined
typedef struct {
	int __count;
	union {
		unsigned int __wch;
		unsigned char __wchb[4];
	} __value;
} _mbstate_t;

#include <autoconf.h>
#include <zephyr/toolchain/zephyr_stdint.h>
#include <stdint.h>

/* Skip irq_multilevel.h: its `_z_irq_t` bitfield union breaks translate-c's
 * BUILD_ASSERT(sizeof(_z_irq_t)==sizeof(uint32_t)). */
#define ZEPHYR_INCLUDE_IRQ_MULTILEVEL_H_
typedef uint32_t _z_irq_t;

#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/sys/printk.h>
