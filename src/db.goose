// SQLite 3 database bridge interface and high-level storage helpers
namespace db;

import std;

extern fn db_open_c(path: const u8[:], enable_wal: bool, out_handle: u64&) -> i32 = "gs_db_open";
extern fn db_close_c(handle: u64) -> i32 = "gs_db_close";
extern fn db_exec_c(handle: u64, sql: const u8[:]) -> i32 = "gs_db_exec";
extern fn db_put_c(handle: u64, key: const u8[:], meta: const u8[:], data: const u8[:]) -> i32 = "gs_db_put";
extern fn db_get_c(handle: u64, key: const u8[:], out_meta: u8[>..]&, out_data: u8[>..]&) -> i32 = "gs_db_get";
extern fn db_delete_c(handle: u64, key: const u8[:]) -> i32 = "gs_db_delete";
extern fn db_list_c(handle: u64, prefix: const u8[:], limit: i32, offset: i32, out_json: u8[>..]&) -> i32 = "gs_db_list";
extern fn db_query_raw_c(handle: u64, sql: const u8[:], format: const u8[:], out_result: u8[>..]&) -> i32 = "gs_db_query_raw";

fn open(path: const u8[:], wal: bool) -> u64 {
    var handle: u64 = 0;
    var rc = db_open_c(path, wal, handle);
    if rc != 0 {
        return 0;
    }
    return handle;
}

fn close(handle: u64) -> bool {
    if handle == 0 {
        return true;
    }
    return db_close_c(handle) == 0;
}

fn exec(handle: u64, sql: const u8[:]) -> bool {
    if handle == 0 {
        return false;
    }
    return db_exec_c(handle, sql) == 0;
}

fn put(handle: u64, key: const u8[:], meta: const u8[:], data: const u8[:]) -> bool {
    if handle == 0 {
        return false;
    }
    var effective_meta: u8[>..] = [];
    if meta.len == 0 {
        effective_meta.append("{}");
    } else {
        effective_meta.append(meta);
    }
    return db_put_c(handle, key, effective_meta, data) == 0;
}

fn get(handle: u64, key: const u8[:], out_meta: u8[>..]&, out_data: u8[>..]&) -> bool {
    if handle == 0 {
        return false;
    }
    return db_get_c(handle, key, out_meta, out_data) == 0;
}

fn delete_key(handle: u64, key: const u8[:]) -> bool {
    if handle == 0 {
        return false;
    }
    return db_delete_c(handle, key) == 0;
}

fn list(handle: u64, prefix: const u8[:], limit: i32, offset: i32, out_json: u8[>..]&) -> bool {
    if handle == 0 {
        return false;
    }
    return db_list_c(handle, prefix, limit, offset, out_json) == 0;
}

fn query_raw(handle: u64, sql: const u8[:], format: const u8[:], out_result: u8[>..]&) -> bool {
    if handle == 0 {
        return false;
    }
    return db_query_raw_c(handle, sql, format, out_result) == 0;
}

fn init_feed_table(handle: u64) -> bool {
    var feed_ddl = "CREATE TABLE IF NOT EXISTS changeset_feed (seq INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER, op INTEGER, key TEXT, metadata TEXT, data BLOB, prev_hash TEXT, hash TEXT);";
    return exec(handle, feed_ddl);
}
