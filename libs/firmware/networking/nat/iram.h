/*
 * Copyright (c) 2026 Apidae Systems
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef IRAM_H_
#define IRAM_H_

#define IRAM_HOT __attribute__((section(".iram1"))) __attribute__((hot))

#endif
