// SSH client commands: ssh-exec, scp-get, scp-put, ota
// Based on exec.cpp, libssh_scp.ino, and FirmwareOTAClientSCP.ino examples

#include "ssh_client.h"
#include "ssh_server.h"

#include <Arduino.h>
#include <microshell.h>
#include <string.h>

#include "libssh_esp32.h"
#include <libssh/libssh.h>

#include "esp_ota_ops.h"

//------------------------------------------
//  Helpers
//------------------------------------------
#define SCP_BUF_SIZE 4096

// Connect to a remote SSH server with password auth.
// Caller must ssh_disconnect + ssh_free when done.
static ssh_session ssh_client_connect(const char *host, const char *user,
                                      const char *password) {
  ssh_session session = ssh_new();
  if (!session) return NULL;

  ssh_options_set(session, SSH_OPTIONS_HOST, host);
  ssh_options_set(session, SSH_OPTIONS_USER, user);
  int verbosity = SSH_LOG_NOLOG;
  ssh_options_set(session, SSH_OPTIONS_LOG_VERBOSITY, &verbosity);

  if (ssh_connect(session) != SSH_OK) {
    ssh_free(session);
    return NULL;
  }

  int rc = ssh_userauth_password(session, NULL, password);
  if (rc != SSH_AUTH_SUCCESS) {
    ssh_disconnect(session);
    ssh_free(session);
    return NULL;
  }

  return session;
}

//------------------------------------------
//  ssh-exec user@host password command
//------------------------------------------
static void cmd_ssh_exec(struct ush_object *self,
                         struct ush_file_descriptor const *file,
                         int argc, char *argv[]) {
  (void)file;
  // usage: ssh-exec host user password command
  if (argc < 5) {
    ush_print(self, (char *)"usage: ssh-exec <host> <user> <password> <command>\r\n");
    return;
  }

  const char *host = argv[1];
  const char *user = argv[2];
  const char *pass = argv[3];
  const char *cmd  = argv[4];

  ush_print(self, (char *)"connecting...\r\n");
  ssh_session session = ssh_client_connect(host, user, pass);
  if (!session) {
    ush_print(self, (char *)"connection failed\r\n");
    return;
  }

  ssh_channel channel = ssh_channel_new(session);
  if (!channel || ssh_channel_open_session(channel) != SSH_OK) {
    ush_print(self, (char *)"channel open failed\r\n");
    if (channel) ssh_channel_free(channel);
    ssh_disconnect(session);
    ssh_free(session);
    return;
  }

  if (ssh_channel_request_exec(channel, cmd) != SSH_OK) {
    ush_print(self, (char *)"exec failed\r\n");
    ssh_channel_close(channel);
    ssh_channel_free(channel);
    ssh_disconnect(session);
    ssh_free(session);
    return;
  }

  // Read stdout
  char buf[256];
  int nbytes;
  while ((nbytes = ssh_channel_read(channel, buf, sizeof(buf) - 1, 0)) > 0) {
    buf[nbytes] = '\0';
    ush_print(self, buf);
  }

  ssh_channel_send_eof(channel);
  ssh_channel_close(channel);
  ssh_channel_free(channel);
  ssh_disconnect(session);
  ssh_free(session);
}

//------------------------------------------
//  scp-get host user password remote local
//------------------------------------------
static void cmd_scp_get(struct ush_object *self,
                        struct ush_file_descriptor const *file,
                        int argc, char *argv[]) {
  (void)file;
  if (argc < 6) {
    ush_print(self, (char *)"usage: scp-get <host> <user> <password> <remote-path> <local-path>\r\n");
    return;
  }

  const char *host   = argv[1];
  const char *user   = argv[2];
  const char *pass   = argv[3];
  const char *remote = argv[4];
  const char *local  = argv[5];

  ush_print(self, (char *)"connecting...\r\n");
  ssh_session session = ssh_client_connect(host, user, pass);
  if (!session) {
    ush_print(self, (char *)"connection failed\r\n");
    return;
  }

  ssh_scp scp = ssh_scp_new(session, SSH_SCP_READ, remote);
  if (!scp || ssh_scp_init(scp) != SSH_OK) {
    ush_print(self, (char *)"scp init failed\r\n");
    if (scp) ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return;
  }

  int r = ssh_scp_pull_request(scp);
  if (r != SSH_SCP_REQUEST_NEWFILE) {
    ush_print(self, (char *)"scp pull request failed\r\n");
    ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return;
  }

  size_t file_size = ssh_scp_request_get_size(scp);
  ssh_scp_accept_request(scp);

  // Write to local filesystem
  FILE *fp = fopen(local, "wb");
  if (!fp) {
    ush_print(self, (char *)"cannot open local file\r\n");
    ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return;
  }

  char buf[SCP_BUF_SIZE];
  size_t total = 0;
  while (total < file_size) {
    r = ssh_scp_read(scp, buf, sizeof(buf));
    if (r == SSH_ERROR || r == 0) break;
    fwrite(buf, 1, r, fp);
    total += r;
  }
  fclose(fp);

  char msg[64];
  snprintf(msg, sizeof(msg), "downloaded %u bytes\r\n", (unsigned)total);
  ush_print(self, msg);

  ssh_scp_free(scp);
  ssh_disconnect(session);
  ssh_free(session);
}

