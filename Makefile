CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -Wno-unused-function -Wno-unused-variable -Wno-unused-parameter -I./csrc
LDFLAGS ?= -lsqlite3 -lcrypto -lpthread -lm
GOOSE ?= /home/innomon/.local/goose-lang/bin/goose
GOOSE_STDLIB ?= /home/innomon/.local/goose-lang/stdlib

BIN_DIR = bin
TARGET = $(BIN_DIR)/goose-sql-p2p
TEST_BIN = $(BIN_DIR)/unit_test

.PHONY: all clean test unit_test mcp_test

all: $(TARGET) $(TEST_BIN)

$(TARGET): src/*.goose csrc/*.c csrc/*.h
	mkdir -p $(BIN_DIR)
	$(GOOSE) --stdlib $(GOOSE_STDLIB) --standalone --include csrc/bridge.h -o build_main.c src/main.goose
	$(CC) $(CFLAGS) build_main.c -o $(TARGET) $(LDFLAGS)
	@echo "Build successful: $(TARGET)"

$(TEST_BIN): src/*.goose csrc/*.c csrc/*.h
	mkdir -p $(BIN_DIR)
	$(GOOSE) --stdlib $(GOOSE_STDLIB) --standalone --include csrc/bridge.h -o build_unit.c src/unit_test.goose
	$(CC) $(CFLAGS) build_unit.c -o $(TEST_BIN) $(LDFLAGS)
	@echo "Build successful: $(TEST_BIN)"

unit_test: $(TEST_BIN)
	$(TEST_BIN)

mcp_test: $(TARGET)
	./scripts/mcp-test.sh

clean:
	rm -f build_main.c build_unit.c $(TARGET) $(TEST_BIN) data/*.db data/*.db-wal data/*.db-shm

test: $(TARGET) $(TEST_BIN)
	$(TEST_BIN)
	./scripts/mcp-test.sh
	./scripts/cross-replication-test.sh
