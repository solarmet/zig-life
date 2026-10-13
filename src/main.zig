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

    fn update(
        self: *Browser,
        allocator: std.mem.Allocator,
        frame_allocator: std.mem.Allocator,
        io: std.Io,
    ) !BrowserFrame {
        var browser_frame: BrowserFrame = .{
            .entry_head = null,
            .entry_tail = null,
        };

        if (rl.IsKeyPressed(rl.KEY_DOWN)) {
            self.selection_update = .next;
        } else if (rl.IsKeyPressed(rl.KEY_UP)) {
            self.selection_update = .previous;
        }

        var it = self.current_dir.iterate();
        var previous: ?[]u8 = null;
        while (try it.next(io)) |entry| {
            if (self.selection == null) {
                self.selection = try std.fmt.allocPrint(allocator, "{s}", .{entry.name});
            }

            const buf: [:0]u8 = try frame_allocator.allocSentinel(u8, 256, 0);
            @memset(buf, 0);

            var color = if (entry.kind == .directory) BLUE else WHITE;

            if (std.mem.eql(u8, entry.name, self.selection.?)) {
                if (self.selection_update == .next) {
                    allocator.free(self.selection.?);
                    self.selection = null;
                    self.selection_update = .none;
                    _ = try std.fmt.bufPrint(buf, " {s}", .{entry.name});
                } else if (self.selection_update == .previous) {
                    if (previous) |_| {
                        allocator.free(self.selection.?);
                        self.selection = try std.fmt.allocPrint(allocator, "{s}", .{previous.?});
                        self.selection_update = .none;
                    }
                } else {
                    _ = try std.fmt.bufPrint(buf, "> {s}", .{entry.name});
                    color = RED;
                }
            } else {
                _ = try std.fmt.bufPrint(buf, " {s}", .{entry.name});
            }

            const previous_entry = browser_frame.entry_tail;
            browser_frame.entry_tail = try frame_allocator.create(BrowserEntry);
            if (previous_entry) |e| {
                e.next = browser_frame.entry_tail;
            }
            browser_frame.entry_tail.?.* = .{
                .next = null,
                .previous = previous_entry,
                .name = buf,
                .color = color,
            };

            if (browser_frame.entry_head == null) {
                browser_frame.entry_head = browser_frame.entry_tail;
            }

            previous = try std.fmt.allocPrint(frame_allocator, "{s}", .{entry.name});
        }

        if (self.selection_update == .previous) {
            if (previous) |_| {
                allocator.free(self.selection.?);
                self.selection = try std.fmt.allocPrint(allocator, "{s}", .{previous.?});
            }

            self.selection_update = .none;
        }

        return browser_frame;
    }
};

const BrowserEntry = struct {
    next: ?*BrowserEntry,
    previous: ?*BrowserEntry,
    name: [:0]u8,
    color: rl.Color,
};

const State = union(enum) {
    browser: Browser,
};

const BrowserFrame = struct {
    entry_head: ?*BrowserEntry,
    entry_tail: ?*BrowserEntry,
};

const Frame = union(enum) {
    browser: BrowserFrame,
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
        var frame: Frame = undefined;

        // Update
        switch (state) {
            .browser => |*browser| {
                const browser_frame = try browser.update(allocator, frame_allocator, io);
                frame = .{ .browser = browser_frame };
            },
        }

        // Render
        rl.BeginDrawing();
        rl.ClearBackground(BACKGROUND);

        switch (frame) {
            .browser => |browser_frame| {
                const x: i32 = 50;
                var y: i32 = 50;
                var it = browser_frame.entry_head;
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

    switch (state) {
        .browser => |browser_state| {
            allocator.free(browser_state.selection.?);
        },
    }
}
