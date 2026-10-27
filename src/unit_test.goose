// Unit test suite for goose-sql-p2p core engine
import std;
import types;
import db;
import crypto;
import json_util;
import changeset;
import feed;
import replicator;
import cli;
import mcp;

fn str_contains(haystack: const u8[:], needle: const u8[:]) -> bool {
    find(haystack, needle) >= 0
}

fn main() {
    print("=== Running goose-sql-p2p Unit Tests ===");

    // 1. Test Crypto Primitives
    print("[TEST 1] Testing Cryptography Primitives...");
    var k = crypto::generate_key();
    assert(k.len > 0);

    var plain = "Hello SQLite P2P World!";
    var cipher = crypto::encrypt(k, plain);
    assert(cipher.len > 0);

    var decrypted = crypto::decrypt(k, cipher);
    assert(decrypted == plain);

    var hash = crypto::sha256("test-data");
    assert(hash.len == 64);

    var b32 = crypto::base32_encode("sqlite-p2p");
    assert(b32.len > 0);
    print("  [PASS] Cryptography Primitives (AES-256-GCM, SHA-256, Base32)");

    // 2. Test JSON Utilities
    print("[TEST 2] Testing JSON Utilities...");
    var sample_json = "{\"node_id\":\"node-test-1\",\"swarm_port\":43219,\"enable_wal\":true,\"bootstrap\":[\"127.0.0.1:4001\",\"127.0.0.1:4002\"]}";
    var nid: u8[>..] = [];
    assert(json_util::find_string_field(sample_json, "node_id", nid));
    assert(nid == "node-test-1");

    var port = json_util::find_int_field(sample_json, "swarm_port", 0);
    assert(port == 43219);

    var wal = json_util::find_bool_field(sample_json, "enable_wal", false);
    assert(wal == true);

    var boot_arr: u8[..128][>..] = [];
    json_util::find_string_array(sample_json, "bootstrap", boot_arr);
    assert(boot_arr.len == 2);
    assert(boot_arr[0] == "127.0.0.1:4001");
    assert(boot_arr[1] == "127.0.0.1:4002");
    print("  [PASS] JSON Extraction and Formatting");

    // 3. Test SQLite Storage Engine
    print("[TEST 3] Testing SQLite Storage Engine...");
    var test_db_path = ":memory:";
    var db_handle = db::open(test_db_path, true);
    assert(db_handle != 0);

    db::init_feed_table(db_handle);

    var put_ok = db::put(db_handle, "test:key:1", "{\"version\":1}", "Sample Payload Data");
    assert(put_ok);

    var meta_out: u8[>..] = [];
    var data_out: u8[>..] = [];
    var get_ok = db::get(db_handle, "test:key:1", meta_out, data_out);
    assert(get_ok);
    assert(data_out == "Sample Payload Data");

    var list_json: u8[>..] = [];
    var list_ok = db::list(db_handle, "test:key:", 10, 0, list_json);
    assert(list_ok);
    assert(list_json.len > 0);

    var del_ok = db::delete_key(db_handle, "test:key:1");
    assert(del_ok);

    var meta_del: u8[>..] = [];
    var data_del: u8[>..] = [];
    var get_del = db::get(db_handle, "test:key:1", meta_del, data_del);
    assert(!get_del);
    print("  [PASS] SQLite Put, Get, Delete, List, and WAL Schema");

    // 4. Test Changeset Encoding & LWW Conflict Resolution
    print("[TEST 4] Testing Changeset & LWW Consensus...");
    var cs = changeset::make_changeset(1, "crm:customer:100", "{\"timestamp\":1000}", "Alice Smith", 1000, 1);
    var encoded: u8[>..] = [];
    changeset::encode(cs, encoded);
    assert(encoded.len > 0);

    var decoded = types::Changeset {
        timestamp: 0,
        seq: 0,
        op: 1,
        key: [],
        metadata: [],
        prev_hash: [],
        data: []
    };
    var dec_ok = changeset::decode(encoded, decoded);
    assert(dec_ok);
    assert(decoded.key == "crm:customer:100");
    assert(decoded.timestamp == 1000);
    assert(decoded.data == "Alice Smith");

    // Apply changeset to database
    var apply_ok = changeset::apply_lww(db_handle, decoded);
    assert(apply_ok);

    var meta_chk: u8[>..] = [];
    var data_chk: u8[>..] = [];
    var g_ok = db::get(db_handle, "crm:customer:100", meta_chk, data_chk);
    assert(g_ok);
    assert(data_chk == "Alice Smith");

    // Test LWW: Older changeset should not overwrite newer data
    var older_cs = changeset::make_changeset(2, "crm:customer:100", "{\"timestamp\":500}", "Alice Stale", 500, 2);
    changeset::apply_lww(db_handle, older_cs);

    var meta_stale: u8[>..] = [];
    var data_stale: u8[>..] = [];
    db::get(db_handle, "crm:customer:100", meta_stale, data_stale);
    assert(data_stale == "Alice Smith"); // Unchanged!

    // Test LWW: Newer changeset should overwrite
    var newer_cs = changeset::make_changeset(2, "crm:customer:100", "{\"timestamp\":2000}", "Alice Updated", 2000, 3);
    changeset::apply_lww(db_handle, newer_cs);

    var meta_new: u8[>..] = [];
    var data_new: u8[>..] = [];
    db::get(db_handle, "crm:customer:100", meta_new, data_new);
    assert(data_new == "Alice Updated");
    print("  [PASS] Changeset Serialization & Autobase LWW Resolution");

    // 5. Test Hypercore Feed Log
    print("[TEST 5] Testing Hypercore-compatible Changeset Feed...");
    var feed_cs = types::Changeset {
        timestamp: 0,
        seq: 0,
        op: 1,
        key: [],
        metadata: [],
        prev_hash: [],
        data: []
    };
    var append_ok = feed::append_changeset(db_handle, 1, "doc:1", "{}", "Doc Content", 3000, feed_cs);
    assert(append_ok);
    assert(feed_cs.prev_hash.len == 64);
    print("  [PASS] Changeset Feed Append and SHA-256 Log Hashing");

    // 6. Test Raw SQL Query Engine (JSON, Table, CSV, DDL/DML, Errors)
    print("[TEST 6] Testing Arbitrary SQL Execution Engine...");
    var sql_res: u8[>..] = [];

    // 6a. DDL CREATE TABLE
    sql_res.clear();
    var ddl_ok = db::query_raw(db_handle, "CREATE TABLE sql_test_items (id INT, name TEXT, score REAL);", "json", sql_res);
    assert(ddl_ok);
    assert(sql_res == "{\"status\":\"ok\",\"rows_affected\":0}");

    // 6b. DML INSERT
    sql_res.clear();
    var ins_ok = db::query_raw(db_handle, "INSERT INTO sql_test_items VALUES (1, 'Alice', 95.5), (2, 'Bob', 88.0);", "json", sql_res);
    assert(ins_ok);
    assert(sql_res == "{\"status\":\"ok\",\"rows_affected\":2}");

    // 6c. JSON format SELECT
    sql_res.clear();
    var q_json_ok = db::query_raw(db_handle, "SELECT id, name, score FROM sql_test_items ORDER BY id ASC;", "json", sql_res);
    assert(q_json_ok);
    assert(sql_res == "[{\"id\":1,\"name\":\"Alice\",\"score\":95.5},{\"id\":2,\"name\":\"Bob\",\"score\":88}]");

    // 6d. ASCII Table format SELECT
    sql_res.clear();
    var q_tbl_ok = db::query_raw(db_handle, "SELECT id, name, score FROM sql_test_items ORDER BY id ASC;", "table", sql_res);
    assert(q_tbl_ok);
    assert(sql_res.len > 0);

    // 6e. CSV format SELECT
    sql_res.clear();
    var q_csv_ok = db::query_raw(db_handle, "SELECT id, name, score FROM sql_test_items ORDER BY id ASC;", "csv", sql_res);
    assert(q_csv_ok);
    assert(sql_res == "id,name,score\n1,\"Alice\",95.5\n2,\"Bob\",88\n");

    // 6f. SQL Error handling
    sql_res.clear();
    var q_err_ok = db::query_raw(db_handle, "SELECT * FROM missing_table_123;", "json", sql_res);
    assert(!q_err_ok);
    assert(sql_res == "{\"status\":\"error\",\"error\":\"no such table: missing_table_123\"}");

    print("  [PASS] SQL Query Engine (JSON, Table, CSV, DDL/DML, Error Handling)");

    // 7. Test Model Context Protocol (MCP) Server Handler
    print("[TEST 7] Testing Model Context Protocol (MCP) Server Handler...");
    var mcp_cfg = types::NodeConfig {
        id: "mcp-test-node",
        name: "MCP Test Node",
        db_path: "data/unit_test.db",
        wal: true,
        replication_port: 0,
        swarm_topic: "test-topic",
        key_registry_path: "",
        encryption_key: "",
        enable_crypto: false,
        sync_interval_sec: 2,
        auto_sync: true,
        mcp_mode: true
    };
    var mcp_rep = replicator::init_replicator(db_handle, 0);
    var mcp_ctx = cli::AppContext {
        cfg: mcp_cfg,
        db_handle: db_handle,
        rep: mcp_rep,
        should_exit: false
    };

    var mcp_resp: u8[>..] = [];

    // 7a. initialize
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\"}}", mcp_resp));
    assert(str_contains(mcp_resp, "\"protocolVersion\":\"2024-11-05\""));
    assert(str_contains(mcp_resp, "\"name\":\"goose-sql-p2p\""));

    // 7b. ping
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}", mcp_resp));
    assert(mcp_resp == "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}");

    // 7c. tools/list
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\"}", mcp_resp));
    assert(str_contains(mcp_resp, "\"name\":\"sql\""));
    assert(str_contains(mcp_resp, "\"name\":\"put\""));
    assert(str_contains(mcp_resp, "\"name\":\"get\""));
    assert(str_contains(mcp_resp, "\"name\":\"del\""));
    assert(str_contains(mcp_resp, "\"name\":\"list\""));
    assert(str_contains(mcp_resp, "\"name\":\"sync\""));
    assert(str_contains(mcp_resp, "\"name\":\"peers\""));
    assert(str_contains(mcp_resp, "\"name\":\"feed\""));
    assert(str_contains(mcp_resp, "\"name\":\"status\""));

    // 7d. tools/call sql
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"sql\",\"arguments\":{\"query\":\"SELECT 42 as answer;\",\"format\":\"json\"}}}", mcp_resp));
    assert(str_contains(mcp_resp, "[{\\\"answer\\\":42}]"));

    // 7e. tools/call put
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"put\",\"arguments\":{\"key\":\"mcp_crm_1\",\"data\":\"{\\\"name\\\":\\\"Acme Corp\\\"}\"}}}", mcp_resp));
    assert(str_contains(mcp_resp, "OK put mcp_crm_1"));

    // 7f. tools/call get
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"get\",\"arguments\":{\"key\":\"mcp_crm_1\"}}}", mcp_resp));
    assert(str_contains(mcp_resp, "Acme Corp"));

    // 7g. tools/call status
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"status\"}}", mcp_resp));
    assert(str_contains(mcp_resp, "mcp-test-node"));

    // 7h. resources/list
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"resources/list\"}", mcp_resp));
    assert(str_contains(mcp_resp, "sqlite://crm_store"));
    assert(str_contains(mcp_resp, "sqlite://feed"));

    // 7i. resources/read
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"resources/read\",\"params\":{\"uri\":\"sqlite://status\"}}", mcp_resp));
    assert(str_contains(mcp_resp, "mcp-test-node"));

    // 7j. prompts/list
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"prompts/list\"}", mcp_resp));
    assert(str_contains(mcp_resp, "p2p_sync_diagnostic"));
    assert(str_contains(mcp_resp, "sql_data_analyst"));

    // 7k. prompts/get
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"prompts/get\",\"params\":{\"name\":\"sql_data_analyst\",\"arguments\":{\"focus\":\"crm_revenue\"}}}", mcp_resp));
    assert(str_contains(mcp_resp, "SELECT * FROM crm_store"));

    // 7l. error on unknown method
    mcp_resp.clear();
    assert(mcp::handle_request(mcp_ctx, "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"unknown/method\"}", mcp_resp));
    assert(str_contains(mcp_resp, "\"code\":-32601"));

    print("  [PASS] Model Context Protocol (MCP) Server (Initialize, Tools, Resources, Prompts, Error Handling)");

    db::close(db_handle);

    print("=== ALL UNIT TESTS PASSED SUCCESSFULLY! ===");
}
