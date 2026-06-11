#include <errno.h>
#include <stdint.h>
#include <time.h>

#include <zephyr/net/sntp.h>
#include <zephyr/sys/clock.h>

int sntp_sync(const char *server, uint32_t timeout_ms)
{
	struct sntp_time ts;
	int rc = sntp_simple(server, timeout_ms, &ts);

	if (rc < 0) {
		return rc;
	}

	struct timespec tp = {
		.tv_sec = (time_t)ts.seconds,
		.tv_nsec = (long)(((uint64_t)ts.fraction * 1000000000ULL) >> 32),
	};

	return sys_clock_settime(SYS_CLOCK_REALTIME, &tp);
}
