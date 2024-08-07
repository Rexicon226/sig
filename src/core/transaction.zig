const std = @import("std");
const sig = @import("../lib.zig");

const Signature = sig.core.Signature;
const Pubkey = sig.core.Pubkey;
const Hash = sig.core.Hash;
const ShortVecConfig = sig.bincode.shortvec.ShortVecConfig;

pub const VersionedTransaction = struct {
    signatures: []Signature,
    message: VersionedMessage,

    pub fn sanitize(self: VersionedTransaction) !void {
        switch (self.message) {
            inline .legacy, .v0 => |m| try m.sanitize(),
        }
    }
};

const VersionedMessage = union(enum) {
    legacy: Message,
    v0: V0Message,
};

pub const V0Message = struct {
    /// The message header, identifying signed and read-only `account_keys`.
    /// Header values only describe static `account_keys`, they do not describe
    /// any additional account keys loaded via address table lookups.
    header: MessageHeader,

    /// List of accounts loaded by this transaction.
    account_keys: []Pubkey,

    /// The blockhash of a recent block.
    recent_blockhash: Hash,

    /// Instructions that invoke a designated program, are executed in sequence,
    /// and committed in one atomic transaction if all succeed.
    ///
    /// # Notes
    ///
    /// Program indexes must index into the list of message `account_keys` because
    /// program id's cannot be dynamically loaded from a lookup table.
    ///
    /// Account indexes must index into the list of addresses
    /// constructed from the concatenation of three key lists:
    ///   1) message `account_keys`
    ///   2) ordered list of keys loaded from `writable` lookup table indexes
    ///   3) ordered list of keys loaded from `readable` lookup table indexes
    instructions: []CompiledInstruction,

    /// List of address table lookups used to load additional accounts
    /// for this transaction.
    address_table_lookups: []MessageAddressTableLookup,

    pub fn sanitize(_: V0Message) !void {
        // TODO
        std.debug.print("V0Message.sanitize not implemented", .{});
    }

    pub fn addressTableLookups(self: V0Message) ?[]MessageAddressTableLookup {
        switch (self) {
            .legacy => null,
            .v0 => |m| m.address_table_lookups,
        }
    }
};

pub const MessageAddressTableLookup = struct {
    /// Address lookup table account key
    account_key: Pubkey,
    /// List of indexes used to load writable account addresses
    writable_indexes: []u8,
    /// List of indexes used to load readonly account addresses
    readonly_indexes: []u8,
};

pub const Transaction = struct {
    signatures: []Signature,
    message: Message,

    pub const @"!bincode-config:signatures" = ShortVecConfig(Signature);

    pub const MAX_BYTES: usize = 1232;

    // used in tests
    pub fn default() Transaction {
        return Transaction{
            .signatures = &[_]Signature{},
            .message = Message.default(),
        };
    }

    pub fn new_unsigned(allocator: std.mem.Allocator, message: Message) Transaction {
        return Transaction{
            .signatures = allocator.alloc(Signature, message.header.num_required_signatures),
            .message = message,
        };
    }

    pub fn clone(self: *const Transaction, allocator: std.mem.Allocator) error{OutOfMemory}!Transaction {
        return .{
            .signatures = try allocator.dupe(Signature, self.signatures),
            .message = try self.message.clone(allocator),
        };
    }

    pub fn deinit(self: *Transaction, allocator: std.mem.Allocator) void {
        allocator.free(self.signatures);
        self.message.deinit(allocator);
    }

    pub fn sanitize(self: *const Transaction) !void {
        const num_required_sigs = self.message.header.num_required_signatures;
        const num_signatures = self.signatures.len;
        if (num_required_sigs > num_signatures) {
            return error.InsufficientSignatures;
        }

        const num_account_keys = self.message.account_keys.len;
        if (num_signatures > num_account_keys) {
            return error.TooManySignatures;
        }
        try self.message.sanitize();
    }

    pub fn serialize(self: *const Transaction, allocator: std.mem.Allocator) ![]u8 {
        var buf = [_](u8){0} ** Transaction.MAX_BYTES;
        const serialized = try sig.bincode.writeToSlice(&buf, self, .{});
        return try allocator.dupe(u8, serialized);
    }
};

