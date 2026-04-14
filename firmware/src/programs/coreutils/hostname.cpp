#include "coreutils.h"
#include "../../services/identity.h"

#include <stdio.h>

int programs::coreutils::cmd_hostname(int argc, char **argv) {
  if (argc == 1) {
    printf("%s\n", services::identity::accessHostname());
    return 0;
  }

  if (argc == 2) {
    if (services::identity::configureHostname(argv[1]))
      printf("hostname updated\n");
    else
      printf("failed to update hostname\n");
    return 0;
  }

  printf("usage: hostname [new-name]\n");
  return 1;
}
