#include <zephyr/kernel.h>

K_MUTEX_DEFINE(test_mutex);
K_SEM_DEFINE(test_sem, 0, 5);

static struct k_mutex runtime_mutex;
static struct k_sem runtime_sem;

void *get_test_mutex(void)
{
	return &test_mutex;
}

void *get_test_sem(void)
{
	return &test_sem;
}

void *get_runtime_mutex(void)
{
	return &runtime_mutex;
}

void *get_runtime_sem(void)
{
	return &runtime_sem;
}
