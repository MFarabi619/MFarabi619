#ifndef PROGRAMS_SHELL_SESSION_H
#define PROGRAMS_SHELL_SESSION_H

#include <stddef.h>
#include <stdint.h>

namespace programs::shell::session {

struct RingBuffer {
  char *data;
  uint16_t capacity;
  volatile uint16_t head;
  volatile uint16_t tail;
};

struct WriteBuffer {
  char *data;
  size_t capacity;
  size_t position;
};

void reset(RingBuffer *ring) noexcept;
bool push(RingBuffer *ring, char ch) noexcept;
int pop(RingBuffer *ring, char *ch) noexcept;

void reset(WriteBuffer *buffer) noexcept;
bool push(WriteBuffer *buffer, char ch) noexcept;

}

#endif
