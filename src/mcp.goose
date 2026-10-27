// Model Context Protocol (MCP) Server over STDIO
namespace mcp;

import std;
import types;
import db;
import crypto;
import net;
import changeset;
import feed;
import replicator;
import json_util;
import cli;

extern fn stdio_readline_c(out_line: u8[>..]&) -> i32 = "gs_stdio_readline";
extern fn stdio_write_stdout_c(data: const u8[:]) = "gs_stdio_write_stdout";
extern fn stdio_write_stderr_c(data: const u8[:]) = "gs_stdio_write_stderr";

fn read_line(out_line: u8[>..]&) -> i32 {
    return stdio_readline_c(out_line);
}

fn write_stdout(data: const u8[:]) {
    stdio_write_stdout_c(data);
}

fn write_stderr(data: const u8[:]) {
    stdio_write_stderr_c(data);
}

fn format_json_id(out: u8[>..]&, id_raw: const u8[:]) {
    if id_raw.len == 0 {
        out.append("null");
        return;
    }
    var is_num = true;
    var i = 0;
    if id_raw[0] == '-' {
        i = 1;
    }
    if i >= id_raw.len {
        is_num = false;
    }
    while i < id_raw.len {
        var c = id_raw[i];
        if c < '0' || c > '9' {
            is_num = false;
            break;
        }
        i++;
    }

    if is_num {
        out.append(id_raw);
    } else {
        out.push('"');
        json_util::escape_string(out, id_raw);
        out.push('"');
    }
}

fn make_error_response(out: u8[>..]&, id_raw: const u8[:], code: i32, msg: const u8[:]) {
    out.append("{\"jsonrpc\":\"2.0\",\"id\":");
    format_json_id(out, id_raw);
    out.append(",\"error\":{\"code\":");
    format(out, code);
    out.append(",\"message\":\"");
    json_util::escape_string(out, msg);
    out.append("\"}}");
}

fn make_tool_result_response(out: u8[>..]&, id_raw: const u8[:], text_content: const u8[:], is_error: bool) {
    out.append("{\"jsonrpc\":\"2.0\",\"id\":");
    format_json_id(out, id_raw);
    out.append(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"");
    json_util::escape_string(out, text_content);
    out.append("\"}],\"isError\":");
    if is_error {
        out.append("true");
    } else {
        out.append("false");
    }
    out.append("}}");
}

fn handle_initialize(id: const u8[:], out: u8[>..]&) {
    out.append("{\"jsonrpc\":\"2.0\",\"id\":");
    format_json_id(out, id);
    out.append(",\"result\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{\"tools\":{},\"resources\":{},\"prompts\":{}},\"serverInfo\":{\"name\":\"goose-sql-p2p\",\"version\":\"0.1.0\"}}}");
}

fn handle_ping(id: const u8[:], out: u8[>..]&) {
    out.append("{\"jsonrpc\":\"2.0\",\"id\":");
    format_json_id(out, id);
    out.append(",\"result\":{}}");
}

