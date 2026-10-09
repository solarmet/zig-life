// Conway's Game Of Life
// See: https://conwaylife.com/wiki/Conway%27s_Game_of_Life
// File format for jslife: https://conwaylife.com/wiki/Run_Length_Encoded

const raylib = @import("raylib");

pub fn main(_: @import("std").process.Init) void {
    const screen_width: c_int = 800;
    const screen_height: c_int = 600;

    raylib.InitWindow(screen_width, screen_height, "Life");
    defer raylib.CloseWindow();
    raylib.SetTargetFPS(60);

    const background = raylib.Color{ .r = 24, .g = 27, .b = 38, .a = 255 };
    const white = raylib.Color{ .r = 245, .g = 247, .b = 250, .a = 255 };

    while (!raylib.WindowShouldClose()) {
        raylib.BeginDrawing();
        raylib.ClearBackground(background);

        raylib.DrawText("Conway's Game of Life", 40, 36, 42, white);

        raylib.DrawFPS(screen_width - 90, 24);
        raylib.EndDrawing();
    }
}
