/* macOS lacks clock_nanosleep. lg only calls it as a relative CLOCK_REALTIME
 * sleep, which nanosleep implements exactly. Force-included on Apple hosts so
 * librgpio builds on macOS; on Linux this is inert. */
#ifdef __APPLE__
#include <time.h>
#define clock_nanosleep(clock_id, flags, request, remaining) \
    nanosleep((request), (remaining))
#endif
