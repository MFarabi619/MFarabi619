#include "session.h"

void programs::shell::session::reset(RingBuffer *ring) {
  if (!ring) return;
  ring->head.store(0, std::memory_order_relaxed);
  ring->tail.store(0, std::memory_order_relaxed);
}

bool programs::shell::session::push(RingBuffer *ring, char ch) {
  if (!ring || !ring->data || ring->capacity == 0) return false;
  uint16_t head = ring->head.load(std::memory_order_relaxed);
  uint16_t tail = ring->tail.load(std::memory_order_acquire);
  uint16_t next = (head + 1) % ring->capacity;
  if (next == tail) return false;
  ring->data[head] = ch;
  ring->head.store(next, std::memory_order_release);
  return true;
}

int programs::shell::session::pop(RingBuffer *ring, char *ch) {
  if (!ring || !ch || !ring->data) return 0;
  uint16_t tail = ring->tail.load(std::memory_order_relaxed);
  uint16_t head = ring->head.load(std::memory_order_acquire);
  if (head == tail) return 0;
  *ch = ring->data[tail];
  ring->tail.store((tail + 1) % ring->capacity, std::memory_order_release);
  return 1;
}

void programs::shell::session::reset(WriteBuffer *buffer) {
  if (!buffer) return;
  buffer->position = 0;
}

bool programs::shell::session::push(WriteBuffer *buffer, char ch) {
  if (!buffer || !buffer->data || buffer->capacity == 0) return false;
  if (buffer->position >= buffer->capacity) return false;
  buffer->data[buffer->position++] = ch;
  return true;
}
