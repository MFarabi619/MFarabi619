#include "coreutils.h"

#include <SD.h>
#include <LittleFS.h>
#include <stdio.h>

int programs::coreutils::cmd_df(int argc, char **argv) {
  (void)argc; (void)argv;

  printf("\n");
  printf("  \x1b[33m%-16s\x1b[0m %-12s %-12s %-12s\n",
         "Filesystem", "Size", "Used", "Avail");

  if (SD.cardType() != CARD_NONE) {
    uint64_t total = SD.totalBytes();
    uint64_t used = SD.usedBytes();
    uint64_t avail = total - used;

    char size_str[16], used_str[16], avail_str[16];
    if (total >= 1024ULL * 1024 * 1024)
      snprintf(size_str, sizeof(size_str), "%.1f GiB", total / (1024.0 * 1024 * 1024));
    else
      snprintf(size_str, sizeof(size_str), "%llu MiB", total / (1024 * 1024));

    snprintf(used_str, sizeof(used_str), "%llu MiB", used / (1024 * 1024));
    snprintf(avail_str, sizeof(avail_str), "%llu MiB", avail / (1024 * 1024));

    printf("  \x1b[33m%-16s\x1b[0m %-12s %-12s %-12s\n",
           "SD (FAT32)", size_str, used_str, avail_str);
  }

  if (LittleFS.totalBytes() > 0) {
    uint32_t total = LittleFS.totalBytes();
    uint32_t used = LittleFS.usedBytes();
    uint32_t avail = total - used;

    char size_str[16], used_str[16], avail_str[16];
    snprintf(size_str, sizeof(size_str), "%lu KiB", (unsigned long)(total / 1024));
    snprintf(used_str, sizeof(used_str), "%lu KiB", (unsigned long)(used / 1024));
    snprintf(avail_str, sizeof(avail_str), "%lu KiB", (unsigned long)(avail / 1024));

    printf("  \x1b[33m%-16s\x1b[0m %-12s %-12s %-12s\n",
           "LittleFS", size_str, used_str, avail_str);
  }

  printf("\n");
  return 0;
}
