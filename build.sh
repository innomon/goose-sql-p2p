#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GOOSE="${GOOSE:-/home/innomon/.local/goose-lang/bin/goose}"
GOOSE_STDLIB="${GOOSE_STDLIB:-/home/innomon/.local/goose-lang/stdlib}"

mkdir -p bin

echo "Compiling Goose source to C..."
"$GOOSE" --stdlib "$GOOSE_STDLIB" --standalone --include csrc/bridge.h -o build_main.c src/main.goose

echo "Compiling C binary with native SQLite & OpenSSL..."
gcc -O2 -Wall -Wextra -Wno-unused-function -Wno-unused-variable -Wno-unused-parameter \
    -I./csrc build_main.c -lsqlite3 -lcrypto -lpthread -lm -o bin/goose-sql-p2p

echo "Build complete: bin/goose-sql-p2p"