fn handle_tools_list(id: const u8[:], out: u8[>..]&) {
    out.append("{\"jsonrpc\":\"2.0\",\"id\":");
    format_json_id(out, id);
    out.append(",\"result\":{\"tools\":[");

    // Tool 1: sql
    out.append("{\"name\":\"sql\",\"description\":\"Execute arbitrary SQL queries (SELECT, DDL, DML) with selectable output format.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"The SQL statement to execute\"},\"format\":{\"type\":\"string\",\"enum\":[\"json\",\"table\",\"csv\"],\"description\":\"Output format (json, table, or csv)\",\"default\":\"json\"}},\"required\":[\"query\"]}},");

    // Tool 2: put
    out.append("{\"name\":\"put\",\"description\":\"Store key-value record with metadata and broadcast mutation across P2P swarm.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"key\":{\"type\":\"string\",\"description\":\"Record unique key\"},\"data\":{\"type\":\"string\",\"description\":\"Payload data string or serialized JSON\"},\"metadata\":{\"type\":\"string\",\"description\":\"Optional metadata JSON string\"}},\"required\":[\"key\",\"data\"]}},");

    // Tool 3: get
    out.append("{\"name\":\"get\",\"description\":\"Retrieve record payload and metadata by key.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"key\":{\"type\":\"string\",\"description\":\"Record key to retrieve\"}},\"required\":[\"key\"]}},");

    // Tool 4: del
    out.append("{\"name\":\"del\",\"description\":\"Delete record by key, write tombstone to changeset feed, and broadcast to peers.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"key\":{\"type\":\"string\",\"description\":\"Record key to delete\"}},\"required\":[\"key\"]}},");

    // Tool 5: list
    out.append("{\"name\":\"list\",\"description\":\"List records matching optional key prefix.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"prefix\":{\"type\":\"string\",\"description\":\"Optional key prefix filter\",\"default\":\"\"}}}},");

    // Tool 6: sync
    out.append("{\"name\":\"sync\",\"description\":\"Trigger immediate bidirectional replication sync across all connected swarm peers.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{}}},");

    // Tool 7: peers
    out.append("{\"name\":\"peers\",\"description\":\"Inspect active peer socket connections and cluster network status.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{}}},");

    // Tool 8: feed
    out.append("{\"name\":\"feed\",\"description\":\"View local Hypercore append-only changeset feed with rolling SHA-256 hashes.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{}}},");

    // Tool 9: status
    out.append("{\"name\":\"status\",\"description\":\"Retrieve node status, WAL mode, swarm topic, and active port configuration.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{}}}");

    out.append("]}}");
}