//------------------------------------------
//  scp-put host user password local remote
//------------------------------------------
static void cmd_scp_put(struct ush_object *self,
                        struct ush_file_descriptor const *file,
                        int argc, char *argv[]) {
  (void)file;
  if (argc < 6) {
    ush_print(self, (char *)"usage: scp-put <host> <user> <password> <local-path> <remote-path>\r\n");
    return;
  }

  const char *host   = argv[1];
  const char *user   = argv[2];
  const char *pass   = argv[3];
  const char *local  = argv[4];
  const char *remote = argv[5];

  // Get local file size
  FILE *fp = fopen(local, "rb");
  if (!fp) {
    ush_print(self, (char *)"cannot open local file\r\n");
    return;
  }
  fseek(fp, 0, SEEK_END);
  size_t file_size = ftell(fp);
  fseek(fp, 0, SEEK_SET);

  ush_print(self, (char *)"connecting...\r\n");
  ssh_session session = ssh_client_connect(host, user, pass);
  if (!session) {
    fclose(fp);
    ush_print(self, (char *)"connection failed\r\n");
    return;
  }

  ssh_scp scp = ssh_scp_new(session, SSH_SCP_WRITE, remote);
  if (!scp || ssh_scp_init(scp) != SSH_OK) {
    fclose(fp);
    ush_print(self, (char *)"scp init failed\r\n");
    if (scp) ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return;
  }

  // Extract filename from remote path for scp_push_file
  const char *filename = strrchr(remote, '/');
  filename = filename ? filename + 1 : remote;

  if (ssh_scp_push_file(scp, filename, file_size, 0644) != SSH_OK) {
    fclose(fp);
    ush_print(self, (char *)"scp push failed\r\n");
    ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return;
  }

  char buf[SCP_BUF_SIZE];
  size_t total = 0;
  size_t n;
  while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
    if (ssh_scp_write(scp, buf, n) != SSH_OK) break;
    total += n;
  }
  fclose(fp);

  char msg[64];
  snprintf(msg, sizeof(msg), "uploaded %u bytes\r\n", (unsigned)total);
  ush_print(self, msg);

  ssh_scp_close(scp);
  ssh_scp_free(scp);
  ssh_disconnect(session);
  ssh_free(session);
}

