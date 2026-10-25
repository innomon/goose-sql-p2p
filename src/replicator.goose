// Replication engine: manages TCP peer connections, framed synchronization and Autobase LWW consensus
namespace replicator;

import std;
import types;
import net;
import db;
import json_util;
import changeset;

struct ReplicatorState {
    db_handle: u64,
    server_fd: i32,
    actual_port: i32,
    peer_fds: i32[..32],
    is_running: bool
}

fn remove_peer_at(fds: i32[..32]&, idx: i64) {
    if idx < 0 || idx >= fds.len {
        return;
    }
    var i = idx;
    while i + 1 < fds.len {
        fds[i] = fds[i + 1];
        i++;
    }
    if fds.len > 0 {
        fds.pop();
    }
}

fn init_replicator(db_handle: u64, port: i32) -> ReplicatorState {
    var rep = ReplicatorState {
        db_handle: db_handle,
        server_fd: -1,
        actual_port: port,
        peer_fds: [],
        is_running: false
    };

    var actual: i32 = port;
    var sfd: i32 = -1;
    if net::listen_tcp(port, actual, sfd) {
        rep.server_fd = sfd;
        rep.actual_port = actual;
        rep.is_running = true;
    }

    return rep;
}

fn close_replicator(rep: ReplicatorState&) {
    rep.is_running = false;
    for fd in rep.peer_fds {
        net::close_fd(fd);
    }
    rep.peer_fds.clear();
    if rep.server_fd >= 0 {
        net::close_fd(rep.server_fd);
        rep.server_fd = -1;
    }
}

// Push all local crm_store records as changesets to a peer socket
fn sync_local_to_peer(handle: u64, fd: i32) {
    if handle == 0 || fd < 0 {
        return;
    }

    var list_json: u8[>..] = [];
    if !db::list(handle, "", 1000, 0, list_json) || list_json.len == 0 {
        return;
    }

    var p = 0;
    while p < list_json.len {
        while p < list_json.len && list_json[p] != '{' {
            p++;
        }
        if p >= list_json.len {
            break;
        }

        // Find matching '}'
        var depth = 1;
        var start = p;
        p++;
        var in_str = false;
        var esc = false;
        while p < list_json.len && depth > 0 {
            var c = list_json[p];
            if esc {
                esc = false;
            } else if c == '\\' && in_str {
                esc = true;
            } else if c == '"' {
                in_str = !in_str;
            } else if !in_str {
                if c == '{' { depth++; }
                else if c == '}' { depth--; }
            }
            p++;
        }

        if depth == 0 {
            var obj = list_json[start..p];
            var key: u8[>..] = [];
            json_util::find_string_field(obj, "key", key);

            var meta: u8[>..] = [];
            json_util::find_string_field(obj, "metadata", meta);

            var data: u8[>..] = [];
            json_util::find_string_field(obj, "data", data);

            var ts = json_util::find_int_field(meta, "timestamp", 0);
            if ts == 0 {
                ts = net::now_ns();
            }

            var cs = changeset::make_changeset(1, key, meta, data, ts, 1);
            var frame: u8[>..] = [];
            changeset::encode(cs, frame);
            net::send_framed(fd, frame);
        }
    }
}

// Connect to a remote peer address (e.g. "127.0.0.1:43219" or "localhost:43219")
fn connect_to_peer(rep: ReplicatorState&, peer_addr: const u8[:]) -> bool {
    var host: u8[>..] = [];
    var port_str: u8[>..] = [];
    var colon_pos = find(peer_addr, ":");

    if colon_pos > 0 {
        host.append(peer_addr[..colon_pos]);
        port_str.append(peer_addr[(colon_pos + 1)..]);
    } else {
        host.append(peer_addr);
        port_str.append("43219");
    }

    var port = json_util::parse_int(port_str, 43219) as i32;
    var fd = net::connect_tcp(host, port, 1000);
    if fd < 0 {
        return false;
    }

    if rep.peer_fds.len < 32 {
        rep.peer_fds.push(fd);
    }

    // Sync our current dataset to this peer
    sync_local_to_peer(rep.db_handle, fd);
    return true;
}

// Polls active connections for incoming changesets (non-blocking)
fn poll_and_sync(rep: ReplicatorState&) -> i64 {
    if !rep.is_running {
        return 0;
    }

    var applied_count: i64 = 0;

    // 1. Accept any pending incoming connection
    if rep.server_fd >= 0 {
        var client_fd: i32 = -1;
        var peer_ip: u8[>..] = [];
        var peer_port: i32 = 0;

        if net::accept_tcp(rep.server_fd, 5, client_fd, peer_ip, peer_port) && client_fd >= 0 {
            if rep.peer_fds.len < 32 {
                rep.peer_fds.push(client_fd);
            }
            // Send local changesets to new peer
            sync_local_to_peer(rep.db_handle, client_fd);
        }
    }

    // 2. Read incoming frames from all peers
    var i: i64 = 0;
    while i < rep.peer_fds.len {
        var fd = rep.peer_fds[i];
        var buf: u8[>..] = [];
        var rc = net::recv_framed(fd, 10, buf);

        if rc > 0 && buf.len > 0 {
            var cs = types::Changeset {
                timestamp: 0,
                seq: 0,
                op: 1,
                key: [],
                metadata: [],
                prev_hash: [],
                data: []
            };

            if changeset::decode(buf, cs) {
                if changeset::apply_lww(rep.db_handle, cs) {
                    applied_count++;
                }
            }
            i++;
        } else if rc < 0 {
            // Socket disconnected or error; remove peer
            net::close_fd(fd);
            remove_peer_at(rep.peer_fds, i);
        } else {
            i++;
        }
    }

    return applied_count;
}

// Broadcasts a locally mutated changeset to all connected peers
fn broadcast_changeset(rep: ReplicatorState&, cs: types::Changeset) {
    var frame: u8[>..] = [];
    changeset::encode(cs, frame);

    var i: i64 = 0;
    while i < rep.peer_fds.len {
        var fd = rep.peer_fds[i];
        if !net::send_framed(fd, frame) {
            net::close_fd(fd);
            remove_peer_at(rep.peer_fds, i);
        } else {
            i++;
        }
    }
}