fn handle_tool_call(ctx: cli::AppContext&, id: const u8[:], params: const u8[:], out: u8[>..]&) {
    var tool_name: u8[>..] = [];
    json_util::find_string_field(params, "name", tool_name);

    var args_str: u8[>..] = [];
    json_util::find_string_field(params, "arguments", args_str);

    if tool_name == "sql" {
        var query: u8[>..] = [];
        json_util::find_string_field(args_str, "query", query);
        if query.len == 0 {
            make_tool_result_response(out, id, "Error: 'query' parameter is required for tool 'sql'", true);
            return;
        }
        var fmt_str: u8[>..] = [];
        if !json_util::find_string_field(args_str, "format", fmt_str) || fmt_str.len == 0 {
            fmt_str.append("json");
        }

        var sql_res: u8[>..] = [];
        var ok = db::query_raw(ctx.db_handle, query, fmt_str, sql_res);
        make_tool_result_response(out, id, sql_res, !ok);
        return;
    }

    if tool_name == "put" {
        var key: u8[>..] = [];
        json_util::find_string_field(args_str, "key", key);
        if key.len == 0 {
            make_tool_result_response(out, id, "Error: 'key' parameter is required for tool 'put'", true);
            return;
        }
        var data: u8[>..] = [];
        if !json_util::find_string_field(args_str, "data", data) || data.len == 0 {
            json_util::find_string_field(args_str, "value", data);
        }

        var meta: u8[>..] = [];
        if !json_util::find_string_field(args_str, "metadata", meta) || meta.len == 0 {
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
            var ok_msg: u8[>..] = [];
            ok_msg.append("OK put ");
            ok_msg.append(key);
            make_tool_result_response(out, id, ok_msg, false);
        } else {
            var err_msg: u8[>..] = [];
            err_msg.append("Error: failed to put ");
            err_msg.append(key);
            make_tool_result_response(out, id, err_msg, true);
        }
        return;
    }

    if tool_name == "get" {
        var key: u8[>..] = [];
        json_util::find_string_field(args_str, "key", key);
        if key.len == 0 {
            make_tool_result_response(out, id, "Error: 'key' parameter is required for tool 'get'", true);
            return;
        }

        var meta_out: u8[>..] = [];
        var data_out: u8[>..] = [];
        if db::get(ctx.db_handle, key, meta_out, data_out) {
            var plain_data: u8[>..] = [];
            if ctx.cfg.enable_crypto && ctx.cfg.encryption_key.len > 0 {
                var dec = crypto::decrypt(ctx.cfg.encryption_key, data_out);
                plain_data.append(dec);
            } else {
                plain_data.append(data_out);
            }

            var res_json: u8[>..] = [];
            res_json.append("{\"key\":\"");
            json_util::escape_string(res_json, key);
            res_json.append("\",\"metadata\":");
            if meta_out.len > 0 {
                res_json.append(meta_out);
            } else {
                res_json.append("{}");
            }
            res_json.append(",\"data\":\"");
            json_util::escape_string(res_json, plain_data);
            res_json.append("\"}");
            make_tool_result_response(out, id, res_json, false);
        } else {
            var err_msg: u8[>..] = [];
            err_msg.append("Key not found: ");
            err_msg.append(key);
            make_tool_result_response(out, id, err_msg, true);
        }
        return;
    }

    if tool_name == "del" {
        var key: u8[>..] = [];
        json_util::find_string_field(args_str, "key", key);
        if key.len == 0 {
            make_tool_result_response(out, id, "Error: 'key' parameter is required for tool 'del'", true);
            return;
        }

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
            var ok_msg: u8[>..] = [];
            ok_msg.append("OK deleted ");
            ok_msg.append(key);
            make_tool_result_response(out, id, ok_msg, false);
        } else {
            var err_msg: u8[>..] = [];
            err_msg.append("Error: failed to delete ");
            err_msg.append(key);
            make_tool_result_response(out, id, err_msg, true);
        }
        return;
    }

    if tool_name == "list" {
        var prefix: u8[>..] = [];
        json_util::find_string_field(args_str, "prefix", prefix);

        var list_json: u8[>..] = [];
        if db::list(ctx.db_handle, prefix, 100, 0, list_json) {
            make_tool_result_response(out, id, list_json, false);
        } else {
            make_tool_result_response(out, id, "[]", false);
        }
        return;
    }

    if tool_name == "sync" {
        var count = replicator::poll_and_sync(ctx.rep);
        var sync_msg: u8[>..] = [];
        sync_msg.append("Sync completed. Applied ");
        format(sync_msg, count);
        sync_msg.append(" remote changesets.");
        make_tool_result_response(out, id, sync_msg, false);
        return;
    }

    if tool_name == "peers" {
        var peers_json: u8[>..] = [];
        peers_json.append("{\"active_peers\":");
        format(peers_json, ctx.rep.peer_fds.len);
        peers_json.append(",\"port\":");
        format(peers_json, ctx.rep.actual_port as i64);
        peers_json.append("}");
        make_tool_result_response(out, id, peers_json, false);
        return;
    }

    if tool_name == "feed" {
        var feed_json: u8[>..] = [];
        if feed::fetch_all_changesets(ctx.db_handle, feed_json) {
            make_tool_result_response(out, id, feed_json, false);
        } else {
            make_tool_result_response(out, id, "[]", false);
        }
        return;
    }

    if tool_name == "status" {
        var status_json: u8[>..] = [];
        status_json.append("{\"node_id\":\"");
        json_util::escape_string(status_json, ctx.cfg.id);
        status_json.append("\",\"swarm_topic\":\"");
        json_util::escape_string(status_json, ctx.cfg.swarm_topic);
        status_json.append("\",\"db_path\":\"");
        json_util::escape_string(status_json, ctx.cfg.db_path);
        status_json.append("\",\"port\":");
        format(status_json, ctx.rep.actual_port as i64);
        status_json.append(",\"wal\":");
        if ctx.cfg.wal { status_json.append("true"); } else { status_json.append("false"); }
        status_json.append(",\"crypto\":");
        if ctx.cfg.enable_crypto { status_json.append("true"); } else { status_json.append("false"); }
        status_json.append(",\"peers\":");
        format(status_json, ctx.rep.peer_fds.len);
        status_json.append("}");
        make_tool_result_response(out, id, status_json, false);
        return;
    }

    var unknown_err: u8[>..] = [];
    unknown_err.append("Unknown tool: ");
    unknown_err.append(tool_name);
    make_tool_result_response(out, id, unknown_err, true);
}

fn handle_resources_list(id: const u8[:], out: u8[>..]&) {
    out.append("{\"jsonrpc\":\"2.0\",\"id\":");
    format_json_id(out, id);
    out.append(",\"result\":{\"resources\":[");
    out.append("{\"uri\":\"sqlite://crm_store\",\"name\":\"Local CRM Key-Value Store\",\"mimeType\":\"application/json\",\"description\":\"Complete listing of local key-value store records\"},");
    out.append("{\"uri\":\"sqlite://feed\",\"name\":\"Hypercore Append-Only Changeset Feed\",\"mimeType\":\"application/json\",\"description\":\"Chronological list of all recorded changesets with SHA-256 hashes\"},");
    out.append("{\"uri\":\"sqlite://status\",\"name\":\"Node Status & Network Metadata\",\"mimeType\":\"application/json\",\"description\":\"Active node configuration, ports, WAL mode, and peer count\"}");
    out.append("]}}");
}

