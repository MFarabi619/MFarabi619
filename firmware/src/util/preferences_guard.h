#ifndef UTIL_PREFERENCES_GUARD_H
#define UTIL_PREFERENCES_GUARD_H

#include <Preferences.h>

class PreferencesGuard {
    Preferences prefs_;
    bool opened_ = false;

public:
    PreferencesGuard(const char *ns, bool readonly = false) {
        opened_ = prefs_.begin(ns, readonly);
    }

    ~PreferencesGuard() {
        if (opened_) prefs_.end();
    }

    PreferencesGuard(const PreferencesGuard &) = delete;
    PreferencesGuard &operator=(const PreferencesGuard &) = delete;

    Preferences *operator->() { return &prefs_; }
    const Preferences *operator->() const { return &prefs_; }
    Preferences &ref() { return prefs_; }
    bool ok() const { return opened_; }
};

#endif
