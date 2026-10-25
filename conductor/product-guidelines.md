# Product Guidelines: goose-sql-p2p

## 1. Architectural Principles
- **Drop-in Interchangeability**: Every subsystem (configuration parser, database schema, P2P wire messages, changeset serialization) must maintain 100% parity with the Go `sqlite-p2p` implementation.
- **Direct C Interop without Dynamic Dependencies**: Leverage Goose's C compilation pipeline to compile and statically link the standard SQLite amalgamation (`sqlite3.c` / `sqlite3.h`) alongside cryptographic ciphers (AES-256-GCM / SHA-256).
- **Deterministic Stack Memory Management**: Rely on Goose's stack-based memory model and avoid unmanaged heap allocations or memory leaks across long-running daemon lifecycles.
- **Decentralized Local-First Resilience**: Engine must operate seamlessly in offline mode, local network LANs, and dynamic DHT mesh topologies without single points of failure.

---

## 2. Code Quality & Modularity
- **Layered Structure**:
  - `sqlite/`: Direct SQLite C bindings, connection management, session & changeset hooks, pragma configurations (WAL mode).
  - `p2p/`: Pear protocol stack implementation (Hypercore feed format, Hyperswarm discovery, DHT topic handling, Autobase causal linearization).
  - `crypto/`: AES-256-GCM encryption/decryption, deterministic pseudonym generation (Base32/SHA256), and Key Registry shredding.
  - `config/`: JSON configuration parsing matching `config.example.json` and node configuration specs.
  - `cmd/`: Handcrafted CLI entrypoints and daemon runner.
- **Fail-Fast Error Handling**: All file I/O, database queries, and network transitions must return explicit error states rather than panicking or crashing.

---

## 3. Wire Protocol & Interoperability Rules
- **Binary & JSON Equivalence**: Wire packets, Hypercore block headers, changeset encodings, and peer handshake framing must match the Go `sqlite-p2p` byte-for-byte.
- **LWW Multi-Master Conflict Resolution**: Conflicts across peer nodes must resolve deterministically via vector timestamps and Lamport clocks matching Autobase semantics.

---

## 4. Logging & Observability
- Follow standard structured logging (timestamp, level, component, message, context fields) for unified debugging and log parsing alongside Go nodes.