fn handle_resources_read(ctx: cli::AppContext&, id: const u8[:], params: const u8[:], out: u8[>..]&) {
    var uri: u8[>..] = [];
    json_util::find_string_field(params, "uri", uri);

    if uri == "sqlite://crm_store" {
        var list_json: u8[>..] = [];
        db::list(ctx.db_handle, "", 100, 0, list_json);
        out.append("{\"jsonrpc\":\"2.0\",\"id\":");
        format_json_id(out, id);
        out.append(",\"result\":{\"contents\":[{\"uri\":\"sqlite://crm_store\",\"mimeType\":\"application/json\",\"text\":\"");
        json_util::escape_string(out, list_json);
        out.append("\"}]}}");
        return;
    }

    if uri.len > 19 && uri[0..19] == "sqlite://crm_store/" {
        var key = uri[19..];
        var meta_out: u8[>..] = [];
        var data_out: u8[>..] = [];
        if db::get(ctx.db_handle, key, meta_out, data_out) {
            var plain_data: u8[>..] = [];
            if ctx.cfg.enable_crypto && ctx.cfg.encryption_key.len > 0 {
                var dec = crypto::decrypt(ctx.cfg.encryption_key, data_out);
                plain_data.append(dec);
            } else {
                plain_data.append(data_out);
            }

            var rec_json: u8[>..] = [];
            rec_json.append("{\"key\":\"");
            json_util::escape_string(rec_json, key);
            rec_json.append("\",\"metadata\":");
            if meta_out.len > 0 { rec_json.append(meta_out); } else { rec_json.append("{}"); }
            rec_json.append(",\"data\":\"");
            json_util::escape_string(rec_json, plain_data);
            rec_json.append("\"}");

            out.append("{\"jsonrpc\":\"2.0\",\"id\":");
            format_json_id(out, id);
            out.append(",\"result\":{\"contents\":[{\"uri\":\"");
            json_util::escape_string(out, uri);
            out.append("\",\"mimeType\":\"application/json\",\"text\":\"");
            json_util::escape_string(out, rec_json);
            out.append("\"}]}}");
        } else {
            make_error_response(out, id, -32602, "Resource not found");
        }
        return;
    }

    if uri == "sqlite://feed" {
        var feed_json: u8[>..] = [];
        feed::fetch_all_changesets(ctx.db_handle, feed_json);
        out.append("{\"jsonrpc\":\"2.0\",\"id\":");
        format_json_id(out, id);
        out.append(",\"result\":{\"contents\":[{\"uri\":\"sqlite://feed\",\"mimeType\":\"application/json\",\"text\":\"");
        json_util::escape_string(out, feed_json);
        out.append("\"}]}}");
        return;
    }

    if uri == "sqlite://status" {
        var status_json: u8[>..] = [];
        status_json.append("{\"node_id\":\"");
        json_util::escape_string(status_json, ctx.cfg.id);
        status_json.append("\",\"swarm_topic\":\"");
        json_util::escape_string(status_json, ctx.cfg.swarm_topic);
        status_json.append("\",\"db_path\":\"");
        json_util::escape_string(status_json, ctx.cfg.db_path);
        status_json.append("\",\"port\":");
        format(status_json, ctx.rep.actual_port as i64);
        status_json.append(",\"wal\":");
        if ctx.cfg.wal { status_json.append("true"); } else { status_json.append("false"); }
        status_json.append(",\"crypto\":");
        if ctx.cfg.enable_crypto { status_json.append("true"); } else { status_json.append("false"); }
        status_json.append(",\"peers\":");
        format(status_json, ctx.rep.peer_fds.len);
        status_json.append("}");

        out.append("{\"jsonrpc\":\"2.0\",\"id\":");
        format_json_id(out, id);
        out.append(",\"result\":{\"contents\":[{\"uri\":\"sqlite://status\",\"mimeType\":\"application/json\",\"text\":\"");
        json_util::escape_string(out, status_json);
        out.append("\"}]}}");
        return;
    }

    make_error_response(out, id, -32602, "Resource not found");
}

