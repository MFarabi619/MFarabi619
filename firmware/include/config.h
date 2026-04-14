// clang-format off
#pragma once

#include "config/features.h"
#include "config/board.h"
#include "config/app.h"

// ─────────────────────────────────────────────────────────────────────────────
//  Compile-time config validation
// ─────────────────────────────────────────────────────────────────────────────

static_assert(config::led::GPIO < 48, "Invalid LED GPIO");
static_assert(config::ssh::PORT > 0, "Invalid SSH port");
static_assert(config::http::PORT > 0, "Invalid HTTP port");
static_assert(config::telnet::PORT > 0, "Invalid telnet port");
static_assert(config::i2c::BUS_0.sda_gpio != config::i2c::BUS_0.scl_gpio,
              "I2C bus 0: SDA and SCL must differ");
static_assert(config::i2c::BUS_1.sda_gpio != config::i2c::BUS_1.scl_gpio,
              "I2C bus 1: SDA and SCL must differ");
static_assert(config::wifi::SSID_MAX_LEN == 32, "IEEE 802.11 SSID max is 32");
static_assert(config::wifi::PASS_MAX_LEN == 64, "IEEE 802.11 pass max is 64");
static_assert(config::shell::BUF_IN >= 64, "Shell input buffer too small");
static_assert(config::shell::BUF_OUT >= 64, "Shell output buffer too small");
static_assert(config::buttons::COUNT <= 8, "Too many buttons");
static_assert(config::sleep::DEFAULT_DURATION_SECONDS > 0,
              "Default sleep duration must be greater than 0");