pub const Message = struct {
    header: MessageHeader,
    account_keys: []Pubkey,
    recent_blockhash: Hash,
    instructions: []CompiledInstruction,

    pub const @"!bincode-config:account_keys" = ShortVecConfig(Pubkey);
    pub const @"!bincode-config:instructions" = ShortVecConfig(CompiledInstruction);

    pub fn default() Message {
        return Message{
            .header = MessageHeader{
                .num_required_signatures = 0,
                .num_readonly_signed_accounts = 0,
                .num_readonly_unsigned_accounts = 0,
            },
            .account_keys = &[_]Pubkey{},
            .recent_blockhash = Hash.generateSha256Hash(&[_]u8{0}),
            .instructions = &[_]CompiledInstruction{},
        };
    }

    pub fn new(instructions: []CompiledInstruction, payer: Pubkey) !Message {
        _ = instructions;
        _ = payer;
        unreachable;
    }

    pub fn clone(self: *const Message, allocator: std.mem.Allocator) error{OutOfMemory}!Message {
        const instructions = try allocator.alloc(CompiledInstruction, self.instructions.len);
        for (instructions, 0..) |*ci, i| ci.* = try self.instructions[i].clone(allocator);
        return .{
            .header = self.header,
            .account_keys = try allocator.dupe(Pubkey, self.account_keys),
            .recent_blockhash = self.recent_blockhash,
            .instructions = instructions,
        };
    }

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        allocator.free(self.account_keys);
        for (self.instructions) |*ci| ci.deinit(allocator);
        allocator.free(self.instructions);
    }

    pub const MessageSanitizeError = error{
        NotEnoughAccounts,
        MissingWritableFeePayer,
        ProgramIdAccountMissing,
        ProgramIdCannotBePayer,
        AccountIndexOutOfBounds,
    };

    pub fn sanitize(self: *const Message) MessageSanitizeError!void {
        // number of accounts should match spec in header. signed and unsigned should not overlap.
        if (self.header.num_required_signatures +| self.header.num_readonly_unsigned_accounts > self.account_keys.len) {
            return error.NotEnoughAccounts;
        }
        // there should be at least 1 RW fee-payer account.
        if (self.header.num_readonly_signed_accounts >= self.header.num_required_signatures) {
            return error.MissingWritableFeePayer;
        }

        for (self.instructions) |ci| {
            if (ci.program_id_index >= self.account_keys.len) {
                return error.ProgramIdAccountMissing;
            }
            // A program cannot be a payer.
            if (ci.program_id_index == 0) {
                return error.ProgramIdCannotBePayer;
            }
            for (ci.accounts) |ai| {
                if (ai >= self.account_keys.len) {
                    return error.AccountIndexOutOfBounds;
                }
            }
        }
    }
};

pub const MessageHeader = struct {
    /// The number of signatures required for this message to be considered
    /// valid. The signers of those signatures must match the first
    /// `num_required_signatures` of [`Message::account_keys`].
    // NOTE: Serialization-related changes must be paired with the direct read at sigverify.
    num_required_signatures: u8,

    /// The last `num_readonly_signed_accounts` of the signed keys are read-only
    /// accounts.
    num_readonly_signed_accounts: u8,

    /// The last `num_readonly_unsigned_accounts` of the unsigned keys are
    /// read-only accounts.
    num_readonly_unsigned_accounts: u8,
};

pub const Instruction = struct {
    program_id: Pubkey,
    accounts: []AccountMeta,
    data: []u8,
};

pub const CompiledInstruction = struct {
    /// Index into the transaction keys array indicating the program account that executes this instruction.
    program_id_index: u8,
    /// Ordered indices into the transaction keys array indicating which accounts to pass to the program.
    accounts: []u8,
    /// The program input data.
    data: []u8,

    pub const @"!bincode-config:accounts" = ShortVecConfig(u8);
    pub const @"!bincode-config:data" = ShortVecConfig(u8);

    pub fn clone(self: *const CompiledInstruction, allocator: std.mem.Allocator) error{OutOfMemory}!CompiledInstruction {
        return .{
            .program_id_index = self.program_id_index,
            .accounts = try allocator.dupe(u8, self.accounts),
            .data = try allocator.dupe(u8, self.data),
        };
    }

    pub fn deinit(self: *CompiledInstruction, allocator: std.mem.Allocator) void {
        allocator.free(self.accounts);
        allocator.free(self.data);
    }
};

pub const AccountMeta = struct {
    pubkey: Pubkey,
    is_signer: bool,
    is_writable: bool,
};

