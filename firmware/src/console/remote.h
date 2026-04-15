#pragma once

#include "session.h"
#include "terminal.h"
#include "history.h"
#include <stddef.h>

namespace console::remote {

typedef void (*flush_fn)(const char *data, size_t len, void *ctx);

//------------------------------------------
//  Shell — remote terminal with editing
//------------------------------------------
class Shell {
public:
  Shell(char *ring_buf, uint16_t ring_cap,
        char *write_buf, size_t write_cap,
        char *line_buf, size_t line_cap,
        flush_fn flush, void *flush_ctx);

  void reset();
  void push_input(char ch);
  void push_input(const char *data, size_t len);
  void service();
  void send_motd(const char *transport, const char *remote_ip = nullptr);
  void send_prompt();
  void save_history();

private:
  void write(const char *data, size_t len);
  void flush();
  void redraw_line();

  programs::shell::session::RingBuffer ring_;
  programs::shell::session::WriteBuffer write_;

  bool handle_builtin(const char *cmd);

  console::Terminal terminal_;
  console::History history_;

  char cwd_[128];

  flush_fn flush_fn_;
  void *flush_ctx_;
};

int run_command(const char *line, flush_fn flush, void *ctx);

}
