#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#include "ssh_client.h"
#include "ssh_server.h"

#include <Arduino.h>
#include <Console.h>
#include <string.h>
#include <stdio.h>

#include "libssh_esp32.h"
#include <libssh/libssh.h>

#include "esp_ota_ops.h"

static ssh_session ssh_client_connect(const char *host, const char *user,
                                      const char *password) {
  ssh_session session = ssh_new();
  if (!session) return nullptr;

  ssh_options_set(session, SSH_OPTIONS_HOST, host);
  ssh_options_set(session, SSH_OPTIONS_USER, user);
  int verbosity = SSH_LOG_NOLOG;
  ssh_options_set(session, SSH_OPTIONS_LOG_VERBOSITY, &verbosity);

  if (ssh_connect(session) != SSH_OK) {
    ssh_free(session);
    return nullptr;
  }

  int rc = ssh_userauth_password(session, NULL, password);
  if (rc != SSH_AUTH_SUCCESS) {
    ssh_disconnect(session);
    ssh_free(session);
    return nullptr;
  }

  return session;
}

static int cmd_ssh_exec(int argc, char **argv) {
  if (argc < 5) {
    printf("usage: ssh-exec <host> <user> <password> <command>\n");
    return 1;
  }

  const char *host = argv[1];
  const char *user = argv[2];
  const char *pass = argv[3];

  static char cmd_buf[256];
  int pos = 0;
  for (int i = 4; i < argc && pos < (int)sizeof(cmd_buf) - 1; i++) {
    if (i > 4) cmd_buf[pos++] = ' ';
    int n = snprintf(cmd_buf + pos, sizeof(cmd_buf) - pos, "%s", argv[i]);
    pos += n;
  }
  cmd_buf[pos] = '\0';

  printf("connecting...\n");
  ssh_session session = ssh_client_connect(host, user, pass);
  if (!session) { printf("connection failed\n"); return 1; }

  ssh_channel channel = ssh_channel_new(session);
  if (!channel || ssh_channel_open_session(channel) != SSH_OK) {
    printf("channel open failed\n");
    if (channel) ssh_channel_free(channel);
    ssh_disconnect(session);
    ssh_free(session);
    return 1;
  }

  if (ssh_channel_request_exec(channel, cmd_buf) != SSH_OK) {
    printf("exec failed\n");
    ssh_channel_close(channel);
    ssh_channel_free(channel);
    ssh_disconnect(session);
    ssh_free(session);
    return 1;
  }

  char buf[256];
  int nbytes;
  while ((nbytes = ssh_channel_read(channel, buf, sizeof(buf) - 1, 0)) > 0) {
    buf[nbytes] = '\0';
    printf("%s", buf);
  }

  ssh_channel_send_eof(channel);
  ssh_channel_close(channel);
  ssh_channel_free(channel);
  ssh_disconnect(session);
  ssh_free(session);
  return 0;
}

static int cmd_scp_get(int argc, char **argv) {
  if (argc < 6) {
    printf("usage: scp-get <host> <user> <password> <remote-path> <local-path>\n");
    return 1;
  }

  const char *host   = argv[1];
  const char *user   = argv[2];
  const char *pass   = argv[3];
  const char *remote = argv[4];
  const char *local  = argv[5];

  printf("connecting...\n");
  ssh_session session = ssh_client_connect(host, user, pass);
  if (!session) { printf("connection failed\n"); return 1; }

  ssh_scp scp = ssh_scp_new(session, SSH_SCP_READ, remote);
  if (!scp || ssh_scp_init(scp) != SSH_OK) {
    printf("scp init failed\n");
    if (scp) ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return 1;
  }

  int r = ssh_scp_pull_request(scp);
  if (r != SSH_SCP_REQUEST_NEWFILE) {
    printf("scp pull request failed\n");
    ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return 1;
  }

  size_t file_size = ssh_scp_request_get_size(scp);
  ssh_scp_accept_request(scp);

  FILE *fp = fopen(local, "wb");
  if (!fp) {
    printf("cannot open local file\n");
    ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return 1;
  }

  char buf[config::scp::BUF_SIZE];
  size_t total = 0;
  bool is_failed = false;
  while (total < file_size) {
    r = ssh_scp_read(scp, buf, sizeof(buf));
    if (r == SSH_ERROR || r == 0) { is_failed = true; break; }
    fwrite(buf, 1, r, fp);
    total += r;
  }
  fclose(fp);

  if (is_failed || total < file_size)
    printf("transfer incomplete: %u/%u bytes\n", (unsigned)total, (unsigned)file_size);
  else
    printf("downloaded %u bytes\n", (unsigned)total);

  ssh_scp_free(scp);
  ssh_disconnect(session);
  ssh_free(session);
  return is_failed ? 1 : 0;
}

