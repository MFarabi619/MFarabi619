#ifndef SSH_SERVER_H
#define SSH_SERVER_H

#include "../../config.h"

struct ush_object;

namespace services::sshd {

bool initialize() noexcept;
[[nodiscard]] bool requestExit(struct ush_object *self) noexcept;

#ifdef PIO_UNIT_TESTING
void test() noexcept;
#endif

}

#endif // SSH_SERVER_H
