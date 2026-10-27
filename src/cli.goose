// Handcrafted CLI and slash command registry
namespace cli;

import std;
import types;
import db;
import crypto;
import net;
import changeset;
import feed;
import replicator;
import json_util;

struct AppContext {
    cfg: types::NodeConfig,
    db_handle: u64,
    rep: replicator::ReplicatorState,
    should_exit: bool
}

fn print_help() {
    print("Available Commands (Slash command syntax supported):");
    print("  put / /put <key> <data> [meta]  - Put key-value pair into crm_store and replicate");
    print("  get / /get <key>                - Get record by key");
    print("  del / /del <key>                - Delete record by key");
    print("  list / /list [prefix]           - List all keys or keys starting with prefix");
    print("  sql / /sql [-f <fmt>] <query>   - Execute raw SQL directly (formats: json, table, csv)");
    print("  sync / /sync                    - Trigger immediate replication sync with peers");
    print("  peers / /peers                  - Display active peer connections");
    print("  feed / /feed                    - View local append-only changeset feed");
    print("  status / /status                - Display node status and configuration");
    print("  mcp / /mcp                      - Run in Model Context Protocol (MCP) STDIO server mode");
    print("  help / /help                    - Display this help message");
    print("  exit / /exit, quit / /quit      - Exit goose-sql-p2p");
}

