#pragma once

namespace power::sleep_after_poll {

void initialize();
void notifyPolled();
void service();

}
