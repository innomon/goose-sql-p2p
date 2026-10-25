# Goose and C Systems Programming Style Guide

## 1. Goose Language Conventions
- Adhere to idiomatic Goose syntax and stack-oriented allocation patterns.
- Prefer explicit type annotations for functions, structs, and interfaces.
- Keep functions modular, single-responsibility, and easy to translate cleanly into C constructs.
- Leverage Goose's lexical scoping for automatic stack cleanup of buffers, strings, and data structures.

## 2. C SQLite & FFI Interoperability
- Encapsulate all native C calls and SQLite C API interactions (`sqlite3_*`) behind clean, typed Goose wrapper modules.
- Check return codes for all SQLite operations (`SQLITE_OK`, `SQLITE_ROW`, `SQLITE_DONE`) and convert errors into structured error types.
- Ensure proper resource deallocation: all SQLite statements (`sqlite3_stmt`) and database handles (`sqlite3*`) must be finalized and closed.

## 3. Wire Protocol & Cryptography Safety
- Zero cleartext logging of sensitive customer payloads or cryptographic key material.
- Enforce strict byte-level schema matching for Pear protocol messages (Hypercore, Hyperswarm, Autobase).
