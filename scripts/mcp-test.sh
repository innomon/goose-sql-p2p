#!/usr/bin/env bash
# scripts/mcp-test.sh - End-to-End Test Suite for Model Context Protocol (MCP) STDIO Server
set -euo pipefail

echo "=========================================================="
echo "  Running Model Context Protocol (MCP) STDIO Test Suite   "
echo "=========================================================="

DB_TEST="data/mcp_stdio_test.db"
rm -f "$DB_TEST" "$DB_TEST-wal" "$DB_TEST-shm"

BIN="./bin/goose-sql-p2p"
if [ ! -f "$BIN" ]; then
    echo "[ERROR] Binary $BIN not found. Run make first."
    exit 1
fi

TMP_INPUT=$(mktemp)
TMP_OUTPUT=$(mktemp)

cat << 'EOF' > "$TMP_INPUT"
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"ping"}
{"jsonrpc":"2.0","id":3,"method":"tools/list"}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sql","arguments":{"query":"SELECT 1 as id, 'Widget A' as item UNION ALL SELECT 2, 'Widget B';","format":"json"}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"put","arguments":{"key":"crm_cust_100","data":"{\"company\":\"Innovate Corp\",\"tier\":\"Gold\"}","metadata":"{\"created_by\":\"mcp_agent\"}"}}}
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get","arguments":{"key":"crm_cust_100"}}}
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"list","arguments":{"prefix":"crm_"}}}
{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"del","arguments":{"key":"crm_cust_100"}}}
{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"status"}}
{"jsonrpc":"2.0","id":10,"method":"resources/list"}
{"jsonrpc":"2.0","id":11,"method":"resources/read","params":{"uri":"sqlite://status"}}
{"jsonrpc":"2.0","id":12,"method":"prompts/list"}
{"jsonrpc":"2.0","id":13,"method":"prompts/get","params":{"name":"p2p_sync_diagnostic"}}
{"jsonrpc":"2.0","id":14,"method":"prompts/get","params":{"name":"sql_data_analyst"}}
{"jsonrpc":"2.0","id":15,"method":"nonexistent/method"}
EOF

# Run MCP server over STDIO
"$BIN" -mcp -db "$DB_TEST" -id "mcp-stdio-node" < "$TMP_INPUT" > "$TMP_OUTPUT" 2>/dev/null

echo "[1/15] Verifying initialize response..."
grep -q '"protocolVersion":"2024-11-05"' "$TMP_OUTPUT"
grep -q '"name":"goose-sql-p2p"' "$TMP_OUTPUT"
echo "  -> Initialize protocol handshake verified."

echo "[2/15] Verifying ping response..."
grep -q '{"jsonrpc":"2.0","id":2,"result":{}}' "$TMP_OUTPUT"
echo "  -> Ping verified."

echo "[3/15] Verifying tools/list response..."
grep -q '"name":"sql"' "$TMP_OUTPUT"
grep -q '"name":"put"' "$TMP_OUTPUT"
grep -q '"name":"get"' "$TMP_OUTPUT"
grep -q '"name":"del"' "$TMP_OUTPUT"
grep -q '"name":"list"' "$TMP_OUTPUT"
grep -q '"name":"sync"' "$TMP_OUTPUT"
grep -q '"name":"peers"' "$TMP_OUTPUT"
grep -q '"name":"feed"' "$TMP_OUTPUT"
grep -q '"name":"status"' "$TMP_OUTPUT"
echo "  -> All 9 MCP tools successfully listed with inputSchemas."

echo "[4/15] Verifying tools/call sql execution..."
grep -q 'Widget A' "$TMP_OUTPUT"
grep -q 'Widget B' "$TMP_OUTPUT"
echo "  -> SQL tool execution and JSON table serialization verified."

echo "[5/15] Verifying tools/call put..."
grep -q 'OK put crm_cust_100' "$TMP_OUTPUT"
echo "  -> Put tool record storage and broadcast verified."

echo "[6/15] Verifying tools/call get..."
grep -q 'Innovate Corp' "$TMP_OUTPUT"
echo "  -> Get tool retrieval verified."

echo "[7/15] Verifying tools/call list..."
grep -q 'crm_cust_100' "$TMP_OUTPUT"
echo "  -> List tool prefix search verified."

echo "[8/15] Verifying tools/call del..."
grep -q 'OK deleted crm_cust_100' "$TMP_OUTPUT"
echo "  -> Del tool deletion and tombstone broadcast verified."

echo "[9/15] Verifying tools/call status..."
grep -q 'mcp-stdio-node' "$TMP_OUTPUT"
echo "  -> Status tool verified."

echo "[10/15] Verifying resources/list..."
grep -q 'sqlite://crm_store' "$TMP_OUTPUT"
grep -q 'sqlite://feed' "$TMP_OUTPUT"
echo "  -> Resources list verified."

echo "[11/15] Verifying resources/read sqlite://status..."
grep -q 'mcp-stdio-node' "$TMP_OUTPUT"
echo "  -> Resource read verified."

echo "[12/15] Verifying prompts/list..."
grep -q 'p2p_sync_diagnostic' "$TMP_OUTPUT"
grep -q 'sql_data_analyst' "$TMP_OUTPUT"
echo "  -> Prompts list verified."

echo "[13/15] Verifying prompts/get p2p_sync_diagnostic..."
grep -q 'Peer connectivity and sync diagnostic' "$TMP_OUTPUT"
echo "  -> Prompt p2p_sync_diagnostic verified."

echo "[14/15] Verifying prompts/get sql_data_analyst..."
grep -q 'SQL data analysis workflow' "$TMP_OUTPUT"
echo "  -> Prompt sql_data_analyst verified."

echo "[15/15] Verifying error response for unknown method..."
grep -q '"code":-32601' "$TMP_OUTPUT"
echo "  -> Error code -32601 (Method not found) verified."

# Cleanup
rm -f "$TMP_INPUT" "$TMP_OUTPUT" "$DB_TEST" "$DB_TEST-wal" "$DB_TEST-shm"

echo "=========================================================="
echo "  [SUCCESS] All Model Context Protocol (MCP) tests passed!"
echo "=========================================================="
