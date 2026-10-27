# Implementation Plan: Arbitrary SQL Execution Command (`sql` and `/sql`)

## Phase 1: C Bridge Layer & Formatters
- [x] Task: Implement `gs_db_query_raw` in `csrc/bridge.h` and `csrc/bridge.c` supporting JSON, ASCII table, and CSV output formats
- [x] Task: Add error handling and error message capture for SQLite execution failures
- [x] Task: Conductor - User Manual Verification 'Phase 1: C Bridge Layer & Formatters'

## Phase 2: Goose DB FFI Binding & CLI Command Handler
- [x] Task: Add `db::query_raw` wrapper in `src/db.goose`
- [x] Task: Implement `sql` and `/sql` command parser in `src/cli.goose` supporting `--format` / `-f` flags and multi-word SQL statements
- [x] Task: Wire command execution into interactive REPL and one-shot `-cmd` modes
- [x] Task: Conductor - User Manual Verification 'Phase 2: Goose DB FFI Binding & CLI Command Handler'

## Phase 3: Unit Testing, Integration & Verification
- [x] Task: Add test suite for `sql` command in `src/unit_test.goose` testing SELECT (JSON, Table, CSV), INSERT/UPDATE/DELETE rows affected, and error handling
- [x] Task: Update `scripts/cross-replication-test.sh` with `sql` command verification
- [x] Task: Run full build and test suite, update docs
- [x] Task: Conductor - User Manual Verification 'Phase 3: Unit Testing, Integration & Verification'
