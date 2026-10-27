// Configuration loader and command-line flag parser
namespace config;

import std;
import os;
import types;
import json_util;

fn default_config() -> types::NodeConfig {
    var cfg = types::NodeConfig {
        id: [],
        name: [],
        db_path: [],
        wal: true,
        replication_port: 0,
        swarm_topic: [],
        key_registry_path: [],
        encryption_key: [],
        enable_crypto: false,
        sync_interval_sec: 2,
        auto_sync: true
    };
    cfg.id.append("node-goose-sql-p2p");
    cfg.name.append("goose-node");
    cfg.db_path.append("data/node.db");
    cfg.swarm_topic.append("sqlite-p2p-e2e-cluster");
    return cfg;
}

fn load_from_json(json_str: const u8[:], cfg: types::NodeConfig&, out_bootstrap: u8[..128][>..]&, out_peers: u8[..128][>..]&) {
    var id: u8[>..] = [];
    if json_util::find_string_field(json_str, "node_id", id) && id.len > 0 {
        cfg.id.clear();
        cfg.id.append(id);
    } else if json_util::find_string_field(json_str, "id", id) && id.len > 0 {
        cfg.id.clear();
        cfg.id.append(id);
    }

    var name: u8[>..] = [];
    if json_util::find_string_field(json_str, "name", name) && name.len > 0 {
        cfg.name.clear();
        cfg.name.append(name);
    }

    var db_path: u8[>..] = [];
    if json_util::find_string_field(json_str, "db_path", db_path) && db_path.len > 0 {
        cfg.db_path.clear();
        cfg.db_path.append(db_path);
    }

    cfg.wal = json_util::find_bool_field(json_str, "enable_wal", cfg.wal);
    cfg.wal = json_util::find_bool_field(json_str, "wal", cfg.wal);

    var port = json_util::find_int_field(json_str, "swarm_port", -1);
    if port < 0 {
        port = json_util::find_int_field(json_str, "replication_port", -1);
    }
    if port >= 0 {
        cfg.replication_port = port as i32;
    }

    var topic: u8[>..] = [];
    if json_util::find_string_field(json_str, "swarm_topic", topic) && topic.len > 0 {
        cfg.swarm_topic.clear();
        cfg.swarm_topic.append(topic);
    }

    cfg.enable_crypto = json_util::find_bool_field(json_str, "enable_crypto", cfg.enable_crypto);
    cfg.auto_sync = json_util::find_bool_field(json_str, "auto_sync", cfg.auto_sync);

    var enc_key: u8[>..] = [];
    if json_util::find_string_field(json_str, "encryption_key", enc_key) && enc_key.len > 0 {
        cfg.encryption_key.clear();
        cfg.encryption_key.append(enc_key);
        cfg.enable_crypto = true;
    }

    var key_reg: u8[>..] = [];
    if json_util::find_string_field(json_str, "key_registry_path", key_reg) && key_reg.len > 0 {
        cfg.key_registry_path.clear();
        cfg.key_registry_path.append(key_reg);
    }

    json_util::find_string_array(json_str, "bootstrap", out_bootstrap);
    json_util::find_string_array(json_str, "peer_addrs", out_peers);
}

fn load_file(path: const u8[:], cfg: types::NodeConfig&, out_bootstrap: u8[..128][>..]&, out_peers: u8[..128][>..]&) -> bool {
    var content: u8[>..] = [];
    if !read_file(path, content) {
        return false;
    }
    load_from_json(content, cfg, out_bootstrap, out_peers);
    return true;
}

// Parses command-line flags into cfg, returning peers and optional one-shot command in out_cmd
fn parse_args(cfg: types::NodeConfig&, out_bootstrap: u8[..128][>..]&, out_peers: u8[..128][>..]&, out_cmd: u8[>..]&) {
    let count = arg_count();
    var i: i64 = 1;

    while i < count {
        var a: u8[>..] = [];
        arg(i, a);

        if a == "-config" || a == "--config" {
            i++;
            if i < count {
                var config_path: u8[>..] = [];
                arg(i, config_path);
                load_file(config_path, cfg, out_bootstrap, out_peers);
            }
        } else if a == "-node" || a == "--node" || a == "-id" || a == "--id" {
            i++;
            if i < count {
                cfg.id.clear();
                var node_buf: u8[>..] = [];
                arg(i, node_buf);
                cfg.id.append(node_buf);
            }
        } else if a == "-port" || a == "--port" {
            i++;
            if i < count {
                var port_str: u8[>..] = [];
                arg(i, port_str);
                var p = json_util::find_int_field(str("\"p\":", port_str), "p", 0);
                cfg.replication_port = p as i32;
            }
        } else if a == "-db" || a == "--db" {
            i++;
            if i < count {
                cfg.db_path.clear();
                var db_buf: u8[>..] = [];
                arg(i, db_buf);
                cfg.db_path.append(db_buf);
            }
        } else if a == "-bootstrap" || a == "--bootstrap" {
            i++;
            if i < count {
                var b: u8[>..] = [];
                arg(i, b);
                if b.len > 0 {
                    var bounded: u8[..128] = [];
                    bounded.append(b);
                    out_bootstrap.push(bounded);
                }
            }
        } else if a == "-peer" || a == "--peer" {
            i++;
            if i < count {
                var p: u8[>..] = [];
                arg(i, p);
                if p.len > 0 {
                    var bounded: u8[..128] = [];
                    bounded.append(p);
                    out_peers.push(bounded);
                }
            }
        } else if a == "-cmd" || a == "--cmd" {
            i++;
            if i < count {
                out_cmd.clear();
                arg(i, out_cmd);
            }
        } else if a == "-mcp" || a == "--mcp" || a == "mcp" {
            cfg.mcp_mode = true;
        }
        i++;
    }
}
