#include "coreutils.h"
#include <i2c.h>
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int programs::coreutils::cmd_i2cdetect(int argc, char **argv) {
  int bus = -1;
  int mux_channel = -2;
  bool is_listing_mode = false;

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-l") == 0) {
      is_listing_mode = true;
    } else if (strcmp(argv[i], "-m") == 0 && i + 1 < argc) {
      mux_channel = atoi(argv[++i]);
      if (mux_channel < 0 || mux_channel > 7) {
        printf("i2cdetect: mux channel must be 0-7\n");
        return 1;
      }
    } else if (bus == -1) {
      bus = atoi(argv[i]);
      if (bus < 0 || bus > 1) {
        printf("i2cdetect: bus must be 0 or 1\n");
        return 1;
      }
    } else {
      printf("usage: i2cdetect [-l] [-m <channel>] [bus]\n");
      return 1;
    }
  }

  hardware::i2c::DiscoveredDevice devices[hardware::i2c::MAX_DISCOVERED_DEVICES];
  size_t count = hardware::i2c::discoverAll(devices, hardware::i2c::MAX_DISCOVERED_DEVICES);

  // ── Listing mode ──
  if (is_listing_mode) {
    printf("\n  %-4s  %-6s  %-4s  %s\n", "BUS", "ADDR", "MUX", "DEVICE");
    for (size_t i = 0; i < count; i++) {
      if (bus >= 0 && devices[i].bus != bus) continue;
      if (mux_channel >= 0 && devices[i].mux_channel != mux_channel) continue;
      if (mux_channel == -2 && false) continue;
      const char *mux_str = devices[i].mux_channel >= 0 ? "yes" : "-";
      printf("  %-4d  0x%02X    %-4s  %s\n",
             devices[i].bus, devices[i].address, mux_str,
             hardware::i2c::deviceNameAt(devices[i].address, devices[i].mux_channel));
    }
    printf("\n");
    return 0;
  }

  // ── Grid mode (default) ──
  // Build a presence map for the selected bus/channel
  bool is_present[128] = {};
  for (size_t i = 0; i < count; i++) {
    if (bus >= 0 && devices[i].bus != bus) continue;
    if (mux_channel >= 0 && devices[i].mux_channel != mux_channel) continue;
    if (mux_channel < 0 && devices[i].mux_channel >= 0) continue;
    is_present[devices[i].address] = true;
  }

  printf("\n");

  // Header
  printf("     ");
  for (int col = 0; col < 16; col++)
    printf("%2x ", col);
  printf("\n");

  // Rows 0x00 - 0x70
  for (int row = 0; row < 8; row++) {
    printf("%02x: ", row << 4);
    for (int col = 0; col < 16; col++) {
      uint8_t addr = (row << 4) | col;
      if (addr < config::i2c::ADDR_MIN || addr > config::i2c::ADDR_MAX)
        printf("   ");
      else if (is_present[addr])
        printf("\x1b[32m%02x\x1b[0m ", addr);
      else
        printf("-- ");
    }
    printf("\n");
  }

  printf("\n");
  return 0;
}