static int cmd_scp_put(int argc, char **argv) {
  if (argc < 6) {
    printf("usage: scp-put <host> <user> <password> <local-path> <remote-path>\n");
    return 1;
  }

  const char *host   = argv[1];
  const char *user   = argv[2];
  const char *pass   = argv[3];
  const char *local  = argv[4];
  const char *remote = argv[5];

  FILE *fp = fopen(local, "rb");
  if (!fp) { printf("cannot open local file\n"); return 1; }
  fseek(fp, 0, SEEK_END);
  size_t file_size = ftell(fp);
  fseek(fp, 0, SEEK_SET);

  printf("connecting...\n");
  ssh_session session = ssh_client_connect(host, user, pass);
  if (!session) {
    fclose(fp);
    printf("connection failed\n");
    return 1;
  }

  ssh_scp scp = ssh_scp_new(session, SSH_SCP_WRITE, remote);
  if (!scp || ssh_scp_init(scp) != SSH_OK) {
    fclose(fp);
    printf("scp init failed\n");
    if (scp) ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return 1;
  }

  const char *filename = strrchr(remote, '/');
  filename = filename ? filename + 1 : remote;

  if (ssh_scp_push_file(scp, filename, file_size, 0644) != SSH_OK) {
    fclose(fp);
    printf("scp push failed\n");
    ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return 1;
  }

  char buf[config::scp::BUF_SIZE];
  size_t total = 0;
  bool is_failed = false;
  size_t n;
  while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
    if (ssh_scp_write(scp, buf, n) != SSH_OK) { is_failed = true; break; }
    total += n;
  }
  fclose(fp);

  if (is_failed || total < file_size)
    printf("transfer incomplete: %u/%u bytes\n", (unsigned)total, (unsigned)file_size);
  else
    printf("uploaded %u bytes\n", (unsigned)total);

  ssh_scp_close(scp);
  ssh_scp_free(scp);
  ssh_disconnect(session);
  ssh_free(session);
  return is_failed ? 1 : 0;
}

static int cmd_ota(int argc, char **argv) {
  if (argc < 5) {
    printf("usage: ota <host> <user> <password> <remote-firmware-path>\n");
    return 1;
  }

  const char *host   = argv[1];
  const char *user   = argv[2];
  const char *pass   = argv[3];
  const char *remote = argv[4];

  const esp_partition_t *running = esp_ota_get_running_partition();
  const esp_partition_t *target  = esp_ota_get_next_update_partition(NULL);
  if (!target) { printf("no OTA partition available\n"); return 1; }

  printf("running: %s, target: %s\n", running->label, target->label);
  printf("connecting...\n");

  ssh_session session = ssh_client_connect(host, user, pass);
  if (!session) { printf("connection failed\n"); return 1; }

  ssh_scp scp = ssh_scp_new(session, SSH_SCP_READ, remote);
  if (!scp || ssh_scp_init(scp) != SSH_OK) {
    printf("scp init failed\n");
    if (scp) ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return 1;
  }

  int r = ssh_scp_pull_request(scp);
  if (r != SSH_SCP_REQUEST_NEWFILE) {
    printf("scp pull request failed\n");
    ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return 1;
  }

  size_t image_size = ssh_scp_request_get_size(scp);
  ssh_scp_accept_request(scp);
  printf("image size: %u bytes\n", (unsigned)image_size);

  esp_ota_handle_t ota_handle = 0;
  esp_err_t err = esp_ota_begin(target, OTA_SIZE_UNKNOWN, &ota_handle);
  if (err != ESP_OK) {
    printf("ota begin failed: 0x%x\n", err);
    ssh_scp_free(scp);
    ssh_disconnect(session);
    ssh_free(session);
    return 1;
  }

  char buf[config::scp::BUF_SIZE];
  size_t total = 0;
  bool is_failed = false;

  while (total < image_size) {
    r = ssh_scp_read(scp, buf, sizeof(buf));
    if (r == SSH_ERROR || r == 0) {
      printf("scp read error\n");
      is_failed = true;
      break;
    }

    err = esp_ota_write(ota_handle, buf, r);
    if (err != ESP_OK) {
      printf("ota write failed: 0x%x\n", err);
      is_failed = true;
      break;
    }

    total += r;
    printf("\r[%d%%] %u / %u bytes", (int)(100 * total / image_size),
           (unsigned)total, (unsigned)image_size);
  }
  printf("\n");

  ssh_scp_free(scp);
  ssh_disconnect(session);
  ssh_free(session);

  if (is_failed) {
    esp_ota_abort(ota_handle);
    printf("ota aborted\n");
    return 1;
  }

  err = esp_ota_end(ota_handle);
  if (err != ESP_OK) { printf("ota end failed: 0x%x\n", err); return 1; }

  err = esp_ota_set_boot_partition(target);
  if (err != ESP_OK) { printf("set boot partition failed: 0x%x\n", err); return 1; }

  printf("OTA complete. Rebooting in 3s...\n");
  delay(3000);
  esp_restart();
  return 0;
}

void programs::ssh_client::registerCommands() {
  Console.addCmd("ssh-exec", "execute command on remote host",
                 "<host> <user> <password> <command>", cmd_ssh_exec);
  Console.addCmd("scp-get", "download file from remote host",
                 "<host> <user> <password> <remote-path> <local-path>", cmd_scp_get);
  Console.addCmd("scp-put", "upload file to remote host",
                 "<host> <user> <password> <local-path> <remote-path>", cmd_scp_put);
  Console.addCmd("ota", "OTA firmware update via SCP",
                 "<host> <user> <password> <remote-firmware-path>", cmd_ota);
}

