// Conway's Game Of Life
// See: https://conwaylife.com/wiki/Conway%27s_Game_of_Life
// File format for jslife: https://conwaylife.com/wiki/Run_Length_Encoded

const std = @import("std");
const rl = @import("raylib");

const BACKGROUND = rl.Color{ .r = 24, .g = 27, .b = 38, .a = 255 };
const WHITE = rl.Color{ .r = 245, .g = 247, .b = 250, .a = 255 };
const BLUE = rl.Color{ .r = 20, .g = 20, .b = 250, .a = 255 };
const RED = rl.Color{ .r = 255, .g = 20, .b = 20, .a = 255 };

const SelectionUpdate = enum {
    none,
    next,
    previous,
};

const Browser = struct {
    current_dir: std.Io.Dir,
    selection: ?[]u8,
    selection_update: SelectionUpdate,
};

const BrowserEntry = struct {
    next: ?*BrowserEntry,
    name: [:0]u8,
    color: rl.Color,
};

const State = union(enum) {
    browser: Browser,
};

const Frame = struct {
    listing_root: ?*BrowserEntry,
};

pub fn main(init: std.process.Init) !void {
    const screen_width: c_int = 1920;
    const screen_height: c_int = 1080;

    const io = init.io;
    const allocator = init.gpa;

    const storage: []u8 = try allocator.alloc(u8, 4 * 1024 * 1024);
    defer allocator.free(storage);
    var frame_fba = std.heap.FixedBufferAllocator.init(storage);

    const frame_allocator = frame_fba.allocator();

    var state: State = .{
        .browser = .{
            .current_dir = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true }),
            .selection = null,
            .selection_update = .none,
        },
    };

    rl.InitWindow(screen_width, screen_height, "Life");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        frame_fba.reset();
        var frame = Frame{
            .listing_root = null,
        };

        // Update
        switch (state) {
            .browser => |*browser_state| {
                if (rl.IsKeyPressed(rl.KEY_UP)) {
                    browser_state.selection_update = .next;
                } else if (rl.IsKeyPressed(rl.KEY_DOWN)) {
                    browser_state.selection_update = .previous;
                }

                var it = browser_state.current_dir.iterate();
                var previous: ?[]u8 = null;
                while (try it.next(io)) |entry| {
                    if (browser_state.selection == null) {
                        browser_state.selection = try std.fmt.allocPrint(allocator, "{s}", .{entry.name});
                    }

                    const buf: [:0]u8 = try frame_allocator.allocSentinel(u8, 256, 0);
                    @memset(buf, 0);

                    var color = if (entry.kind == .directory) BLUE else WHITE;

                    if (std.mem.eql(u8, entry.name, browser_state.selection.?)) {
                        if (browser_state.selection_update == .next) {
                            allocator.free(browser_state.selection.?);
                            browser_state.selection = null;
                            browser_state.selection_update = .none;
                            _ = try std.fmt.bufPrint(buf, " {s}", .{entry.name});
                        } else if (browser_state.selection_update == .previous) {
                            if (previous) |_| {
                                allocator.free(browser_state.selection.?);
                                browser_state.selection = try std.fmt.allocPrint(allocator, "{s}", .{previous.?});
                            }
                            browser_state.selection_update = .none;
                        } else {
                            _ = try std.fmt.bufPrint(buf, "> {s}", .{entry.name});
                            color = RED;
                        }
                    } else {
                        _ = try std.fmt.bufPrint(buf, " {s}", .{entry.name});
                    }

                    const next = frame.listing_root;
                    frame.listing_root = try frame_allocator.create(BrowserEntry);
                    frame.listing_root.?.* = .{
                        .next = next,
                        .name = buf,
                        .color = color,
                    };

                    previous = try std.fmt.allocPrint(frame_allocator, "{s}", .{entry.name});
                }
            },
        }

        // Render
        rl.BeginDrawing();
        rl.ClearBackground(BACKGROUND);

        switch (state) {
            .browser => {
                const x: i32 = 50;
                var y: i32 = 50;
                var it = frame.listing_root;
                while (it) |entry| {
                    rl.DrawText(entry.name, x, y, 42, entry.color);
                    y = y + 50;
                    it = entry.next;
                }
            },
        }

        rl.DrawFPS(screen_width - 90, 24);
        rl.EndDrawing();
    }
}
