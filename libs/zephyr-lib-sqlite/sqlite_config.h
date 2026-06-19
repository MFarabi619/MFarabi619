#ifndef EMBEDDED_SQLITE_CONFIG_H_
#define EMBEDDED_SQLITE_CONFIG_H_

#define NDEBUG                          1

#define SQLITE_OS_OTHER                 1
#define SQLITE_THREADSAFE               0
#define SQLITE_TEMP_STORE               3
#define SQLITE_SYSTEM_MALLOC            1
#define SQLITE_MUTEX_NOOP               1

#define SQLITE_OMIT_LOAD_EXTENSION      1
#define SQLITE_OMIT_WAL                 1
#define SQLITE_OMIT_DEPRECATED          1
#define SQLITE_OMIT_AUTOINIT            1
#define SQLITE_OMIT_PROGRESS_CALLBACK   1
#define SQLITE_OMIT_SHARED_CACHE        1

#define SQLITE_DQS                      0
#define SQLITE_USE_URI                  0
#define SQLITE_DISABLE_LFS              1
#define SQLITE_DISABLE_DIRSYNC          1
#define SQLITE_LIKE_DOESNT_MATCH_BLOBS  1

#define SQLITE_DEFAULT_MEMSTATUS        0
#define SQLITE_DEFAULT_MMAP_SIZE        0
#define SQLITE_DEFAULT_PAGE_SIZE        512
#define SQLITE_DEFAULT_CACHE_SIZE       -8
#define SQLITE_DEFAULT_LOCKING_MODE     1
#define SQLITE_DEFAULT_FOREIGN_KEYS     1

#define SQLITE_MAX_EXPR_DEPTH           0
#define SQLITE_SMALL_STACK              1
#define SQLITE_SORTER_PMASZ             4

#endif
