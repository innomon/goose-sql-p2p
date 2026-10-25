// Unit test suite for goose-sql-p2p core engine
import std;
import types from "../src/types";
import db from "../src/db";
import crypto from "../src/crypto";
import json_util from "../src/json_util";
import changeset from "../src/changeset";
import feed from "../src/feed";

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
    var test_db_path = "data/test_unit.db";
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
    assert(db::get(db_handle, "crm:customer:100", meta_chk, data_chk));
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

    db::close(db_handle);
    print("  [PASS] Changeset Feed Append and SHA-256 Log Hashing");

    print("=== ALL UNIT TESTS PASSED SUCCESSFULLY! ===");
}
