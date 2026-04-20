#pragma once

namespace programs::shell::microfetch {

void registerCmd();
const char *generate(const char *transport = "Serial");

}