pub const CompiledKeys = struct {
    maybe_payer: ?Pubkey,
    key_meta_map: std.AutoArrayHashMap(Pubkey, CompiledKeyMeta),

    pub fn compile(allocator: std.mem.Allocator, instructions: []Instruction, maybe_payer: ?Pubkey) !CompiledKeys {
        var key_meta_map = std.AutoArrayHashMap(Pubkey, CompiledKeyMeta).init(allocator);
        for (instructions) |instruction| {
            const instruction_meta_gopr = try key_meta_map.getOrPut(instruction.program_id);
            if (!instruction_meta_gopr.found_existing) {
                instruction_meta_gopr.value_ptr.* = CompiledKeyMeta.default();
            }
            instruction_meta_gopr.value_ptr.*.is_invoked = true;

            for (instruction.accounts) |account_meta| {
                const account_meta_gopr = try key_meta_map.getOrPut(account_meta.pubkey);
                if (!account_meta_gopr.found_existing) {
                    account_meta_gopr.value_ptr.* = CompiledKeyMeta.default();
                }
                account_meta_gopr.value_ptr.*.is_signer |= account_meta.is_signer;
                account_meta_gopr.value_ptr.*.is_writable |= account_meta.is_writable;
            }

            if (maybe_payer) |payer| {
                const payer_meta_gopr = try key_meta_map.getOrPut(payer);
                if (!payer_meta_gopr.found_existing) {
                    payer_meta_gopr.value_ptr.* = CompiledKeyMeta.default();
                }
                payer_meta_gopr.value_ptr.*.is_signer = true;
                payer_meta_gopr.value_ptr.*.is_writable = true;
            }
        }
        return .{ .maybe_payer = maybe_payer, .key_meta_map = key_meta_map };
    }

    /// Creates message header and account keys from the compiled keys.
    /// Account keys memory is allocated and owned by the caller.
    /// TODO: Depending on whether the order of account keys is important, the code could be
    /// optimized by simply counting the key types and appending them to account_keys direclty.
    pub fn into_message_header_and_account_keys(self: *CompiledKeys, allocator: std.mem.Allocator) !struct { MessageHeader, []Pubkey } {
        if (self.maybe_payer) |payer| {
            _ = self.key_meta_map.swapRemove(payer);
        }

        var writable_signer_keys = std.ArrayList(Pubkey).init(allocator);
        defer writable_signer_keys.deinit();
        var writable_non_signer_keys = std.ArrayList(Pubkey).init(allocator);
        defer writable_non_signer_keys.deinit();
        var readonly_signer_keys = std.ArrayList(Pubkey).init(allocator);
        defer readonly_signer_keys.deinit();
        var readonly_non_signer_keys = std.ArrayList(Pubkey).init(allocator);
        defer readonly_non_signer_keys.deinit();

        var key_meta_map_iter = self.key_meta_map.iterator();
        while (key_meta_map_iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const meta = entry.value_ptr.*;
            switch (meta.is_signer) {
                true => switch (meta.is_writable) {
                    true => try writable_signer_keys.append(key),
                    false => try readonly_signer_keys.append(key),
                },
                false => switch (meta.is_writable) {
                    true => try writable_non_signer_keys.append(key),
                    false => try readonly_non_signer_keys.append(key),
                },
            }
        }

        const header = MessageHeader{
            .num_required_signatures = writable_signer_keys.len + readonly_signer_keys.len,
            .num_readonly_signed_accounts = readonly_signer_keys.len,
            .num_readonly_unsigned_accounts = readonly_non_signer_keys.len,
        };

        const account_keys_len =
            writable_signer_keys.len +
            readonly_signer_keys.len +
            writable_non_signer_keys.len +
            readonly_non_signer_keys.len;

        var account_keys = try std.ArrayList(Pubkey).initCapacity(allocator, account_keys_len);
        try account_keys.appendSlice(writable_signer_keys.items);
        try account_keys.appendSlice(readonly_signer_keys.items);
        try account_keys.appendSlice(writable_non_signer_keys.items);
        try account_keys.appendSlice(readonly_non_signer_keys.items);

        return .{ header, account_keys.items };
    }
};

pub const CompiledKeyMeta = struct {
    is_signer: bool,
    is_writable: bool,
    is_invoked: bool,

    pub fn default() CompiledKeyMeta {
        return .{
            .is_signer = false,
            .is_writable = false,
            .is_invoked = false,
        };
    }
};

pub const CompileError = error{
    AccountIndexOverflow,
    AddressTableLookupIndexOverflow,
    UnknownInstructionKey,
};

test "core.transaction: tmp" {
    const msg = Message.default();
    try std.testing.expect(msg.account_keys.len == 0);
}

test "core.transaction: blank Message fails to sanitize" {
    try std.testing.expect(error.MissingWritableFeePayer == Message.default().sanitize());
}

