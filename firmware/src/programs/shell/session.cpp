#include "session.h"

void programs::shell::session::reset(RingBuffer *ring) noexcept {
  if (!ring) return;
  ring->head = 0;
  ring->tail = 0;
}

bool programs::shell::session::push(RingBuffer *ring, char ch) noexcept {
  if (!ring || !ring->data || ring->capacity == 0) return false;
  uint16_t next = (ring->head + 1) % ring->capacity;
  if (next == ring->tail) return false;
  ring->data[ring->head] = ch;
  ring->head = next;
  return true;
}

int programs::shell::session::pop(RingBuffer *ring, char *ch) noexcept {
  if (!ring || !ch || !ring->data || ring->head == ring->tail) return 0;
  *ch = ring->data[ring->tail];
  ring->tail = (ring->tail + 1) % ring->capacity;
  return 1;
}

void programs::shell::session::reset(WriteBuffer *buffer) noexcept {
  if (!buffer) return;
  buffer->position = 0;
}

bool programs::shell::session::push(WriteBuffer *buffer, char ch) noexcept {
  if (!buffer || !buffer->data || buffer->capacity == 0) return false;
  if (buffer->position >= buffer->capacity) return false;
  buffer->data[buffer->position++] = ch;
  return true;
}
