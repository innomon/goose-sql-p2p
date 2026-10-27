# Implementation Plan: Model Context Protocol (MCP) Server over STDIO (`mcp_server`)

## Phase 1: STDIO Line Reader & JSON-RPC 2.0 Parser / Formatter
- [ ] Task: Implement STDIO line reader in C bridge / Goose (`gs_stdio_readline`) and ensure diagnostic logging routes to `stderr`
- [ ] Task: Implement JSON-RPC 2.0 request parser, response builder, and error code handler (`src/mcp.goose`)
- [ ] Task: Implement protocol lifecycle methods (`initialize`, `notifications/initialized`, `ping`)
- [ ] Task: Conductor - User Manual Verification 'Phase 1: STDIO Line Reader & JSON-RPC 2.0 Parser / Formatter' (Protocol in workflow.md)

## Phase 2: MCP Tool Registry, Resources & Prompts Dispatcher
- [ ] Task: Implement `tools/list` returning JSON Schema definitions for all interactive/slash commands (`sql`, `put`, `get`, `del`, `list`, `sync`, `peers`, `feed`, `status`)
- [ ] Task: Implement `tools/call` handler executing tools against `db`, `feed`, and `replicator` state
- [ ] Task: Implement `resources/list` and `resources/read` for `sqlite://crm_store`, `sqlite://feed`, `sqlite://status`
- [ ] Task: Implement `prompts/list` and `prompts/get` for `p2p_sync_diagnostic` and `sql_data_analyst`
- [ ] Task: Conductor - User Manual Verification 'Phase 2: MCP Tool Registry, Resources & Prompts Dispatcher' (Protocol in workflow.md)

## Phase 3: CLI Integration, Main Loop & Stdio Mode Wiring
- [ ] Task: Add `-mcp` CLI argument parsing in `src/config.goose` and `mcp` command in `src/cli.goose`
- [ ] Task: Wire MCP STDIO server event loop in `src/main.goose`
- [ ] Task: Conductor - User Manual Verification 'Phase 3: CLI Integration, Main Loop & Stdio Mode Wiring' (Protocol in workflow.md)

## Phase 4: Unit Testing, STDIO Verification & Documentation
- [ ] Task: Add MCP protocol & tool execution unit tests in `src/unit_test.goose`
- [ ] Task: Create automated STDIO integration test script `scripts/mcp-test.sh` verifying end-to-end MCP JSON-RPC workflows
- [ ] Task: Update `scripts/cross-replication-test.sh` and `Makefile` with MCP test targets
- [ ] Task: Document MCP server usage and AI client configuration in `README.md` and `ARCHITECTURE.md`
- [ ] Task: Conductor - User Manual Verification 'Phase 4: Unit Testing, STDIO Verification & Documentation' (Protocol in workflow.md)
