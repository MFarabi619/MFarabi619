#include "ssh_server.h"

#include <Arduino.h>
#include <LittleFS.h>
#include <microshell.h>
#include <string.h>

#include "libssh_esp32.h"
#include <libssh/libssh.h>

static size_t fingerprint_get_data(struct ush_object *self,
                                   struct ush_file_descriptor const *file,
                                   uint8_t **data) {
  (void)self; (void)file;
  static char buf[128];
  buf[0] = '\0';

  String vfs_path = String(LittleFS.mountpoint()) + CONFIG_SSH_HOSTKEY_PATH;
  ssh_key key = NULL;
  int rc = ssh_pki_import_privkey_file(vfs_path.c_str(), NULL, NULL, NULL, &key);
  if (rc != SSH_OK) {
    snprintf(buf, sizeof(buf), "(no host key)\r\n");
    *data = (uint8_t *)buf;
    return strlen(buf);
  }

  unsigned char *hash = NULL;
  size_t hlen = 0;
  rc = ssh_get_publickey_hash(key, SSH_PUBLICKEY_HASH_SHA256, &hash, &hlen);
  ssh_key_free(key);

  if (rc != SSH_OK || hash == NULL) {
    snprintf(buf, sizeof(buf), "(hash failed)\r\n");
    *data = (uint8_t *)buf;
    return strlen(buf);
  }

  char *hex = ssh_get_fingerprint_hash(SSH_PUBLICKEY_HASH_SHA256, hash, hlen);
  ssh_clean_pubkey_hash(&hash);

  if (hex) {
    snprintf(buf, sizeof(buf), "%s\r\n", hex);
    ssh_string_free_char(hex);
  } else {
    snprintf(buf, sizeof(buf), "(format failed)\r\n");
  }

  *data = (uint8_t *)buf;
  return strlen(buf);
}

static const struct ush_file_descriptor ssh_dev_files[] = {
  { .name = "fingerprint", .description = "host key SHA256 fingerprint",
    .get_data = fingerprint_get_data },
};

static struct ush_node_object ssh_dev_node;

void dev_ssh_mount(struct ush_object *ush) {
  ush_node_mount(ush, "/dev/ssh", &ssh_dev_node, ssh_dev_files,
                 sizeof(ssh_dev_files) / sizeof(ssh_dev_files[0]));
}