fn execute_command(ctx: AppContext&, line: const u8[:]) -> bool {
    var trimmed: u8[>..] = [];
    var start = 0;
    while start < line.len && (line[start] == ' ' || line[start] == '\t' || line[start] == '\r' || line[start] == '\n') {
        start++;
    }
    var end = line.len;
    while end > start && (line[end - 1] == ' ' || line[end - 1] == '\t' || line[end - 1] == '\r' || line[end - 1] == '\n') {
        end--;
    }
    if start >= end {
        return true;
    }
    trimmed.append(line[start..end]);

    // Parse words as slices and track start offsets
    var words: u8[:][>..] = [];
    var word_starts: i64[>..] = [];
    var p = 0;
    while p < trimmed.len {
        while p < trimmed.len && (trimmed[p] == ' ' || trimmed[p] == '\t') {
            p++;
        }
        if p >= trimmed.len {
            break;
        }
        var word_start = p;
        while p < trimmed.len && trimmed[p] != ' ' && trimmed[p] != '\t' {
            p++;
        }
        words.push(trimmed[word_start..p]);
        word_starts.push(word_start);
    }

    if words.len == 0 {
        return true;
    }

    var cmd = words[0];

    // Normalize command (strip leading slash if present for slash command support)
    var cmd_name: u8[>..] = [];
    if cmd.len > 0 && cmd[0] == '/' {
        cmd_name.append(cmd[1..]);
    } else {
        cmd_name.append(cmd);
    }

    if cmd_name == "help" || cmd_name == "?" {
        print_help();
        return true;
    }

    if cmd_name == "exit" || cmd_name == "quit" {
        ctx.should_exit = true;
        print("Shutting down goose-sql-p2p node...");
        return true;
    }

    if cmd_name == "status" {
        print("--- Node Status ---");
        print("  Node ID:     ", ctx.cfg.id);
        print("  Swarm Topic: ", ctx.cfg.swarm_topic);
        print("  DB Path:     ", ctx.cfg.db_path);
        print("  Port:        ", ctx.rep.actual_port);
        print("  WAL Mode:    ", ctx.cfg.wal);
        print("  Crypto:      ", ctx.cfg.enable_crypto);
        print("  Peers:       ", ctx.rep.peer_fds.len);
        return true;
    }

    if cmd_name == "peers" {
        print("Active Peer Count: ", ctx.rep.peer_fds.len);
        return true;
    }

    if cmd_name == "sql" {
        if words.len < 2 {
            print("Usage: sql [--format json|table|csv] <query>");
            return false;
        }
        var fmt_str: u8[>..] = [];
        fmt_str.append("json");
        var sql_start_idx = 1;

        while sql_start_idx < words.len {
            var w = words[sql_start_idx];
            if w.len >= 9 && w[0..9] == "--format=" {
                fmt_str.clear();
                fmt_str.append(w[9..]);
                sql_start_idx++;
            } else if w.len >= 3 && w[0..3] == "-f=" {
                fmt_str.clear();
                fmt_str.append(w[3..]);
                sql_start_idx++;
            } else if w == "--format" || w == "-f" {
                if sql_start_idx + 1 < words.len {
                    fmt_str.clear();
                    fmt_str.append(words[sql_start_idx + 1]);
                    sql_start_idx += 2;
                } else {
                    print("Usage: sql [--format json|table|csv] <query>");
                    return false;
                }
            } else {
                break;
            }
        }

        if sql_start_idx >= words.len {
            print("Usage: sql [--format json|table|csv] <query>");
            return false;
        }

        var raw_sql = trimmed[word_starts[sql_start_idx]..trimmed.len];
        var out_res: u8[>..] = [];
        db::query_raw(ctx.db_handle, raw_sql, fmt_str, out_res);
        print(out_res);
        return true;
    }

    if cmd_name == "sync" {
        var count = replicator::poll_and_sync(ctx.rep);
        print("Sync completed. Applied ", count, " remote changesets.");
        return true;
    }

    if cmd_name == "get" {
        if words.len < 2 {
            print("Usage: get <key>");
            return false;
        }
        var key = words[1];
        var meta: u8[>..] = [];
        var data: u8[>..] = [];
        if db::get(ctx.db_handle, key, meta, data) {
            print("Key:      ", key);
            print("Metadata: ", meta);
            print("Data:     ", data);
        } else {
            print("Key not found: ", key);
        }
        return true;
    }

    if cmd_name == "put" {
        if words.len < 3 {
            print("Usage: put <key> <data> [metadata_json]");
            return false;
        }
        var key = words[1];
        var data = words[2];
        var meta: u8[>..] = [];
        if words.len >= 4 {
            meta.append(words[3]);
        } else {
            var now = net::now_ns();
            meta.append("{\"timestamp\":");
            format(meta, now);
            meta.append("}");
        }

        var payload_data: u8[>..] = [];
        if ctx.cfg.enable_crypto && ctx.cfg.encryption_key.len > 0 {
            var cipher = crypto::encrypt(ctx.cfg.encryption_key, data);
            payload_data.append(cipher);
        } else {
            payload_data.append(data);
        }

        if db::put(ctx.db_handle, key, meta, payload_data) {
            var now = net::now_ns();
            var cs = types::Changeset {
                timestamp: now,
                seq: 1,
                op: 1,
                key: [],
                metadata: [],
                prev_hash: [],
                data: []
            };
            feed::append_changeset(ctx.db_handle, 1, key, meta, payload_data, now, cs);
            replicator::broadcast_changeset(ctx.rep, cs);
            print("OK put ", key);
        } else {
            print("Error: failed to put ", key);
        }
        return true;
    }

    if cmd_name == "del" || cmd_name == "delete" {
        if words.len < 2 {
            print("Usage: del <key>");
            return false;
        }
        var key = words[1];
        if db::delete_key(ctx.db_handle, key) {
            var now = net::now_ns();
            var cs = types::Changeset {
                timestamp: now,
                seq: 1,
                op: 3,
                key: [],
                metadata: [],
                prev_hash: [],
                data: []
            };
            feed::append_changeset(ctx.db_handle, 3, key, "{}", "", now, cs);
            replicator::broadcast_changeset(ctx.rep, cs);
            print("OK deleted ", key);
        } else {
            print("Error: failed to delete ", key);
        }
        return true;
    }

    if cmd_name == "list" {
        var prefix: u8[>..] = [];
        if words.len >= 2 {
            prefix.append(words[1]);
        }
        var json_out: u8[>..] = [];
        if db::list(ctx.db_handle, prefix, 100, 0, json_out) {
            print(json_out);
        } else {
            print("[]");
        }
        return true;
    }

    if cmd_name == "feed" {
        var json_out: u8[>..] = [];
        if feed::fetch_all_changesets(ctx.db_handle, json_out) {
            print(json_out);
        } else {
            print("[]");
        }
        return true;
    }

    print("Unknown command: '", cmd, "'. Type 'help' for available commands.");
    return false;
}
