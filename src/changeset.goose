// Changeset definition, serialization and LWW conflict resolution
namespace changeset;

import std;
import types;
import json_util;
import db;

fn make_changeset(op: i32, key: const u8[:], meta: const u8[:], data: const u8[:], timestamp: i64, seq: u64) -> types::Changeset {
    var cs = types::Changeset {
        timestamp: timestamp,
        seq: seq,
        op: op,
        key: [],
        metadata: [],
        prev_hash: [],
        data: []
    };
    cs.key.append(key);
    if meta.len == 0 {
        cs.metadata.append("{}");
    } else {
        cs.metadata.append(meta);
    }
    cs.data.append(data);
    return cs;
}

fn encode(cs: types::Changeset, out: u8[>..]&) {
    out.append("{\"timestamp\":");
    format(out, cs.timestamp);
    out.append(",\"seq\":");
    format(out, cs.seq);
    out.append(",\"op\":");
    format(out, cs.op);
    out.append(",\"key\":\"");
    json_util::escape_string(out, cs.key);
    out.append("\",\"metadata\":");
    if cs.metadata.len > 0 && cs.metadata[0] == '{' {
        out.append(cs.metadata);
    } else if cs.metadata.len > 0 {
        out.push('"');
        json_util::escape_string(out, cs.metadata);
        out.push('"');
    } else {
        out.append("{}");
    }
    out.append(",\"data\":\"");
    json_util::escape_string(out, cs.data);
    out.append("\",\"prev_hash\":\"");
    json_util::escape_string(out, cs.prev_hash);
    out.append("\"}");
}

fn decode(json_str: const u8[:], out: types::Changeset&) -> bool {
    out.timestamp = json_util::find_int_field(json_str, "timestamp", 0);
    out.seq = json_util::find_int_field(json_str, "seq", 0) as u64;
    out.op = json_util::find_int_field(json_str, "op", 1) as i32;

    out.key.clear();
    var key_buf: u8[>..] = [];
    json_util::find_string_field(json_str, "key", key_buf);
    out.key.append(key_buf);

    out.metadata.clear();
    var meta_buf: u8[>..] = [];
    json_util::find_string_field(json_str, "metadata", meta_buf);
    if meta_buf.len == 0 {
        out.metadata.append("{}");
    } else {
        out.metadata.append(meta_buf);
    }

    out.data.clear();
    var data_buf: u8[>..] = [];
    json_util::find_string_field(json_str, "data", data_buf);
    out.data.append(data_buf);

    out.prev_hash.clear();
    var hash_buf: u8[>..] = [];
    json_util::find_string_field(json_str, "prev_hash", hash_buf);
    out.prev_hash.append(hash_buf);

    return out.key.len > 0;
}

// LWW conflict resolution:
// If record exists, compare timestamp in local metadata vs incoming timestamp.
// If incoming timestamp >= local timestamp, apply mutation.
fn apply_lww(handle: u64, cs: types::Changeset) -> bool {
    if handle == 0 || cs.key.len == 0 {
        return false;
    }

    var local_meta: u8[>..] = [];
    var local_data: u8[>..] = [];
    var exists = db::get(handle, cs.key, local_meta, local_data);

    if exists {
        var local_ts = json_util::find_int_field(local_meta, "timestamp", 0);
        if local_ts == 0 {
            local_ts = json_util::find_int_field(local_meta, "updated_at", 0);
        }
        if local_ts > cs.timestamp {
            // Local record is newer; keep local
            return true;
        }
    }

    if cs.op == 3 {
        // OpDelete
        return db::delete_key(handle, cs.key);
    } else {
        // OpInsert (1) or OpUpdate (2)
        var meta_to_store: u8[>..] = [];
        if cs.metadata.len > 0 && cs.metadata[0] == '{' {
            meta_to_store.append(cs.metadata);
        } else {
            meta_to_store.append("{\"timestamp\":");
            format(meta_to_store, cs.timestamp);
            meta_to_store.append("}");
        }
        return db::put(handle, cs.key, meta_to_store, cs.data);
    }
}
