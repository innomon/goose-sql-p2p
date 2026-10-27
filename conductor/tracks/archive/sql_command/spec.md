# Specification: Arbitrary SQL Execution Command (`sql` and `/sql`)

## 1. Overview

Implement an arbitrary SQL execution command (`sql` and `/sql`) in `goose-sql-p2p` that allows users to run arbitrary SQL statements (SELECT, INSERT, UPDATE, DELETE, CREATE, PRAGMA, EXPLAIN, schema inspections) directly against the local SQLite database in both interactive REPL mode and one-shot CLI execution mode (`-cmd "sql ..."`).

## 2. Functional Requirements

### 2.1 Command Syntax & Dispatch

- Support both `sql` and `/sql` as primary commands in the handcrafted command registry (`src/cli.goose`).
- Syntax: `sql [--format <json|table|csv>] <SQL STATEMENT>` or `/sql [-f <json|table|csv>] <SQL STATEMENT>`
- If no format flag is provided, default output format is **`json`**.

### 2.2 Output Formats

1. **JSON (`--format json` / `-f json` / default)**:
   - For `SELECT` queries returning rows: outputs a JSON array of row objects `[{"col1":val1, "col2":"val2"}, ...]`.
   - For non-query DDL/DML statements (`INSERT`, `UPDATE`, `DELETE`, `CREATE`, etc.): outputs `{"status":"ok","rows_affected":N}`.
2. **Table (`--format table` / `-f table`)**:
   - For `SELECT` queries returning rows: outputs an ASCII tabular grid with aligned column headers, separators, and data rows.
   - For non-query DDL/DML statements: outputs `OK: N rows affected.`.
3. **CSV (`--format csv` / `-f csv`)**:
   - For `SELECT` queries: outputs comma-separated values with a header line containing column names.
   - For non-query DDL/DML statements: outputs `status,rows_affected\nok,N`.

### 2.3 SQLite C Bridge Engine Extension

- Add native C bridge functions in `csrc/bridge.h` and `csrc/bridge.c`:
  - `gs_db_query_raw(uint64_t handle, sl_u8 sql, sl_u8 format, gs_rref out_result) -> int32_t`: Executes arbitrary SQL and returns formatted results into Goose string builder.
  - Support column data types (TEXT, INTEGER, REAL, BLOB, NULL).
  - Clear SQLite error message propagation (`sqlite3_errmsg(db)`).

### 2.4 Integration Modes

- **One-Shot CLI**: `./bin/goose-sql-p2p -db data/node1.db -cmd "sql SELECT * FROM crm_store"`
- **Interactive REPL**: `> sql --format table SELECT key, length(data) AS size FROM crm_store;`
- **Slash Command**: `> /sql SELECT count(*) FROM changeset_feed`

## 3. Non-Functional & Safety Requirements

- **WAL Concurrency**: Queries must execute concurrently with P2P replicator background activity without locking issues.
- **Documentation Integrity**: Workspace-relative paths in docs and comments.
- **Zero-Dependency CLI**: Handcrafted parser without Cobra/spf13.

## 4. Acceptance Criteria

1. `sql "SELECT * FROM crm_store"` outputs valid JSON array of records.
2. `sql --format table "SELECT key, metadata FROM crm_store"` formats output as clean ASCII grid.
3. `sql -f csv "SELECT key FROM crm_store"` outputs CSV with column header.
4. Mutation queries (`INSERT`, `UPDATE`, `DELETE`, `CREATE TABLE`) execute cleanly and return rows affected.
5. Error queries (e.g. syntax errors or nonexistent tables) report clear error message and non-zero status without crashing.
6. Unit tests and integration test suite verify the `sql` command across all formats.
