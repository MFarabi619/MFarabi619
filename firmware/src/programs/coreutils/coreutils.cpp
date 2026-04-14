#include "coreutils.h"

namespace {

const struct ush_file_descriptor files[] = {
  programs::coreutils::date::descriptor,
  programs::coreutils::uptime::descriptor,
  programs::coreutils::print::descriptor,
  programs::coreutils::whoami::descriptor,
  programs::coreutils::free::descriptor,
  programs::coreutils::hostname::descriptor,
  programs::coreutils::ifconfig::descriptor,
  programs::coreutils::sensors::descriptor,
};

}

const struct ush_file_descriptor *programs::coreutils::descriptors(size_t *count) {
  if (count) *count = sizeof(files) / sizeof(files[0]);
  return files;
}
