const std = @import("std");
const sig = @import("../lib.zig");

const AtomicBool = std.atomic.Value(bool);
const KeyPair = std.crypto.sign.Ed25519.KeyPair;
const Channel = sig.sync.Channel;

const Hash = sig.core.Hash;
const Pubkey = sig.core.Pubkey;
const RpcClient = sig.rpc.Client;
const TransactionInfo = sig.transaction_sender.TransactionInfo;
const Duration = sig.time.Duration;

/// Mock transaction generator that sends a transaction every 10 seconds
/// Used to test the transaction sender
/// TODO:
///     - Pass sender keypair and receiver pubkey
pub fn run(
    allocator: std.mem.Allocator,
    sender: *Channel(TransactionInfo),
    exit: *AtomicBool,
) !void {
    errdefer exit.store(true, .unordered);

    const from_pubkey = try Pubkey.fromString("Bkd9xbHF7JgwXmEib6uU3y582WaPWWiasPxzMesiBwWm");
    const from_keypair = KeyPair{
        .public_key = .{ .bytes = from_pubkey.data },
        .secret_key = .{ .bytes = [_]u8{ 76, 196, 192, 17, 40, 245, 120, 49, 64, 133, 213, 227, 12, 42, 183, 70, 235, 64, 235, 96, 246, 205, 78, 13, 173, 111, 254, 96, 210, 208, 121, 240, 159, 193, 185, 89, 227, 77, 234, 91, 232, 234, 253, 119, 162, 105, 200, 227, 123, 90, 111, 105, 72, 53, 60, 147, 76, 154, 44, 72, 29, 165, 2, 246 } },
    };
    const to_pubkey = try Pubkey.fromString("GDFVa3uYXDcNhcNk8A4v28VeF4wcMn8mauZNwVWbpcN");
    const lamports: u64 = 100;

    var rpc_client = RpcClient.init(allocator, .Testnet);
    defer rpc_client.deinit();

    while (!exit.load(.unordered)) {
        std.time.sleep(Duration.fromSecs(10).asNanos());

        const latest_blockhash, const last_valid_blockheight = blk: {
            var rpc_arena = std.heap.ArenaAllocator.init(allocator);
            defer rpc_arena.deinit();
            const blockhash = try rpc_client.getLatestBlockhash(&rpc_arena, .{});
            break :blk .{
                try Hash.fromString(blockhash.value.blockhash),
                blockhash.value.lastValidBlockHeight,
            };
        };

        const transaction = try sig.core.transaction.buildTransferTansaction(
            allocator,
            from_keypair,
            from_pubkey,
            to_pubkey,
            lamports,
            latest_blockhash,
        );

        const transaction_info = try TransactionInfo.new(
            transaction,
            last_valid_blockheight,
            null,
            null,
        );

        try sender.send(transaction_info);
    }
}
