#include "ssh_server.h"

#include <Arduino.h>
#include <Console.h>
#include <LittleFS.h>
#include <string.h>
#include <stdio.h>

#include "libssh_esp32.h"
#include <libssh/libssh.h>

static int cmd_fingerprint(int argc, char **argv) {
  (void)argc; (void)argv;

  String vfs_path = String(LittleFS.mountpoint()) + config::ssh::HOSTKEY_PATH;
  ssh_key key = nullptr;
  int rc = ssh_pki_import_privkey_file(vfs_path.c_str(), NULL, NULL, NULL, &key);
  if (rc != SSH_OK) {
    printf("(no host key)\n");
    return 1;
  }

  unsigned char *hash = nullptr;
  size_t hlen = 0;
  rc = ssh_get_publickey_hash(key, SSH_PUBLICKEY_HASH_SHA256, &hash, &hlen);
  ssh_key_free(key);

  if (rc != SSH_OK || hash == nullptr) {
    printf("(hash failed)\n");
    return 1;
  }

  char *hex = ssh_get_fingerprint_hash(SSH_PUBLICKEY_HASH_SHA256, hash, hlen);
  ssh_clean_pubkey_hash(&hash);

  if (hex) {
    printf("%s\n", hex);
    ssh_string_free_char(hex);
  } else {
    printf("(format failed)\n");
    return 1;
  }

  return 0;
}

void programs::ssh_fingerprint::registerCmd() {
  Console.addCmd("fingerprint", "show SSH host key fingerprint", cmd_fingerprint);
}
