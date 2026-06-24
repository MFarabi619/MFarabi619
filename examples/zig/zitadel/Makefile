# zig cc **/*.c -Iinclude -o build && ./build

CC ?= clang
AR := ar
ARFLAGS := rcs

CFLAGS  := -Wall -Wextra -Wpedantic -O2
DEBUG_FLAGS := -g -O0 -fsanitize=address,undefined
CPPFLAGS := -Iinclude

BIN     := bin/example
BUILD   := build
LIBDIR  := lib

LIBNAME := arithmetic
LIBA    := $(LIBDIR)/lib$(LIBNAME).a

APP_SRCS := $(wildcard src/*.c)
APP_OBJS := $(patsubst %.c,$(BUILD)/%.o,$(APP_SRCS))

LIB_SRCS := $(wildcard modules/$(LIBNAME)/*.c)
LIB_OBJS := $(patsubst %.c,$(BUILD)/%.o,$(LIB_SRCS))

DEPS := $(APP_OBJS:.o=.d) $(LIB_OBJS:.o=.d)

all: $(BIN)

$(BIN): $(APP_OBJS) $(LIBA)
	@mkdir -p $(@D)
	$(CC) $(APP_OBJS) -L$(LIBDIR) -l$(LIBNAME) -o $@

$(LIBA): $(LIB_OBJS)
	@mkdir -p $(@D)
	$(AR) $(ARFLAGS) $@ $^

$(BUILD)/%.o: %.c
	@mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

-include $(DEPS)

run: $(BIN)
	./$(BIN)

debug: CFLAGS += $(DEBUG_FLAGS)
debug: clean $(BIN)

clean:
	rm -rf $(BUILD) $(LIBDIR) bin

.PHONY: all run clean debug
