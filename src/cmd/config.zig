const ACCOUNT_INDEX_BINS = @import("../accountsdb/db.zig").ACCOUNT_INDEX_BINS;

pub const Config = struct {
    identity: IdentityConfig = .{},
    gossip: GossipConfig = .{},
    repair: RepairConfig = .{},
    accounts_db: AccountsDbConfig = .{},
    // general config
    log_level: []const u8 = "debug",
    metrics_port: u16 = 12345,
};

pub const current: *Config = &default_validator_config;
var default_validator_config: Config = .{};

const IdentityConfig = struct {};

const GossipConfig = struct {
    host: ?[]const u8 = null,
    port: u16 = 8001,
    entrypoints: [][]const u8 = &.{},
    spy_node: bool = false,
    dump: bool = false,
    trusted_validators: [][]const u8 = &.{},
};

const RepairConfig = struct {
    port: u16 = 8002,
    test_repair_slot: ?u64 = null,
};

const AccountsDbConfig = struct {
    snapshot_dir: []const u8 = "test_data/",
    num_threads_snapshot_load: u16 = 0,
    num_threads_snapshot_unpack: u16 = 0,
    num_account_index_bins: usize = ACCOUNT_INDEX_BINS,
    disk_index_path: ?[]const u8 = null,
    force_unpack_snapshot: bool = false,
    min_snapshot_download_speed_mbs: usize = 20,
    force_new_snapshot_download: bool = false,
    storage_cache_size: usize = 10_000,
};

const LogConfig = struct {};
