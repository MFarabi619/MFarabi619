#pragma once

#include <sqlite3.h>

namespace programs::sqlite {

bool open(const char *path = nullptr);
void close();
[[nodiscard]] bool isOpen();
const char *currentPath();
sqlite3 *handle();
int lastErrorCode();
const char *lastError();
int changes();
sqlite3_int64 lastInsertRowid();
sqlite3_int64 memoryUsed();
sqlite3_int64 memoryHighwater(bool reset = false);

void registerCmd();

#ifdef PIO_UNIT_TESTING
void test();
#endif

}
