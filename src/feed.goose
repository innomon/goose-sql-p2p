// Hypercore-compatible append-only changeset feed log
namespace feed;

import std;
import types;
import crypto;
import db;
import json_util;
import changeset;

fn append_changeset(handle: u64, op: i32, key: const u8[:], meta: const u8[:], data: const u8[:], timestamp: i64, out_cs: types::Changeset&) -> bool {
    if handle == 0 {
        return false;
    }

    var effective_meta: u8[>..] = [];
    if meta.len == 0 {
        effective_meta.append("{}");
    } else {
        effective_meta.append(meta);
    }

    // Build hash over (timestamp, op, key, meta, data)
    var hash_input: u8[>..] = [];
    format(hash_input, timestamp, ":", op, ":", key, ":", effective_meta, ":", data);
    var h = crypto::sha256(hash_input);

    var sql: u8[>..] = [];
    sql.append("INSERT INTO changeset_feed (timestamp, op, key, metadata, data, prev_hash, hash) VALUES (");
    format(sql, timestamp);
    sql.append(", ");
    format(sql, op);
    sql.append(", '");
    json_util::escape_string(sql, key);
    sql.append("', '");
    json_util::escape_string(sql, effective_meta);
    sql.append("', '");
    json_util::escape_string(sql, data);
    sql.append("', '', '");
    sql.append(h);
    sql.append("');");

    var ok = db::exec(handle, sql);
    if !ok {
        return false;
    }

    out_cs.timestamp = timestamp;
    out_cs.op = op;
    out_cs.key.clear();
    out_cs.key.append(key);
    out_cs.metadata.clear();
    out_cs.metadata.append(effective_meta);
    out_cs.data.clear();
    out_cs.data.append(data);
    out_cs.prev_hash.clear();
    out_cs.prev_hash.append(h);

    return true;
}

fn fetch_all_changesets(handle: u64, out_json: u8[>..]&) -> bool {
    if handle == 0 {
        return false;
    }
    // Query changeset_feed using db_list or custom query
    var json_out: u8[>..] = [];
    var ok = db::list(handle, "", 1000, 0, json_out);
    out_json.append(json_out);
    return ok;
}