test "core.transaction: minimal valid Message sanitizes" {
    var pubkeys = [_]Pubkey{Pubkey.default()};
    const message = Message{
        .header = MessageHeader{
            .num_required_signatures = 1,
            .num_readonly_signed_accounts = 0,
            .num_readonly_unsigned_accounts = 0,
        },
        .account_keys = &pubkeys,
        .recent_blockhash = Hash.generateSha256Hash(&[_]u8{0}),
        .instructions = &[_]CompiledInstruction{},
    };
    try message.sanitize();
}

test "core.transaction: Message sanitize fails if missing signers" {
    var pubkeys = [_]Pubkey{Pubkey.default()};
    const message = Message{
        .header = MessageHeader{
            .num_required_signatures = 2,
            .num_readonly_signed_accounts = 0,
            .num_readonly_unsigned_accounts = 0,
        },
        .account_keys = &pubkeys,
        .recent_blockhash = Hash.generateSha256Hash(&[_]u8{0}),
        .instructions = &[_]CompiledInstruction{},
    };
    try std.testing.expect(error.NotEnoughAccounts == message.sanitize());
}

test "core.transaction: Message sanitize fails if missing unsigned" {
    var pubkeys = [_]Pubkey{Pubkey.default()};
    const message = Message{
        .header = MessageHeader{
            .num_required_signatures = 1,
            .num_readonly_signed_accounts = 0,
            .num_readonly_unsigned_accounts = 1,
        },
        .account_keys = &pubkeys,
        .recent_blockhash = Hash.generateSha256Hash(&[_]u8{0}),
        .instructions = &[_]CompiledInstruction{},
    };
    try std.testing.expect(error.NotEnoughAccounts == message.sanitize());
}

test "core.transaction: Message sanitize fails if no writable signed" {
    var pubkeys = [_]Pubkey{ Pubkey.default(), Pubkey.default() };
    const message = Message{
        .header = MessageHeader{
            .num_required_signatures = 1,
            .num_readonly_signed_accounts = 1,
            .num_readonly_unsigned_accounts = 0,
        },
        .account_keys = &pubkeys,
        .recent_blockhash = Hash.generateSha256Hash(&[_]u8{0}),
        .instructions = &[_]CompiledInstruction{},
    };
    try std.testing.expect(error.MissingWritableFeePayer == message.sanitize());
}

test "core.transaction: Message sanitize fails if missing program id" {
    var pubkeys = [_]Pubkey{Pubkey.default()};
    var instructions = [_]CompiledInstruction{.{
        .program_id_index = 1,
        .accounts = &[_]u8{},
        .data = &[_]u8{},
    }};
    const message = Message{
        .header = MessageHeader{
            .num_required_signatures = 1,
            .num_readonly_signed_accounts = 0,
            .num_readonly_unsigned_accounts = 0,
        },
        .account_keys = &pubkeys,
        .recent_blockhash = Hash.generateSha256Hash(&[_]u8{0}),
        .instructions = &instructions,
    };
    try std.testing.expect(error.ProgramIdAccountMissing == message.sanitize());
}

test "core.transaction: Message sanitize fails if program id has index 0" {
    var pubkeys = [_]Pubkey{Pubkey.default()};
    var instructions = [_]CompiledInstruction{.{
        .program_id_index = 0,
        .accounts = &[_]u8{},
        .data = &[_]u8{},
    }};
    const message = Message{
        .header = MessageHeader{
            .num_required_signatures = 1,
            .num_readonly_signed_accounts = 0,
            .num_readonly_unsigned_accounts = 0,
        },
        .account_keys = &pubkeys,
        .recent_blockhash = Hash.generateSha256Hash(&[_]u8{0}),
        .instructions = &instructions,
    };
    try std.testing.expect(error.ProgramIdCannotBePayer == message.sanitize());
}

test "core.transaction: Message sanitize fails if account index is out of bounds" {
    var pubkeys = [_]Pubkey{ Pubkey.default(), Pubkey.default() };
    var accounts = [_]u8{2};
    var instructions = [_]CompiledInstruction{.{
        .program_id_index = 1,
        .accounts = &accounts,
        .data = &[_]u8{},
    }};
    const message = Message{
        .header = MessageHeader{
            .num_required_signatures = 1,
            .num_readonly_signed_accounts = 0,
            .num_readonly_unsigned_accounts = 1,
        },
        .account_keys = &pubkeys,
        .recent_blockhash = Hash.generateSha256Hash(&[_]u8{0}),
        .instructions = &instructions,
    };
    try std.testing.expect(error.AccountIndexOutOfBounds == message.sanitize());
}
