#include "history.h"

#include <SD.h>
#include <string.h>

//------------------------------------------
//  History
//------------------------------------------
console::History::History(size_t max_entries, bool is_deduplicating)
    : count_(0), max_entries_(max_entries > MAX_ENTRIES ? MAX_ENTRIES : max_entries),
      current_index_(-1), is_deduplicating_(is_deduplicating) {}

void console::History::add(const char *command) {
  if (!command || command[0] == '\0') return;

  if (is_deduplicating_ && count_ > 0) {
    if (strcmp(entries_[count_ - 1], command) == 0) return;
  }

  if (count_ >= max_entries_) {
    memmove(entries_[0], entries_[1], (count_ - 1) * ENTRY_SIZE);
    count_--;
  }

  strlcpy(entries_[count_], command, ENTRY_SIZE);
  count_++;
  current_index_ = -1;
}

const char *console::History::previous() {
  if (count_ == 0) return nullptr;

  if (current_index_ < 0)
    current_index_ = (int)count_ - 1;
  else if (current_index_ > 0)
    current_index_--;

  return entries_[current_index_];
}

const char *console::History::next() {
  if (current_index_ < 0) return nullptr;

  if ((size_t)current_index_ >= count_ - 1) {
    current_index_ = -1;
    return nullptr;
  }

  current_index_++;
  return entries_[current_index_];
}

void console::History::reset_position() {
  current_index_ = -1;
}

void console::History::clear() {
  count_ = 0;
  current_index_ = -1;
}

size_t console::History::length() const {
  return count_;
}

bool console::History::is_empty() const {
  return count_ == 0;
}

//------------------------------------------
//  Persistent storage
//------------------------------------------
void console::History::load(const char *path) {
  File f = SD.open(path, FILE_READ);
  if (!f) return;

  char line[ENTRY_SIZE];
  size_t pos = 0;

  while (f.available()) {
    char ch = f.read();
    if (ch == '\n' || ch == '\r') {
      if (pos > 0) {
        line[pos] = '\0';
        add(line);
        pos = 0;
      }
      continue;
    }
    if (pos < ENTRY_SIZE - 1)
      line[pos++] = ch;
  }

  if (pos > 0) {
    line[pos] = '\0';
    add(line);
  }

  f.close();
  current_index_ = -1;
}

void console::History::save(const char *path) const {
  File f = SD.open(path, FILE_WRITE);
  if (!f) return;

  for (size_t i = 0; i < count_; i++) {
    f.println(entries_[i]);
  }

  f.close();
}
