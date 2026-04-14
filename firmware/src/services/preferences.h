#pragma once

#include <Preferences.h>

namespace services::preferences {

inline bool open(const char *ns, bool readonly, Preferences *prefs) {
    return prefs && prefs->begin(ns, readonly);
}

}
