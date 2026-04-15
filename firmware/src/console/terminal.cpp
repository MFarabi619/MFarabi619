#include "terminal.h"

#include <string.h>

//------------------------------------------
//  Terminal
//------------------------------------------
console::Terminal::Terminal(char *buf, size_t cap)
    : buf_(buf), cap_(cap), len_(0), cursor_(0),
      last_char_(0), escape_state_(Normal) {
  buf_[0] = '\0';
}

console::KeyCode console::Terminal::process_byte(uint8_t byte) {
  switch (escape_state_) {
  case Normal:
    switch (byte) {
    case '\r': case '\n':     return KeyCode::Enter;
    case 0x01:               return KeyCode::CtrlA;
    case 0x02:               return KeyCode::CtrlB;
    case 0x03:               return KeyCode::CtrlC;
    case 0x04:               return KeyCode::CtrlD;
    case 0x05:               return KeyCode::CtrlE;
    case 0x06:               return KeyCode::CtrlF;
    case 0x08:               return KeyCode::Backspace;
    case 0x09:               return KeyCode::Tab;
    case 0x0B:               return KeyCode::CtrlK;
    case 0x0C:               return KeyCode::CtrlL;
    case 0x0E:               return KeyCode::CtrlN;
    case 0x10:               return KeyCode::CtrlP;
    case 0x12:               return KeyCode::CtrlR;
    case 0x14:               return KeyCode::CtrlT;
    case 0x15:               return KeyCode::CtrlU;
    case 0x17:               return KeyCode::CtrlW;
    case 0x1B:
      escape_state_ = Escape;
      return KeyCode::None;
    case 0x7F:               return KeyCode::Backspace;
    default:
      if (byte >= 0x20 && byte < 0x7F) {
        last_char_ = byte;
        return KeyCode::Char;
      }
      return KeyCode::None;
    }

  case Escape:
    if (byte == '[') {
      escape_state_ = Bracket;
      return KeyCode::None;
    }
    escape_state_ = Normal;
    return KeyCode::Escape;

  case Bracket:
    escape_state_ = Normal;
    switch (byte) {
    case 'A': return KeyCode::ArrowUp;
    case 'B': return KeyCode::ArrowDown;
    case 'C': return KeyCode::ArrowRight;
    case 'D': return KeyCode::ArrowLeft;
    case 'H': return KeyCode::Home;
    case 'F': return KeyCode::End;
    case '1': return KeyCode::Home;   // ESC[1~ (some terminals)
    case '3': return KeyCode::Delete; // ESC[3~
    case '4': return KeyCode::End;    // ESC[4~ (some terminals)
    default:  return KeyCode::None;
    }
  }

  return KeyCode::None;
}

console::TerminalEvent console::Terminal::handle_key(KeyCode key, uint8_t ch) {
  switch (key) {
  case KeyCode::Enter:
    return len_ == 0 ? TerminalEvent::EmptyCommand : TerminalEvent::CommandReady;

  case KeyCode::Backspace:
    if (cursor_ > 0 && len_ > 0) {
      memmove(buf_ + cursor_ - 1, buf_ + cursor_, len_ - cursor_);
      cursor_--;
      len_--;
      buf_[len_] = '\0';
      return TerminalEvent::BufferChanged;
    }
    return TerminalEvent::None;

  case KeyCode::Delete:
    if (cursor_ < len_) {
      memmove(buf_ + cursor_, buf_ + cursor_ + 1, len_ - cursor_ - 1);
      len_--;
      buf_[len_] = '\0';
      return TerminalEvent::BufferChanged;
    }
    return TerminalEvent::None;

  case KeyCode::ArrowLeft:
  case KeyCode::CtrlB:
    if (cursor_ > 0) {
      cursor_--;
      return TerminalEvent::CursorMoved;
    }
    return TerminalEvent::None;

  case KeyCode::ArrowRight:
  case KeyCode::CtrlF:
    if (cursor_ < len_) {
      cursor_++;
      return TerminalEvent::CursorMoved;
    }
    return TerminalEvent::None;

  case KeyCode::Home:
  case KeyCode::CtrlA:
    if (cursor_ > 0) {
      cursor_ = 0;
      return TerminalEvent::CursorHome;
    }
    return TerminalEvent::None;

  case KeyCode::End:
  case KeyCode::CtrlE:
    if (cursor_ < len_) {
      cursor_ = len_;
      return TerminalEvent::CursorEnd;
    }
    return TerminalEvent::None;

  case KeyCode::ArrowUp:
  case KeyCode::CtrlP:
    return TerminalEvent::HistoryPrevious;

  case KeyCode::ArrowDown:
  case KeyCode::CtrlN:
    return TerminalEvent::HistoryNext;

  case KeyCode::CtrlC:
    return TerminalEvent::Interrupt;

  case KeyCode::CtrlD:
    if (len_ == 0) return TerminalEvent::EndOfFile;
    if (cursor_ < len_) {
      memmove(buf_ + cursor_, buf_ + cursor_ + 1, len_ - cursor_ - 1);
      len_--;
      buf_[len_] = '\0';
      return TerminalEvent::BufferChanged;
    }
    return TerminalEvent::None;

  case KeyCode::CtrlK:
    if (cursor_ < len_) {
      len_ = cursor_;
      buf_[len_] = '\0';
      return TerminalEvent::KillToEnd;
    }
    return TerminalEvent::None;

  case KeyCode::CtrlL:
    return TerminalEvent::ClearScreen;

  case KeyCode::CtrlR:
    return TerminalEvent::Redraw;

  case KeyCode::CtrlT:
    if (cursor_ > 0 && cursor_ < len_) {
      char tmp = buf_[cursor_ - 1];
      buf_[cursor_ - 1] = buf_[cursor_];
      buf_[cursor_] = tmp;
      if (cursor_ < len_) cursor_++;
      return TerminalEvent::SwapChars;
    }
    return TerminalEvent::None;

  case KeyCode::CtrlW:
    return TerminalEvent::DeleteWord;

  case KeyCode::CtrlU:
    return TerminalEvent::ClearLine;

  case KeyCode::Char:
    if (len_ < cap_ - 1) {
      if (cursor_ < len_)
        memmove(buf_ + cursor_ + 1, buf_ + cursor_, len_ - cursor_);
      buf_[cursor_] = (char)last_char_;
      cursor_++;
      len_++;
      buf_[len_] = '\0';
      return TerminalEvent::BufferChanged;
    }
    return TerminalEvent::None;

  default:
    return TerminalEvent::None;
  }
}

const char *console::Terminal::buffer_str() const {
  return buf_;
}

size_t console::Terminal::buffer_length() const {
  return len_;
}

size_t console::Terminal::cursor_position() const {
  return cursor_;
}

void console::Terminal::set_buffer(const char *content) {
  size_t slen = strlen(content);
  if (slen >= cap_) slen = cap_ - 1;
  memcpy(buf_, content, slen);
  buf_[slen] = '\0';
  len_ = slen;
  cursor_ = slen;
}

void console::Terminal::clear_buffer() {
  len_ = 0;
  cursor_ = 0;
  buf_[0] = '\0';
}

const char *console::Terminal::take_command() {
  buf_[len_] = '\0';
  len_ = 0;
  cursor_ = 0;
  return buf_;
}
