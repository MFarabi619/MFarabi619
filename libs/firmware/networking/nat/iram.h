#ifndef IRAM_H_
#define IRAM_H_

#define IRAM_HOT __attribute__((section(".iram1"))) __attribute__((hot))

#endif