//------------------------------------------
//  Tests
//------------------------------------------
#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>
#include <WiFi.h>
#include "esp_ota_ops.h"

static void test_ssh_exec_rejects_missing_args(void) {
  WHEN("ssh-exec is run without enough arguments");
  int rc = Console.run("ssh-exec");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc, "device: ssh-exec with no args should fail");
  rc = Console.run("ssh-exec host");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc, "device: ssh-exec with 1 arg should fail");
  rc = Console.run("ssh-exec host user");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc, "device: ssh-exec with 2 args should fail");
  rc = Console.run("ssh-exec host user pass");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc, "device: ssh-exec with 3 args should fail");
}

static void test_scp_get_rejects_missing_args(void) {
  WHEN("scp-get is run without enough arguments");
  int rc = Console.run("scp-get");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc, "device: scp-get with no args should fail");
  rc = Console.run("scp-get host user pass remote");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc, "device: scp-get with 4 args should fail");
}

static void test_scp_put_rejects_missing_args(void) {
  WHEN("scp-put is run without enough arguments");
  int rc = Console.run("scp-put");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc, "device: scp-put with no args should fail");
  rc = Console.run("scp-put host user pass local");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc, "device: scp-put with 4 args should fail");
}

static void test_ota_rejects_missing_args(void) {
  WHEN("ota is run without enough arguments");
  int rc = Console.run("ota");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc, "device: ota with no args should fail");
  rc = Console.run("ota host user");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc, "device: ota with 2 args should fail");
}

static void test_ota_partition_available(void) {
  WHEN("the OTA update partition is queried");
  const esp_partition_t *target = esp_ota_get_next_update_partition(NULL);
  TEST_ASSERT_NOT_NULL_MESSAGE(target,
    "device: no OTA update partition — partition table may lack ota_0/ota_1");
  TEST_PRINTF("OTA target: %s", target->label);
}

static void test_ssh_exec_fails_on_unreachable_host(void) {
  WHEN("ssh-exec targets an unreachable host");
  if (!WiFi.isConnected()) {
    TEST_IGNORE_MESSAGE("skipped — WiFi not connected");
    return;
  }
  int rc = Console.run("ssh-exec 192.0.2.1 user pass echo hi");
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, rc,
    "device: ssh-exec to unreachable host should fail");
}

// TODO: End-to-end tests — require a reachable SSH server.
// Set TEST_SSH_HOST, TEST_SSH_USER, TEST_SSH_PASS environment variables
// and uncomment to enable.
//
// static void ssh_client_test_ssh_exec_runs_remote_command(void) {
//   TEST_MESSAGE("user executes a command on a remote host via ssh-exec");
//   int rc = Console.run("ssh-exec " TEST_SSH_HOST " " TEST_SSH_USER " " TEST_SSH_PASS " echo hello");
//   TEST_ASSERT_EQUAL_INT(0, rc);
// }
//
// static void ssh_client_test_scp_get_downloads_file(void) {
//   TEST_MESSAGE("user downloads a file from a remote host via scp-get");
//   int rc = Console.run("scp-get " TEST_SSH_HOST " " TEST_SSH_USER " " TEST_SSH_PASS " /tmp/test.txt /sd/test_scp.txt");
//   TEST_ASSERT_EQUAL_INT(0, rc);
//   TEST_ASSERT_TRUE(SD.exists("/sd/test_scp.txt"));
//   SD.remove("/sd/test_scp.txt");
// }
//
// static void ssh_client_test_scp_put_uploads_file(void) {
//   TEST_MESSAGE("user uploads a file to a remote host via scp-put");
//   File f = SD.open("/sd/test_upload.txt", FILE_WRITE);
//   f.print("upload test");
//   f.close();
//   int rc = Console.run("scp-put " TEST_SSH_HOST " " TEST_SSH_USER " " TEST_SSH_PASS " /sd/test_upload.txt /tmp/test_upload.txt");
//   TEST_ASSERT_EQUAL_INT(0, rc);
//   SD.remove("/sd/test_upload.txt");
// }
//
// static void ssh_client_test_ota_fails_with_nonexistent_firmware(void) {
//   TEST_MESSAGE("user runs OTA with a nonexistent remote firmware path");
//   int rc = Console.run("ota " TEST_SSH_HOST " " TEST_SSH_USER " " TEST_SSH_PASS " /tmp/nonexistent.bin");
//   TEST_ASSERT_NOT_EQUAL_INT(0, rc);
// }

void programs::ssh_client::test() {
  MODULE("SSH Client");
  RUN_TEST(test_ssh_exec_rejects_missing_args);
  RUN_TEST(test_scp_get_rejects_missing_args);
  RUN_TEST(test_scp_put_rejects_missing_args);
  RUN_TEST(test_ota_rejects_missing_args);
  RUN_TEST(test_ota_partition_available);
  RUN_TEST(test_ssh_exec_fails_on_unreachable_host);
}

#endif

#pragma GCC diagnostic pop
