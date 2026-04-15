#pragma once

#include <stddef.h>
#include <stdint.h>

namespace console {

//------------------------------------------
//  Key codes from ANSI escape parsing
//------------------------------------------
enum class KeyCode {
  None,
  Backspace,
  Delete,
  Enter,
  Tab,
  Escape,
  ArrowUp,
  ArrowDown,
  ArrowLeft,
  ArrowRight,
  CtrlC,
  CtrlD,
  CtrlL,
  CtrlW,
  CtrlU,
  CtrlP,
  CtrlN,
  Char,
};

//------------------------------------------
//  Events from key handling
//------------------------------------------
enum class TerminalEvent {
  None,
  BufferChanged,
  CursorMoved,
  CommandReady,
  EmptyCommand,
  Interrupt,
  EndOfFile,
  HistoryPrevious,
  HistoryNext,
  ClearScreen,
  DeleteWord,
  ClearLine,
};

//------------------------------------------
//  Terminal — line buffer with ANSI parsing
//------------------------------------------
class Terminal {
public:
  Terminal(char *buf, size_t cap);

  KeyCode process_byte(uint8_t byte);
  TerminalEvent handle_key(KeyCode key, uint8_t ch = 0);

  const char *buffer_str() const;
  size_t buffer_length() const;
  size_t cursor_position() const;

  void set_buffer(const char *content);
  void clear_buffer();
  const char *take_command();

private:
  char *buf_;
  size_t cap_;
  size_t len_;
  size_t cursor_;
  uint8_t last_char_;

  enum EscapeState { Normal, Escape, Bracket } escape_state_;
};

}
