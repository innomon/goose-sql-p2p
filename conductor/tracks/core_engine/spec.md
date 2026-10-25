# Specification: Core SQLite C Integration, Config Compatibility & Pear P2P Replication Engine

## 1. Overview
Reimplement the core `sqlite-p2p` engine in Goose, interfacing directly with native C SQLite (`sqlite3.c`/`sqlite3.h`), supporting full configuration parity (`config.example.json`), and implementing the Pear P2P replication stack (Hypercore log format, Hyperswarm DHT discovery, and Autobase multi-writer consensus).

## 2. Requirements & Deliverables

### 2.1 Configuration Subsystem
- Parse standard `sqlite-p2p` JSON configuration files:
  - `node_id`: string
  - `swarm_topic`: string (or 32-byte hex/hash)
  - `swarm_port`: int (0 for ephemeral)
  - `bootstrap`: list of string addresses (`host:port`)
  - `peer_addrs`: list of string addresses
  - `db_path`: string
  - `enable_wal`: bool
  - `enable_crypto`: bool
  - `auto_sync`: bool
  - `replication`: `{ mode: string, whitelist: list, blacklist: list }`

### 2.2 Native SQLite Engine & Schema
- Direct C FFI interface to SQLite 3:
  - `PRAGMA journal_mode = WAL;`
  - `PRAGMA synchronous = NORMAL;`
  - `PRAGMA foreign_keys = ON;`
- Initialize and manage table `crm_store`:
  ```sql
  CREATE TABLE IF NOT EXISTS crm_store (
      key TEXT PRIMARY KEY,
      metadata TEXT CHECK(json_valid(metadata)),
      data BLOB
  ) WITHOUT ROWID;
  ```
- CRUD API: `Put(key, metadata, data)`, `Get(key)`, `Delete(key)`, `List()`.
- Mutation capture hooks generating binary changesets for replication.

### 2.3 Pear P2P Protocol & Replication Mesh
- **Hypercore Feed**: Binary append-only log format matching Go `sqlite-p2p`.
- **Hyperswarm & DHT**: Peer discovery over 32-byte swarm topics and TCP/UDP socket communication.
- **Autobase Linearization**: Last-Write-Wins (LWW) conflict reconciliation and changeset application via `sqlite3changeset_apply`.

### 2.4 Cryptographic Layer
- AES-256-GCM authenticated payload encryption/decryption when `enable_crypto` is active.
- Key Registry and crypto-shredding support.

### 2.5 Verification & Interoperability
- Unit tests for SQLite bindings, config parser, and crypto routines.
- Integration tests demonstrating multi-node sync between `goose-sql-p2p` and Go `sqlite-p2p`.
