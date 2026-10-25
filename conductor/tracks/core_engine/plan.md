# Implementation Plan: Core SQLite C Integration, Config Compatibility & Pear P2P Replication Engine

## Phase 1: Project Scaffolding & Toolchain Setup
- [ ] Setup Goose project structure (`src/`, `csrc/`, `tests/`, `config/`)
- [ ] Vendor or link SQLite 3 amalgamation (`sqlite3.c`, `sqlite3.h`)
- [ ] Configure build scripts / Makefile to compile Goose code to C and link with SQLite and cryptographic primitives
- [ ] Implement command line argument parser and handcrafted command registry

## Phase 2: Configuration Loader & SQLite Storage Engine
- [ ] Implement JSON configuration loader with full field compatibility matching `config.example.json`
- [ ] Create Goose native C FFI wrapper for SQLite 3
- [ ] Initialize `crm_store` table with WAL mode and JSON validation
- [ ] Implement Put, Get, Delete, and List operations on `crm_store`
- [ ] Add unit tests for SQLite database operations and configuration parsing

## Phase 3: Cryptography & Key Management
- [ ] Implement AES-256-GCM authenticated cipher and SHA-256 hashing
- [ ] Implement Base32 deterministic pseudonym generation
- [ ] Implement KeyRegistry with crypto-shredding support
- [ ] Add unit tests for crypto routines and key shredding

## Phase 4: Pear P2P Protocol Stack (Hypercore, Hyperswarm, Autobase)
- [ ] Implement Hypercore append-only binary log serialization and verification
- [ ] Implement Hyperswarm DHT / Noise peer discovery and socket transport
- [ ] Implement Changeset capture and Autobase multi-writer causal linearization (LWW)
- [ ] Implement `sqlite3changeset_apply` hook for remote mutation ingestion

## Phase 5: Drop-in CLI, End-to-End Testing & Cross-Replication Verification
- [ ] Implement full CLI interface drop-in replacement matching `sqlite-p2p`
- [ ] Write integration test harness
- [ ] Execute bi-directional cross-replication test between Go `sqlite-p2p` and Goose `goose-sql-p2p`
- [ ] Document benchmarks and finalize release build
