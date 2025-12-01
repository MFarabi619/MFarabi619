SRC = hello.asm
BUILD_DIR = build
OUT = $(BUILD_DIR)/hello

all: $(OUT)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(OUT): $(SRC) | $(BUILD_DIR)
	clang -o $@ $<

run: $(OUT)
	./$(OUT)

clean:
	rm -rf $(BUILD_DIR)
