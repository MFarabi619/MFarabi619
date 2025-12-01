CC = clang
ARCH = arm64

SRC = hello.asm
BUILD_DIR = build
OUT = $(BUILD_DIR)/hello

all: $(OUT)

$(OUT): $(SRC) | $(BUILD_DIR)
	$(CC) -o $@ $< -arch $(ARCH)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

run: $(OUT)
	./$(OUT)

show: $(OUT)
	@file $(OUT)
	@otool -hv $(OUT)

disassemble: $(OUT)
	@otool -tV $(OUT)

clean:
	rm -rf $(BUILD_DIR)
