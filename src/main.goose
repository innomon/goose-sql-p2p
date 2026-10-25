// goose-sql-p2p: Pear-compatible P2P SQLite Replication Engine in Goose
import std;
import os;
import types;
import db;
import crypto;
import net;
import json_util;
import changeset;
import config;
import feed;
import replicator;
import cli;

fn main() {
    var cfg = config::default_config();
    var bootstrap_nodes: u8[..128][>..] = [];
    var peer_addrs: u8[..128][>..] = [];
    var one_shot_cmd: u8[>..] = [];

    config::parse_args(cfg, bootstrap_nodes, peer_addrs, one_shot_cmd);

    // Open SQLite database
    var db_handle = db::open(cfg.db_path, cfg.wal);
    if db_handle == 0 {
        print("[ERROR] Failed to open SQLite database at: ", cfg.db_path);
        return;
    }

    db::init_feed_table(db_handle);

    // Initialize P2P Replicator
    var rep = replicator::init_replicator(db_handle, cfg.replication_port);

    // Connect to configured peers
    for p in peer_addrs {
        if p.len > 0 {
            replicator::connect_to_peer(rep, p);
        }
    }
    for b in bootstrap_nodes {
        if b.len > 0 {
            replicator::connect_to_peer(rep, b);
        }
    }

    var app_ctx = cli::AppContext {
        cfg: cfg,
        db_handle: db_handle,
        rep: rep,
        should_exit: false
    };

    // If one-shot command is supplied via -cmd, execute it and exit
    if one_shot_cmd.len > 0 {
        cli::execute_command(app_ctx, one_shot_cmd);
        net::sleep_ms(200);
        replicator::close_replicator(app_ctx.rep);
        db::close(db_handle);
        return;
    }

    // Interactive REPL Mode
    print("=================================================================");
    print("  goose-sql-p2p Node Running");
    print("  Node ID:     ", cfg.id);
    print("  Swarm Topic: ", cfg.swarm_topic);
    print("  DB Path:     ", cfg.db_path);
    print("  Listening:   0.0.0.0:", app_ctx.rep.actual_port);
    print("  Type 'help' or '/help' for commands, 'exit' to quit");
    print("=================================================================");

    while !app_ctx.should_exit {
        // Poll for replication events
        replicator::poll_and_sync(app_ctx.rep);

        var line: u8[>..] = [];
        if read_line(line) {
            cli::execute_command(app_ctx, line);
        } else {
            // End of stdin or running as daemon background; sleep slightly and continue syncing
            net::sleep_ms(100);
        }
    }

    replicator::close_replicator(app_ctx.rep);
    db::close(db_handle);
}
