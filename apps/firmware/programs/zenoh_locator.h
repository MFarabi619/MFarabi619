#ifndef ZENOH_LOCATOR_H_
#define ZENOH_LOCATOR_H_

#include <zenoh-pico.h>

const char *zenoh_locator_get(void);
int zenoh_locator_set(const char *new_locator);
int zenoh_locator_open_session(z_owned_session_t *session);

#endif /* ZENOH_LOCATOR_H_ */
