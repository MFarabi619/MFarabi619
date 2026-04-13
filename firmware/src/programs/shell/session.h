#ifndef PROGRAMS_SHELL_SESSION_H
#define PROGRAMS_SHELL_SESSION_H

#include <stddef.h>
#include <atomic>
#include <stdint.h>

namespace programs::shell::session {

struct RingBuffer {
  char *data;
  uint16_t capacity;
  std::atomic<uint16_t> head;
  std::atomic<uint16_t> tail;
};

struct WriteBuffer {
  char *data;
  size_t capacity;
  size_t position;
};

void reset(RingBuffer *ring);
bool push(RingBuffer *ring, char ch);
int pop(RingBuffer *ring, char *ch);

void reset(WriteBuffer *buffer);
bool push(WriteBuffer *buffer, char ch);

}

#endif
