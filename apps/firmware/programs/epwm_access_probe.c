#include <zephyr/arch/cpu.h>
#include <zephyr/init.h>
#include <zephyr/sys/printk.h>
#include <zephyr/sys/sys_io.h>

struct probe_target {
	const char *name;
	mem_addr_t address;
	bool halfword;
};

static const struct probe_target probe_targets[] = {
	{"CTRL_MMR EPWM_TB_CLKEN", 0x00104130, false},
	{"EPWM0 TBCTL", 0x23000000, true},
	{"EPWM1 TBCTL", 0x23010000, true},
	{"SECPROXY RT thread 18 status", 0x4a612000, false},
	{"SECPROXY RT thread 19 status", 0x4a613000, false},
};

static int epwm_access_probe(void)
{
	printk("epwm-access-probe: start (host MCU_0_R5_0)\n");
	for (size_t i = 0; i < ARRAY_SIZE(probe_targets); i++) {
		const struct probe_target *target = &probe_targets[i];

		printk("epwm-access-probe: reading %s @ 0x%08lx ...\n", target->name,
		       (unsigned long)target->address);
		uint32_t value = target->halfword ? sys_read16(target->address)
						  : sys_read32(target->address);
		printk("epwm-access-probe: %s = 0x%08x\n", target->name, value);
	}
	printk("epwm-access-probe: all reads passed\n");
	return 0;
}

SYS_INIT(epwm_access_probe, APPLICATION, 99);