//------------------------------------------
//  ota host user password remote-path
//  Pull firmware via SCP, flash to OTA partition, reboot
//------------------------------------------
static void cmd_ota(struct ush_object *self,
                    struct ush_file_descriptor const *file,
                    int argc, char *argv[]) {
  (void)file;
  if (argc < 5) {
    ush_print(self, (char *)"usage: ota <host> <user> <password> <remote-firmware-path>\r\n");
    return;
  }

  const char *host   = argv[1];
  const char *user   = argv[2];
  const char *pass   = argv[3];
  const char *remote = argv[4];

  // Partition info
  const esp_partition_t *running = esp_ota_get_running_partition();
  const esp_partition_t *target  = esp_ota_get_next_update_partition(NULL);
  if (!target) {
    ush_print(self, (char *)"no OTA partition available\r\n");
    return;
  }

  char msg[128];
  snprintf(msg, sizeof(msg), "running: %s, target: %s\r\n",
           running->label, target->label);
  ush_print(self, msg);

  ush_print(self, (char *)"connecting...\r\n");
  ssh_session session = ssh_client_connect(host, user, pass);
  if (!session) {
    ush_print(self, (char *)"connection failed\r\n");
    return;
  }

  ssh_scp scp = ssh_scp_new(session, SSH_SCP_READ, remote);
  if (!scp || ssh_scp_init(scp) != SSH_OK) {
    ush_print(self, (char *)"scp init failed\r\n");
    if (scp) ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return;
  }

  int r = ssh_scp_pull_request(scp);
  if (r != SSH_SCP_REQUEST_NEWFILE) {
    ush_print(self, (char *)"scp pull request failed\r\n");
    ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return;
  }

  size_t image_size = ssh_scp_request_get_size(scp);
  ssh_scp_accept_request(scp);

  snprintf(msg, sizeof(msg), "image size: %u bytes\r\n", (unsigned)image_size);
  ush_print(self, msg);

  // Begin OTA
  esp_ota_handle_t ota_handle = 0;
  esp_err_t err = esp_ota_begin(target, OTA_SIZE_UNKNOWN, &ota_handle);
  if (err != ESP_OK) {
    snprintf(msg, sizeof(msg), "ota begin failed: 0x%x\r\n", err);
    ush_print(self, msg);
    ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return;
  }

  // Read + write loop
  char buf[SCP_BUF_SIZE];
  size_t total = 0;
  bool failed = false;

  while (total < image_size) {
    r = ssh_scp_read(scp, buf, sizeof(buf));
    if (r == SSH_ERROR || r == 0) {
      ush_print(self, (char *)"scp read error\r\n");
      failed = true;
      break;
    }

    err = esp_ota_write(ota_handle, buf, r);
    if (err != ESP_OK) {
      snprintf(msg, sizeof(msg), "ota write failed: 0x%x\r\n", err);
      ush_print(self, msg);
      failed = true;
      break;
    }

    total += r;
    int pct = (int)(100 * total / image_size);
    snprintf(msg, sizeof(msg), "\r[%d%%] %u / %u bytes", pct, (unsigned)total, (unsigned)image_size);
    ush_print(self, msg);
  }

  ush_print(self, (char *)"\r\n");

  ssh_scp_free(scp);
  ssh_disconnect(session);
  ssh_free(session);

  if (failed) {
    esp_ota_abort(ota_handle);
    ush_print(self, (char *)"ota aborted\r\n");
    return;
  }

  // Finalize
  err = esp_ota_end(ota_handle);
  if (err != ESP_OK) {
    snprintf(msg, sizeof(msg), "ota end failed: 0x%x\r\n", err);
    ush_print(self, msg);
    return;
  }

  err = esp_ota_set_boot_partition(target);
  if (err != ESP_OK) {
    snprintf(msg, sizeof(msg), "set boot partition failed: 0x%x\r\n", err);
    ush_print(self, msg);
    return;
  }

  ush_print(self, (char *)"OTA complete. Rebooting in 3s...\r\n");
  delay(3000);
  esp_restart();
}

//------------------------------------------
//  Register all SSH client commands
//------------------------------------------
static const struct ush_file_descriptor ssh_client_cmd_files[] = {
  { .name = "ssh-exec",  .description = "execute command on remote host",
    .help = "usage: ssh-exec <host> <user> <password> <command>\r\n",
    .exec = cmd_ssh_exec },
  { .name = "scp-get",   .description = "download file from remote host",
    .help = "usage: scp-get <host> <user> <password> <remote-path> <local-path>\r\n",
    .exec = cmd_scp_get },
  { .name = "scp-put",   .description = "upload file to remote host",
    .help = "usage: scp-put <host> <user> <password> <local-path> <remote-path>\r\n",
    .exec = cmd_scp_put },
  { .name = "ota",       .description = "OTA firmware update via SCP",
    .help = "usage: ota <host> <user> <password> <remote-firmware-path>\r\n",
    .exec = cmd_ota },
};

static struct ush_node_object ssh_client_cmd_node;

void ssh_client_commands_register(struct ush_object *ush) {
  ush_commands_add(ush, &ssh_client_cmd_node, ssh_client_cmd_files,
                   sizeof(ssh_client_cmd_files) / sizeof(ssh_client_cmd_files[0]));
}
