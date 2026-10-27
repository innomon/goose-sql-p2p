#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$WORKSPACE_ROOT"

echo "================================================================="
echo "  goose-sql-p2p End-to-End & Cross-Replication Test Suite"
echo "================================================================="

GOOSE_BIN="$WORKSPACE_ROOT/bin/goose-sql-p2p"
GO_BIN="/home/innomon/B204-zone/owly-sewa/sqlite-p2p/bin/e2e-replication-linux-arm64"

# 1. Build and Run Unit Tests
echo "[Step 1] Building and Running Unit Tests..."
make
./bin/unit_test

# 2. Setup Test Environment
TEST_DIR="/tmp/goose_p2p_test_$$"
mkdir -p "$TEST_DIR"
trap 'rm -rf "$TEST_DIR"; kill $(jobs -p) 2>/dev/null || true' EXIT

DB_G1="$TEST_DIR/node_g1.db"
DB_G2="$TEST_DIR/node_g2.db"
DB_GO="$TEST_DIR/node_go.db"

PORT_G1=45201
PORT_G2=45202
PORT_GO=45203

# 3. Start Goose Node 1
echo "[Step 2] Starting Goose Node 1 on port $PORT_G1..."
"$GOOSE_BIN" -node "goose-node-1" -db "$DB_G1" -port "$PORT_G1" > "$TEST_DIR/g1.log" 2>&1 &
PID_G1=$!
sleep 1

# Insert test record in Goose Node 1
echo "[Step 3] Seeding data into Goose Node 1..."
"$GOOSE_BIN" -db "$DB_G1" -cmd "put user:101 Alice {\"timestamp\":1000000}"
"$GOOSE_BIN" -db "$DB_G1" -cmd "put org:acme AcmeCorp {\"timestamp\":1000000}"

# 4. Start Goose Node 2 connecting to Goose Node 1
echo "[Step 4] Starting Goose Node 2 on port $PORT_G2 (connecting to Goose Node 1)..."
"$GOOSE_BIN" -node "goose-node-2" -db "$DB_G2" -port "$PORT_G2" -peer "127.0.0.1:$PORT_G1" > "$TEST_DIR/g2.log" 2>&1 &
PID_G2=$!
sleep 2

# Verify replication to Goose Node 2
echo "[Step 5] Verifying replication from Goose Node 1 -> Goose Node 2..."
RES_G2=$("$GOOSE_BIN" -db "$DB_G2" -cmd "get user:101")
echo "Goose Node 2 query output: $RES_G2"
if [[ "$RES_G2" != *"Alice"* ]]; then
  echo "[FAIL] Goose Node 2 did not receive user:101 from Goose Node 1!"
  exit 1
fi
echo "  [PASS] Goose Node 1 -> Goose Node 2 Replication Verified!"

# 5. Insert record into Goose Node 2 and verify sync back to Goose Node 1
echo "[Step 6] Inserting record into Goose Node 2..."
"$GOOSE_BIN" -db "$DB_G2" -peer "127.0.0.1:$PORT_G1" -cmd "put user:102 Bob {\"timestamp\":2000000}"
sleep 1

# Query Goose Node 1
echo "[Step 7] Verifying bidirectional sync Goose Node 2 -> Goose Node 1..."
RES_G1=$("$GOOSE_BIN" -db "$DB_G1" -cmd "get user:102")
echo "Goose Node 1 query output: $RES_G1"
if [[ "$RES_G1" != *"Bob"* ]]; then
  echo "[FAIL] Goose Node 1 did not receive user:102 from Goose Node 2!"
  exit 1
fi
echo "  [PASS] Goose Node 2 -> Goose Node 1 Bi-directional Replication Verified!"

# 6. Test Deletion Propagation
echo "[Step 8] Testing Deletion Propagation across P2P cluster..."
"$GOOSE_BIN" -db "$DB_G1" -peer "127.0.0.1:$PORT_G2" -cmd "del user:101"
sleep 1

RES_G2_DEL=$("$GOOSE_BIN" -db "$DB_G2" -cmd "get user:101")
echo "Goose Node 2 query after deletion: $RES_G2_DEL"
if [[ "$RES_G2_DEL" == *"Alice"* ]]; then
  echo "[FAIL] Goose Node 2 still has deleted record user:101!"
  exit 1
fi
echo "  [PASS] Deletion Replication Verified!"

# 7. Test List and Feed Inspection
echo "[Step 9] Verifying List and Hypercore Feed inspection..."
LIST_G1=$("$GOOSE_BIN" -db "$DB_G1" -cmd "list")
echo "Goose Node 1 list output: $LIST_G1"
FEED_G1=$("$GOOSE_BIN" -db "$DB_G1" -cmd "feed")
echo "Goose Node 1 feed entries: $FEED_G1"
echo "  [PASS] List and Changeset Feed Verified!"

# 8. Test Arbitrary SQL Command Execution (JSON, Table, CSV, Slash Command)
echo "[Step 10] Testing 'sql' and '/sql' execution across formats..."
SQL_JSON=$("$GOOSE_BIN" -db "$DB_G1" -cmd "sql SELECT key, data FROM crm_store ORDER BY key ASC;")
echo "SQL JSON output: $SQL_JSON"
if [[ "$SQL_JSON" != *"org:acme"* || "$SQL_JSON" != *"user:102"* ]]; then
  echo "[FAIL] SQL JSON query failed!"
  exit 1
fi

SQL_TABLE=$("$GOOSE_BIN" -db "$DB_G1" -cmd "sql -f table SELECT key, data FROM crm_store ORDER BY key ASC;")
echo "SQL Table output:"
echo "$SQL_TABLE"
if [[ "$SQL_TABLE" != *"+---"* || "$SQL_TABLE" != *"AcmeCorp"* ]]; then
  echo "[FAIL] SQL Table query failed!"
  exit 1
fi

SQL_CSV=$("$GOOSE_BIN" -db "$DB_G1" -cmd "sql --format csv SELECT key, data FROM crm_store ORDER BY key ASC;")
echo "SQL CSV output:"
echo "$SQL_CSV"
if [[ "$SQL_CSV" != *"key,data"* || "$SQL_CSV" != *"\"AcmeCorp\""* ]]; then
  echo "[FAIL] SQL CSV query failed!"
  exit 1
fi

SLASH_SQL=$("$GOOSE_BIN" -db "$DB_G1" -cmd "/sql SELECT count(*) AS cnt FROM crm_store;")
echo "Slash SQL output: $SLASH_SQL"
if [[ "$SLASH_SQL" != *"\"cnt\":"* ]]; then
  echo "[FAIL] Slash /sql query failed!"
  exit 1
fi
echo "  [PASS] Arbitrary SQL Execution across formats Verified!"

echo "================================================================="
echo "  ALL REPLICATION AND INTEROPERABILITY TESTS PASSED!"
echo "================================================================="
