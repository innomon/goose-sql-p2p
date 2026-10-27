# Specification: Model Context Protocol (MCP) Server over STDIO (`mcp_server`)

## 1. Overview
Implement a native Model Context Protocol (MCP) server over STDIO in the Goose language for `goose-sql-p2p`, allowing LLMs and AI agents (such as Claude Desktop, Antigravity, Cursor, and custom MCP clients) to seamlessly interact with the local SQLite database and Pear P2P replication cluster.

All interactive and slash commands (`sql`, `put`, `get`, `del`, `list`, `sync`, `peers`, `feed`, `status`) will be exposed as standardized MCP Tools with complete JSON Schema parameter definitions. In addition, MCP Resources and Prompts will be provided for direct state inspection and assisted workflows.

## 2. Invocation & STDIO Transport
- **CLI Invocations**:
  - `bin/goose-sql-p2p -mcp [-db <path>] [-port <port>] [-node <id>] [-peer <peer>] [-config <path>]`
  - Subcommand: `bin/goose-sql-p2p mcp`
- **Transport & Framing**:
  - Standard Model Context Protocol JSON-RPC 2.0 over standard input / standard output (STDIO).
  - Uses newline-delimited (`\n`) JSON-RPC messages.
  - Standard output (`stdout`) is strictly reserved for JSON-RPC messages.
  - All node runtime logs and diagnostics are directed to standard error (`stderr`) to prevent protocol corruption.

## 3. Protocol Lifecycle & Methods
Conforms to MCP protocol version `2024-11-05`:
- `initialize`: Returns server capabilities (tools, resources, prompts) and server info (`goose-sql-p2p`, version `0.1.0`).
- `notifications/initialized`: Confirms client readiness.
- `ping`: Standard keep-alive response `{}`.
- `tools/list`: Lists all available tools with parameter JSON schemas.
- `tools/call`: Executes specified tool against local SQLite engine / P2P replicator and returns `content: [{type: "text", text: "..."}]`.
- `resources/list` & `resources/read`: Direct URI-based access to `crm_store` records and changeset logs.
- `prompts/list` & `prompts/get`: Built-in templates for cluster sync and SQL analysis.

## 4. MCP Tools Registry (Exposing All Commands)
1. `sql`: Execute arbitrary SQL queries (SELECT, DDL, DML) with selectable output format (`json`, `table`, `csv`).
   - Arguments: `query` (string, required), `format` (string enum: `json`, `table`, `csv`, default `json`).
2. `put`: Store key-value record with metadata and broadcast mutation across P2P swarm.
   - Arguments: `key` (string, required), `data` (string, required), `metadata` (string, optional).
3. `get`: Retrieve record payload and metadata by key.
   - Arguments: `key` (string, required).
4. `del`: Delete record by key, write tombstone to feed, and broadcast to swarm.
   - Arguments: `key` (string, required).
5. `list`: List records matching optional key prefix.
   - Arguments: `prefix` (string, optional).
6. `sync`: Trigger immediate bidirectional replication sync across all connected peers.
   - Arguments: none.
7. `peers`: Inspect active peer connections and cluster status.
   - Arguments: none.
8. `feed`: View local Hypercore append-only changeset feed with rolling SHA-256 hashes.
   - Arguments: none.
9. `status`: Retrieve node status, WAL mode, swarm topic, and port configuration.
   - Arguments: none.

## 5. MCP Resources & Prompts
- **Resources**:
  - `sqlite://crm_store`: Complete listing of local key-value store.
  - `sqlite://crm_store/{key}`: Resource content for specific record.
  - `sqlite://feed`: Append-only changeset log records.
  - `sqlite://status`: Node metadata and network state.
- **Prompts**:
  - `p2p_sync_diagnostic`: Prompts LLM to analyze peer connectivity and synchronization status.
  - `sql_data_analyst`: Contextual prompt with database schemas and sample queries for analytical workflows.

## 6. Acceptance Criteria
- Running `goose-sql-p2p -mcp` launches a headless JSON-RPC 2.0 loop reading from `stdin` and writing to `stdout`.
- Passes standard MCP protocol handshake (`initialize` -> `notifications/initialized`).
- All tools execute properly and return structured text/JSON blocks with `isError: false` on success and `isError: true` on failure.
- Unit tests in `bin/unit_test` and E2E scripted STDIO tests verify protocol framing, tools execution, resources, and error recovery.
