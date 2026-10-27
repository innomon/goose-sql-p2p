// goose-sql-p2p types and structures
namespace types;

struct NodeConfig {
    id: u8[..64],
    name: u8[..64],
    db_path: u8[..256],
    wal: bool = true,
    replication_port: i32 = 0,
    swarm_topic: u8[..128],
    key_registry_path: u8[..256],
    encryption_key: u8[..64],
    enable_crypto: bool = false,
    sync_interval_sec: i32 = 2,
    auto_sync: bool = true,
    mcp_mode: bool = false
}

struct Changeset {
    timestamp: i64,
    seq: u64,
    op: i32,         // 1 = Insert, 2 = Update, 3 = Delete
    key: u8[..256],
    metadata: u8[..1024],
    prev_hash: u8[..128],
    data: u8[..4096]
}

struct PeerInfo {
    ip: u8[..64],
    port: i32,
    fd: i32,
    last_seen: i64,
    is_connected: bool
}

struct KeyEntry {
    key_id: u8[..64],
    key_data: u8[..64],
    created_at: i64,
    is_active: bool
}
