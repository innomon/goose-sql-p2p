# Initial Concept

Reimplement `sqlite-p2p` project (/home/innomon/B204-zone/owly-sewa/sqlite-p2p) in the Goose programming language (https://aardappel.github.io/goose). Since Goose compiles its source code to C first, directly link and interface with the original SQLite C library (https://www.sqlite.org/).

The project must serve as a drop-in replacement for `sqlite-p2p` with full configuration file compatibility (including config formats and settings), fully implementing the Pear P2P replication protocol so that a Go `sqlite-p2p` instance and a Goose `goose-sql-p2p` instance can bidirectionally replicate data seamlessly.

# Product Guide: goose-sql-p2p

## 1. Vision & Core Objective
`goose-sql-p2p` is a high-performance, decentralized, local-first SQLite replication engine written in the **Goose programming language** (https://aardappel.github.io/goose). Since Goose compiles directly to C and utilizes a deterministic stack-based memory model (zero GC pause, zero heap fragmentation), `goose-sql-p2p` directly interfaces with native SQLite C libraries (https://www.sqlite.org/) and provides a **100% wire-compatible and config-compatible drop-in replacement** for `sqlite-p2p` (Go version).

A `goose-sql-p2p` node seamlessly joins existing Pear/Holepunch P2P swarms and replicates bidirectionally with Go `sqlite-p2p` peer nodes.

---

## 2. Key Capabilities & Scope

### 2.1 Native SQLite C Integration
- Direct native FFI integration with SQLite amalgamation C source / headers (`sqlite3.h`, `sqlite3.c`).
- Standard schema support for `crm_store`:
  ```sql
  CREATE TABLE IF NOT EXISTS crm_store (
      key TEXT PRIMARY KEY,
      metadata TEXT CHECK(json_valid(metadata)),
      data BLOB
  ) WITHOUT ROWID;
  ```
- Full support for SQLite Session API / Changeset generation and application (`sqlite3session_*`, `sqlite3changeset_*`) and WAL journal mode.

### 2.2 Wire & Protocol Compatibility (Pear / Holepunch Stack)
- **Hypercore Feed Replication**: Binary changeset append-only log format wire-compatible with Go `sqlite-p2p`.
- **Hyperswarm & HyperDHT**: 32-byte topic-based peer discovery, dynamic port binding, air-gapped/offline local bootstrap roots, and cluster bootstrap joining.
- **Autobase Multi-Writer Consensus**: Deterministic causal ordering and Last-Write-Wins (LWW) conflict resolution across heterogeneous Go and Goose nodes.
- **Noise / SecretStream Transport**: Encrypted peer sessions over TCP/UDP.

### 2.3 Drop-in Configuration & CLI Compatibility
- 100% schema compatibility with `sqlite-p2p` configuration files:
  - `node_id`, `swarm_topic`, `swarm_port`, `bootstrap`, `peer_addrs`, `db_path`, `enable_wal`, `enable_crypto`, `auto_sync`, `replication` (mode/whitelist/blacklist).
- Command-line flags and environmental drop-in compatibility.

### 2.4 Security & Privacy
- Authenticated AES-256-GCM symmetric encryption for payloads.
- Crypto-shredding key lifecycle management (purging symmetric keys instantly invalidates historical ciphertext while preserving causal verification).

---

## 3. Success Metrics & Validation
- **Drop-in replacement test**: Replace Go `sqlite-p2p` with `goose-sql-p2p` against the same configuration files without manual adjustments.
- **Interoperability test**: Bi-directional replication between a Go `sqlite-p2p` instance and a Goose `goose-sql-p2p` instance with 0 data divergence under multi-master writes.
- **Performance & Footprint**: Fast startup, low memory overhead leveraging Goose's single-stack memory management and native C SQLite speed.
