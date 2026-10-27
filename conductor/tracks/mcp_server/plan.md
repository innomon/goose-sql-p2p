# Implementation Plan: Model Context Protocol (MCP) Server over STDIO (`mcp_server`)

## Phase 1: STDIO Line Reader & JSON-RPC 2.0 Parser / Formatter
- [x] Task: Implement STDIO line reader in C bridge / Goose (`gs_stdio_readline`) and ensure diagnostic logging routes to `stderr`
- [x] Task: Implement JSON-RPC 2.0 request parser, response builder, and error code handler (`src/mcp.goose`)
- [x] Task: Implement protocol lifecycle methods (`initialize`, `notifications/initialized`, `ping`)
- [x] Task: Conductor - User Manual Verification 'Phase 1: STDIO Line Reader & JSON-RPC 2.0 Parser / Formatter' (Protocol in workflow.md)

## Phase 2: MCP Tool Registry, Resources & Prompts Dispatcher
- [x] Task: Implement `tools/list` returning JSON Schema definitions for all interactive/slash commands (`sql`, `put`, `get`, `del`, `list`, `sync`, `peers`, `feed`, `status`)
- [x] Task: Implement `tools/call` handler executing tools against `db`, `feed`, and `replicator` state
- [x] Task: Implement `resources/list` and `resources/read` for `sqlite://crm_store`, `sqlite://feed`, `sqlite://status`
- [x] Task: Implement `prompts/list` and `prompts/get` for `p2p_sync_diagnostic` and `sql_data_analyst`
- [x] Task: Conductor - User Manual Verification 'Phase 2: MCP Tool Registry, Resources & Prompts Dispatcher' (Protocol in workflow.md)

## Phase 3: CLI Integration, Main Loop & Stdio Mode Wiring
- [x] Task: Add `-mcp` CLI argument parsing in `src/config.goose` and `mcp` command in `src/cli.goose`
- [x] Task: Wire MCP STDIO server event loop in `src/main.goose`
- [x] Task: Conductor - User Manual Verification 'Phase 3: CLI Integration, Main Loop & Stdio Mode Wiring' (Protocol in workflow.md)

## Phase 4: Unit Testing, STDIO Verification & Documentation
- [x] Task: Add MCP protocol & tool execution unit tests in `src/unit_test.goose`
- [x] Task: Create automated STDIO integration test script `scripts/mcp-test.sh` verifying end-to-end MCP JSON-RPC workflows
- [x] Task: Update `scripts/cross-replication-test.sh` and `Makefile` with MCP test targets
- [x] Task: Document MCP server usage and AI client configuration in `README.md` and `ARCHITECTURE.md`
- [x] Task: Conductor - User Manual Verification 'Phase 4: Unit Testing, STDIO Verification & Documentation' (Protocol in workflow.md)
