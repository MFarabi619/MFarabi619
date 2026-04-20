#pragma once

#include <stddef.h>

namespace console {

//------------------------------------------
//  History — command history with navigation
//------------------------------------------
class History {
public:
  History(size_t max_entries = 16, bool is_deduplicating = true);

  void add(const char *command);
  const char *previous();
  const char *next();
  void reset_position();
  void clear();
  size_t length() const;
  bool is_empty() const;

  void load(const char *path);
  void save(const char *path) const;

private:
  static constexpr size_t MAX_ENTRIES = 16;
  static constexpr size_t ENTRY_SIZE = 256;

  char entries_[MAX_ENTRIES][ENTRY_SIZE];
  size_t count_;
  size_t max_entries_;
  int current_index_;
  bool is_deduplicating_;
};

}
