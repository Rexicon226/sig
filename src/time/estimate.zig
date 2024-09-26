const std = @import("std");
const sig = @import("../sig.zig");
const Logger = sig.trace_ng.Logger;
// const Logger = sig.trace.Logger;

// TODO: change to writer interface when logger has improved
pub fn printTimeEstimate(
    logger: *Logger,
    // timer should be started at the beginning of the loop
    timer: *sig.time.Timer,
    total: usize,
    i: usize,
    comptime name: []const u8,
    other_info: ?[]const u8,
) void {
    _ = logger;
    _ = name;
    if (i == 0 or total == 0) return;
    if (i > total) {
        if (other_info) |_| {
            // logger.infof("{s} [{s}]: {d}/{d} (?%) (est: ? elp: {s})", .{
            //     name,
            //     info,
            //     i,
            //     total,
            //     timer.read(),
            // });
        } else {
            // logger.infof("{s}: {d}/{d} (?%) (est: ? elp: {s})", .{
            //     name,
            //     i,
            //     total,
            //     timer.read(),
            // });
        }
        return;
    }

    const p_done = i * 100 / total;
    _ = p_done;
    const left = total - i;

    const elapsed = timer.read().asNanos();
    const ns_per_vec = elapsed / i;
    const ns_left = ns_per_vec * left;
    _ = ns_left;

    if (other_info) |_| {
        // logger.infof("{s} [{s}]: {d}/{d} ({d}%) (est: {s} elp: {s})", .{
        //     name,
        //     info,
        //     i,
        //     total,
        //     p_done,
        //     std.fmt.fmtDuration(ns_left),
        //     timer.read(),
        // });
    } else {
        // logger.infof("{s}: {d}/{d} ({d}%) (est: {s} elp: {s})", .{
        //     name,
        //     i,
        //     total,
        //     p_done,
        //     std.fmt.fmtDuration(ns_left),
        //     timer.read(),
        // });
    }
}
