#ifndef ZENOH_LOCATOR_H_
#define ZENOH_LOCATOR_H_

const char *zenoh_locator_get(void);
int zenoh_locator_set(const char *new_locator);

#endif /* ZENOH_LOCATOR_H_ */
