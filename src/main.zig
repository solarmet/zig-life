// Conway's Game Of Life
// See: https://conwaylife.com/wiki/Conway%27s_Game_of_Life
// File format for jslife: https://conwaylife.com/wiki/Run_Length_Encoded

const std = @import("std");
const rl = @import("raylib");

const BACKGROUND = rl.Color{ .r = 24, .g = 27, .b = 38, .a = 255 };
const WHITE = rl.Color{ .r = 245, .g = 247, .b = 250, .a = 255 };
const BLUE = rl.Color{ .r = 200, .g = 200, .b = 250, .a = 255 };
const RED = rl.Color{ .r = 255, .g = 20, .b = 20, .a = 255 };
const SCREEN_WIDTH: c_int = 1920;
const SCREEN_HEIGHT: c_int = 1080;

const State = union(enum) {
    browser: Browser,
};

const Frame = union(enum) {
    browser: Browser.Frame,
};

pub fn main(init: std.process.Init) !void {
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
            .selection_is_dir = false,
            .simulation = null,
        },
    };

    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Life");
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

        rl.DrawFPS(SCREEN_WIDTH - 90, 24);
        rl.EndDrawing();
    }

    switch (state) {
        .browser => |browser_state| {
            allocator.free(browser_state.selection.?);
        },
    }
}

const Browser = struct {
    current_dir: std.Io.Dir,
    selection: ?[]u8,
    selection_is_dir: bool,
    selection_update: SelectionUpdate,
    simulation: ?std.Io.File,

    const Entry = struct {
        next: ?*Entry,
        previous: ?*Entry,
        name: [:0]u8,
        color: rl.Color,
    };

    const Frame = struct {
        entry_head: ?*Entry,
        entry_tail: ?*Entry,
    };

    const SelectionUpdate = enum {
        none,
        next,
        previous,
        into,
    };

    fn update(
        self: *Browser,
        allocator: std.mem.Allocator,
        frame_allocator: std.mem.Allocator,
        io: std.Io,
    ) !Browser.Frame {
        var browser_frame: Browser.Frame = .{
            .entry_head = null,
            .entry_tail = null,
        };

        if (rl.IsKeyPressed(rl.KEY_DOWN)) {
            self.selection_update = .next;
        } else if (rl.IsKeyPressed(rl.KEY_UP)) {
            self.selection_update = .previous;
        } else if (rl.IsKeyPressed(rl.KEY_ENTER)) {
            self.selection_update = .into;
        }

        if (self.selection_update == .into) {
            if (self.selection_is_dir) {
                const child = try self.current_dir.openDir(io, self.selection.?, .{ .iterate = true });
                self.current_dir.close(io);
                self.current_dir = child;
                self.selection_update = .none;
                self.selection = null;
                self.selection_is_dir = false;
            }
        }

        var it = self.current_dir.iterate();
        var previous: ?[]u8 = null;
        var previous_is_dir: bool = false;
        while (try it.next(io)) |entry| {
            if (self.selection == null) {
                self.selection = try std.fmt.allocPrint(allocator, "{s}", .{entry.name});
                self.selection_is_dir = entry.kind == .directory;
            }

            const buf: [:0]u8 = try frame_allocator.allocSentinel(u8, 256, 0);
            @memset(buf, 0);

            var color = if (entry.kind == .directory) BLUE else WHITE;

            if (std.mem.eql(u8, entry.name, self.selection.?)) {
                switch (self.selection_update) {
                    .next => {
                        allocator.free(self.selection.?);
                        self.selection = null;
                        self.selection_update = .none;
                        _ = try std.fmt.bufPrint(buf, "  {s}", .{entry.name});
                    },
                    .previous => {
                        if (previous) |_| {
                            allocator.free(self.selection.?);
                            self.selection = try std.fmt.allocPrint(allocator, "{s}", .{previous.?});
                            self.selection_is_dir = previous_is_dir;
                            self.selection_update = .none;
                        }
                    },
                    .into => {
                        self.selection_update = .none;
                    },
                    .none => {
                        _ = try std.fmt.bufPrint(buf, "> {s}", .{entry.name});
                        color = RED;
                    },
                }
            } else {
                _ = try std.fmt.bufPrint(buf, "  {s}", .{entry.name});
            }

            const previous_entry = browser_frame.entry_tail;
            browser_frame.entry_tail = try frame_allocator.create(Entry);
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
            previous_is_dir = entry.kind == .directory;
        }

        if (self.selection_update == .previous) {
            if (previous) |_| {
                allocator.free(self.selection.?);
                self.selection = try std.fmt.allocPrint(allocator, "{s}", .{previous.?});
                self.selection_is_dir = previous_is_dir;
            }

            self.selection_update = .none;
        }

        return browser_frame;
    }
};
