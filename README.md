# goose-sql-p2p

A high-performance peer-to-peer SQLite replication engine implemented in the [Goose programming language](https://aardappel.github.io/goose), featuring direct C-native SQLite 3 amalgamation integration, Pear protocol compatibility (Hypercore, Hyperswarm, Autobase LWW consensus), and drop-in configuration parity with `sqlite-p2p`.

---

## Key Features

- **Direct SQLite 3 C Integration**: Interfaces directly with original SQLite C amalgamation (`libsqlite3`) via Goose C-native FFI, supporting full WAL mode and `CHECK(json_valid(metadata))` integrity constraints.
- **Pear Protocol Parity**:
  - **Hypercore**: Append-only binary changeset feed with continuous rolling SHA-256 state hashing.
  - **Hyperswarm**: 32-byte swarm topic discovery and TCP peer pooling.
  - **Autobase LWW**: Deterministic multi-writer causal linearization and conflict resolution via timestamp-based Last-Write-Wins.
- **Drop-in Configuration & CLI Compatibility**: Compatible with `sqlite-p2p` configuration JSON files (`config/config.example.json`, node configs) and command-line flags (`-config`, `-node`, `-port`, `-db`, `-bootstrap`, `-peer`, `-cmd`).
- **Slash Commands & REPL**: Interactive prompt supporting both standard and slash commands (`put`, `/put`, `get`, `/get`, `del`, `/del`, `list`, `/list`, `sync`, `/sync`, `peers`, `/peers`, `feed`, `/feed`, `status`, `/status`, `help`, `/help`, `exit`, `/exit`).
- **Cryptographic Security**: Native AES-256-GCM authenticated payload encryption, SHA-256 digest hashing, and RFC-4648 Base32 pseudonymization.

---

## Directory Structure

```
goose-sql-p2p/
├── Makefile                          # Build system for goose-sql-p2p & unit_test
├── build.sh                          # Compilation shell wrapper
├── csrc/                             # C Native Bridge Layer
│   ├── bridge.h                      # Unified C header for SQLite, OpenSSL & Sockets
│   ├── bridge.c                      # SQLite, Crypto, and Socket implementations
│   ├── sqlite3_bridge.h / .c         # SQLite 3 FFI bindings
│   ├── crypto_bridge.h / .c          # OpenSSL 3.0 crypto bindings
│   └── socket_bridge.h / .c          # Sockets & polling networking
├── src/                              # Goose Source Code
│   ├── main.goose                    # Application entry point & REPL loop
│   ├── types.goose                   # Struct definitions (NodeConfig, Changeset, etc.)
│   ├── db.goose                      # SQLite storage operations & schema init
│   ├── crypto.goose                  # AES-256-GCM, SHA-256 & Base32 helpers
│   ├── net.goose                     # Framed TCP & UDP networking
│   ├── json_util.goose               # Fast JSON parsing & field extraction
│   ├── changeset.goose               # Changeset serialization & Autobase LWW consensus
│   ├── feed.goose                    # Hypercore append-only feed
│   ├── config.goose                  # Config file loader & CLI argument parser
│   ├── replicator.goose              # P2P connection pool & mutation broadcasting
│   ├── cli.goose                     # Handcrafted command & slash command registry
│   └── unit_test.goose               # Unit test suite
├── config/                           # Configuration templates
│   ├── config.example.json           # Canonical example configuration
│   └── node1.json                    # Cluster node configuration
└── scripts/
    └── cross-replication-test.sh     # Comprehensive E2E & replication test harness
```

---

## Prerequisites

- GCC / Clang
- `libsqlite3-dev`
- `libssl-dev`
- Goose compiler (installed at `~/.local/goose-lang/bin/goose`)

---

## Building

```bash
# Build binary and unit test suite
make all

# Output binaries:
# - bin/goose-sql-p2p
# - bin/unit_test
```

---

## Running

### Daemon / Interactive REPL Mode

```bash
# Start Node 1
./bin/goose-sql-p2p -node "node-1" -db "data/node1.db" -port 43219

# Start Node 2 (connecting to Node 1)
./bin/goose-sql-p2p -node "node-2" -db "data/node2.db" -port 43220 -peer "127.0.0.1:43219"
```

### One-Shot CLI Commands

```bash
# Store record
./bin/goose-sql-p2p -db "data/node1.db" -cmd "put user:101 Alice {\"timestamp\":1000}"

# Query record
./bin/goose-sql-p2p -db "data/node1.db" -cmd "get user:101"

# List records by prefix
./bin/goose-sql-p2p -db "data/node1.db" -cmd "list user:"

# View Hypercore changeset feed
./bin/goose-sql-p2p -db "data/node1.db" -cmd "feed"

# Delete record
./bin/goose-sql-p2p -db "data/node1.db" -cmd "del user:101"
```

---

## Testing

```bash
# Run unit tests
make unit_test

# Run full end-to-end and bidirectional replication test suite
./scripts/cross-replication-test.sh
```
