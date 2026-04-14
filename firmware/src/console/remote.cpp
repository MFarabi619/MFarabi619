#include "remote.h"
#include "prompt.h"
#include "../programs/shell/microfetch.h"

#include <Console.h>
#include <stdio.h>
#include <string.h>

namespace {

struct RedirectCtx {
  console::remote::flush_fn flush;
  void *ctx;
};

int redirect_write(void *cookie, const char *buf, int len) {
  RedirectCtx *r = (RedirectCtx *)cookie;
  const char *start = buf;
  for (int i = 0; i < len; i++) {
    if (buf[i] == '\n') {
      if (i > 0 && &buf[i] > start)
        r->flush(start, &buf[i] - start, r->ctx);
      r->flush("\r\n", 2, r->ctx);
      start = &buf[i + 1];
    }
  }
  if (start < buf + len)
    r->flush(start, (buf + len) - start, r->ctx);
  return len;
}

} // namespace

console::remote::Shell::Shell(char *ring_buf, uint16_t ring_cap,
                              char *write_buf, size_t write_cap,
                              char *line_buf, size_t line_cap,
                              flush_fn flush, void *flush_ctx)
    : line_buf_(line_buf), line_cap_(line_cap), line_pos_(0),
      flush_fn_(flush), flush_ctx_(flush_ctx) {
  ring_.data = ring_buf;
  ring_.capacity = ring_cap;
  ring_.head.store(0);
  ring_.tail.store(0);
  write_.data = write_buf;
  write_.capacity = write_cap;
  write_.position = 0;
}

void console::remote::Shell::reset() {
  programs::shell::session::reset(&ring_);
  programs::shell::session::reset(&write_);
  line_pos_ = 0;
}

void console::remote::Shell::push_input(char ch) {
  echo(ch);
  programs::shell::session::push(&ring_, ch);
}

void console::remote::Shell::push_input(const char *data, size_t len) {
  for (size_t i = 0; i < len; i++)
    push_input(data[i]);
  flush();
}

void console::remote::Shell::write(const char *data, size_t len) {
  for (size_t i = 0; i < len; i++) {
    if (!programs::shell::session::push(&write_, data[i])) {
      flush();
      programs::shell::session::push(&write_, data[i]);
    }
  }
}

void console::remote::Shell::flush() {
  if (write_.position > 0) {
    flush_fn_(write_.data, write_.position, flush_ctx_);
    programs::shell::session::reset(&write_);
  }
}

void console::remote::Shell::echo(char ch) {
  if (ch == '\r' || ch == '\n') {
    write("\r\n", 2);
  } else if (ch == '\x7f' || ch == '\x08') {
    write("\b \b", 3);
  } else if (ch >= 0x20) {
    write(&ch, 1);
  }
}

void console::remote::Shell::send_motd(const char *transport) {
  const char *motd = programs::shell::microfetch::generate(transport);
  write(motd, strlen(motd));
}

void console::remote::Shell::send_prompt() {
  const char *p = console::prompt::build("/");
  write(p, strlen(p));
  flush();
}

void console::remote::Shell::service() {
  char ch;
  bool is_line_ready = false;

  while (programs::shell::session::pop(&ring_, &ch)) {
    if (ch == '\r' || ch == '\n') {
      if (line_pos_ == 0) continue;
      line_buf_[line_pos_] = '\0';
      line_pos_ = 0;
      is_line_ready = true;
      break;
    }

    if (ch == '\x7f' || ch == '\x08') {
      if (line_pos_ > 0) line_pos_--;
      continue;
    }

    if (ch < 0x20 && ch != '\t') continue;

    if (line_pos_ < line_cap_ - 1)
      line_buf_[line_pos_++] = ch;
  }

  if (!is_line_ready) return;

  if (strcmp(line_buf_, "exit") == 0 || strcmp(line_buf_, "quit") == 0) {
    write("logout\r\n", 8);
    flush();
    return;
  }

  run_command(line_buf_, flush_fn_, flush_ctx_);
  send_prompt();
}

int console::remote::run_command(const char *line, flush_fn flush, void *ctx) {
  RedirectCtx rctx = {flush, ctx};

  FILE *capture = funopen(&rctx, NULL, redirect_write, NULL, NULL);
  if (!capture) return -1;

  setvbuf(capture, NULL, _IONBF, 0);

  FILE *saved = stdout;
  stdout = capture;

  int ret = Console.run(line);

  fflush(capture);
  stdout = saved;
  fclose(capture);

  return ret;
}