fn handle_prompts_list(id: const u8[:], out: u8[>..]&) {
    out.append("{\"jsonrpc\":\"2.0\",\"id\":");
    format_json_id(out, id);
    out.append(",\"result\":{\"prompts\":[");
    out.append("{\"name\":\"p2p_sync_diagnostic\",\"description\":\"Analyze peer connectivity and synchronization status across P2P swarm\",\"arguments\":[]},");
    out.append("{\"name\":\"sql_data_analyst\",\"description\":\"Inspect local SQLite schema and compose analytical queries against crm_store\",\"arguments\":[]}");
    out.append("]}}");
}

fn handle_prompts_get(ctx: cli::AppContext&, id: const u8[:], params: const u8[:], out: u8[>..]&) {
    var name: u8[>..] = [];
    json_util::find_string_field(params, "name", name);

    if name == "p2p_sync_diagnostic" {
        out.append("{\"jsonrpc\":\"2.0\",\"id\":");
        format_json_id(out, id);
        out.append(",\"result\":{\"description\":\"Peer connectivity and sync diagnostic\",\"messages\":[{\"role\":\"user\",\"content\":{\"type\":\"text\",\"text\":\"Please inspect the active peers using the 'peers' tool and check recent changesets using 'feed' to ensure peer state is synchronized.\"}}]}}");
        return;
    }

    if name == "sql_data_analyst" {
        out.append("{\"jsonrpc\":\"2.0\",\"id\":");
        format_json_id(out, id);
        out.append(",\"result\":{\"description\":\"SQL data analysis workflow\",\"messages\":[{\"role\":\"user\",\"content\":{\"type\":\"text\",\"text\":\"Please inspect the table schema and data using the 'sql' tool with query 'SELECT * FROM crm_store LIMIT 10;' and provide an overview of stored records.\"}}]}}");
        return;
    }

    make_error_response(out, id, -32602, "Prompt not found");
}

fn handle_request(ctx: cli::AppContext&, req_line: const u8[:], out_resp: u8[>..]&) -> bool {
    var method: u8[>..] = [];
    if !json_util::find_string_field(req_line, "method", method) {
        return false;
    }

    var id: u8[>..] = [];
    var has_id = json_util::find_string_field(req_line, "id", id);

    var params: u8[>..] = [];
    json_util::find_string_field(req_line, "params", params);

    // Notifications (no id)
    if method == "notifications/initialized" || method == "initialized" {
        return false;
    }

    if !has_id {
        return false;
    }

    if method == "initialize" {
        handle_initialize(id, out_resp);
        return true;
    }

    if method == "ping" {
        handle_ping(id, out_resp);
        return true;
    }

    if method == "tools/list" {
        handle_tools_list(id, out_resp);
        return true;
    }

    if method == "tools/call" {
        handle_tool_call(ctx, id, params, out_resp);
        return true;
    }

    if method == "resources/list" {
        handle_resources_list(id, out_resp);
        return true;
    }

    if method == "resources/read" {
        handle_resources_read(ctx, id, params, out_resp);
        return true;
    }

    if method == "prompts/list" {
        handle_prompts_list(id, out_resp);
        return true;
    }

    if method == "prompts/get" {
        handle_prompts_get(ctx, id, params, out_resp);
        return true;
    }

    make_error_response(out_resp, id, -32601, "Method not found");
    return true;
}

fn run_stdio_server(ctx: cli::AppContext&) {
    write_stderr("[MCP Server] Starting goose-sql-p2p Model Context Protocol Server on STDIO...");
    var line: u8[>..] = [];
    var resp: u8[>..] = [];

    while !ctx.should_exit {
        line.clear();
        var rc = read_line(line);
        if rc != 0 {
            // EOF or error
            break;
        }
        if line.len == 0 {
            continue;
        }

        resp.clear();
        if handle_request(ctx, line, resp) {
            if resp.len > 0 {
                write_stdout(resp);
            }
        }
    }
    write_stderr("[MCP Server] Shutting down STDIO server.");
}
