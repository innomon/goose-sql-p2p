# Technology Stack: goose-sql-p2p

## Core Technologies
- **Primary Language**: [Goose](https://aardappel.github.io/goose) (Single-stack, memory-safe systems programming language that compiles to C).
- **C Compiler & Toolchain**: GCC / Clang for compiling Goose-generated C code and static linking.
- **Embedded Database**: [SQLite 3 (Official C Amalgamation)](https://www.sqlite.org/) with WAL journaling mode, JSON1 extension, and Session API (`sqlite3session_*`, `sqlite3changeset_*`).
- **Cryptography & Security**: Native C / Goose cryptographic routines for AES-256-GCM authenticated encryption, SHA-256 hashing, and Base32 pseudonym encoding.
- **Networking & P2P Protocol**: BSD Sockets (TCP/UDP) implementing:
  - Hypercore append-only log serialization
  - Hyperswarm DHT 32-byte topic peer discovery
  - Autobase vector-clock multi-master consensus
  - Noise / SecretStream secure transport framing
- **Configuration Format**: Standard JSON matching `config.example.json` schema.
- **Build & Packaging**: Handcrafted build script / Makefile invoking Goose compiler and C compiler into a zero-dependency self-contained executable.
- **Testing & Interoperability**: Integration test suite executing multi-node replication benchmarks between `goose-sql-p2p` and Go `sqlite-p2p`.
