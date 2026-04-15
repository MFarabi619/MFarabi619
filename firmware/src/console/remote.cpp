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
      if (&buf[i] > start)
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

//------------------------------------------
//  Shell construction / reset
//------------------------------------------
console::remote::Shell::Shell(char *ring_buf, uint16_t ring_cap,
                              char *write_buf, size_t write_cap,
                              char *line_buf, size_t line_cap,
                              flush_fn flush, void *flush_ctx)
    : terminal_(line_buf, line_cap), history_(),
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
  terminal_.clear_buffer();
  history_.reset_position();
}

//------------------------------------------
//  Input — push raw bytes to ring buffer
//------------------------------------------
void console::remote::Shell::push_input(char ch) {
  programs::shell::session::push(&ring_, ch);
}

void console::remote::Shell::push_input(const char *data, size_t len) {
  for (size_t i = 0; i < len; i++)
    programs::shell::session::push(&ring_, data[i]);
}

//------------------------------------------
//  Output helpers
//------------------------------------------
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

void console::remote::Shell::redraw_line() {
  write("\r\x1b[K", 4);
  const char *buf = terminal_.buffer_str();
  size_t len = terminal_.buffer_length();
  size_t cursor = terminal_.cursor_position();

  if (len > 0)
    write(buf, len);

  if (cursor < len) {
    char esc[16];
    int n = snprintf(esc, sizeof(esc), "\x1b[%uD", (unsigned)(len - cursor));
    write(esc, n);
  }

  flush();
}

//------------------------------------------
//  MOTD / Prompt
//------------------------------------------
void console::remote::Shell::send_motd(const char *transport) {
  const char *motd = programs::shell::microfetch::generate(transport);
  write(motd, strlen(motd));
}

void console::remote::Shell::send_prompt() {
  const char *p = console::prompt::build("/");
  write(p, strlen(p));
  flush();
}

//------------------------------------------
//  Service loop — terminal-aware
//------------------------------------------
void console::remote::Shell::service() {
  char raw;
  while (programs::shell::session::pop(&ring_, &raw)) {
    console::KeyCode key = terminal_.process_byte((uint8_t)raw);
    if (key == console::KeyCode::None) continue;

    console::TerminalEvent event = terminal_.handle_key(key);

    switch (event) {
    case console::TerminalEvent::BufferChanged:
      redraw_line();
      break;

    case console::TerminalEvent::CursorMoved:
      if (key == console::KeyCode::ArrowLeft)
        write("\x1b[D", 3);
      else
        write("\x1b[C", 3);
      flush();
      break;

    case console::TerminalEvent::CommandReady: {
      write("\r\n", 2);
      const char *cmd = terminal_.take_command();

      if (strcmp(cmd, "exit") == 0 || strcmp(cmd, "quit") == 0) {
        write("logout\r\n", 8);
        flush();
        return;
      }

      history_.add(cmd);
      history_.reset_position();
      run_command(cmd, flush_fn_, flush_ctx_);
      send_prompt();
      break;
    }

    case console::TerminalEvent::EmptyCommand:
      write("\r\n", 2);
      send_prompt();
      break;

    case console::TerminalEvent::Interrupt:
      terminal_.clear_buffer();
      write("^C\r\n", 4);
      send_prompt();
      break;

    case console::TerminalEvent::EndOfFile:
      write("logout\r\n", 8);
      flush();
      return;

    case console::TerminalEvent::ClearScreen:
      terminal_.clear_buffer();
      write("\x1b[2J\x1b[H", 7);
      send_prompt();
      break;

    case console::TerminalEvent::DeleteWord: {
      const char *buf = terminal_.buffer_str();
      size_t len = terminal_.buffer_length();
      if (len == 0) break;

      size_t pos = len;
      while (pos > 0 && buf[pos - 1] == ' ') pos--;
      while (pos > 0 && buf[pos - 1] != ' ') pos--;

      char trimmed[256];
      if (pos >= sizeof(trimmed)) pos = sizeof(trimmed) - 1;
      memcpy(trimmed, buf, pos);
      trimmed[pos] = '\0';
      terminal_.set_buffer(trimmed);
      redraw_line();
      break;
    }

    case console::TerminalEvent::ClearLine:
      terminal_.clear_buffer();
      redraw_line();
      break;

    case console::TerminalEvent::HistoryPrevious: {
      const char *entry = history_.previous();
      if (entry) {
        terminal_.set_buffer(entry);
        redraw_line();
      }
      break;
    }

    case console::TerminalEvent::HistoryNext: {
      const char *entry = history_.next();
      if (entry)
        terminal_.set_buffer(entry);
      else
        terminal_.clear_buffer();
      redraw_line();
      break;
    }

    default:
      break;
    }
  }
}

//------------------------------------------
//  Command execution with stdout redirect
//------------------------------------------
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
