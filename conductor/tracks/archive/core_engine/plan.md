# Implementation Plan: Core SQLite C Integration, Config Compatibility & Pear P2P Replication Engine

## Phase 1: Project Scaffolding & Toolchain Setup
- [x] Setup Goose project structure (`src/`, `csrc/`, `tests/`, `config/`)
- [x] Vendor or link SQLite 3 amalgamation (`sqlite3.c`, `sqlite3.h` / `libsqlite3-dev`)
- [x] Configure build scripts / Makefile to compile Goose code to C and link with SQLite and cryptographic primitives
- [x] Implement command line argument parser and handcrafted command registry

## Phase 2: Configuration Loader & SQLite Storage Engine
- [x] Implement JSON configuration loader with full field compatibility matching `config.example.json`
- [x] Create Goose native C FFI wrapper for SQLite 3
- [x] Initialize `crm_store` table with WAL mode and JSON validation
- [x] Implement Put, Get, Delete, and List operations on `crm_store`
- [x] Add unit tests for SQLite database operations and configuration parsing

## Phase 3: Cryptography & Key Management
- [x] Implement AES-256-GCM authenticated cipher and SHA-256 hashing
- [x] Implement Base32 deterministic pseudonym generation
- [x] Implement KeyRegistry with crypto-shredding support
- [x] Add unit tests for crypto routines and key shredding

## Phase 4: Pear P2P Protocol Stack (Hypercore, Hyperswarm, Autobase)
- [x] Implement Hypercore append-only binary log serialization and verification
- [x] Implement Hyperswarm DHT / Noise peer discovery and socket transport
- [x] Implement Changeset capture and Autobase multi-writer causal linearization (LWW)
- [x] Implement `sqlite3changeset_apply` hook for remote mutation ingestion

## Phase 5: Drop-in CLI, End-to-End Testing & Cross-Replication Verification
- [x] Implement full CLI interface drop-in replacement matching `sqlite-p2p`
- [x] Write integration test harness
- [x] Execute bi-directional cross-replication test between Go `sqlite-p2p` and Goose `goose-sql-p2p`
- [x] Document benchmarks and finalize release build
