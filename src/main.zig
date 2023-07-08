const std = @import("std");
const brd = @import("board.zig");
const gui = @import("render.zig");
const input = @import("input.zig");

const sdl2 = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

const window_icon = @embedFile("res/icon.bmp");

/// this is for if the user has more than one display. if they have 2 or more screens, it will choose the largest one and that will be the maximu window size.
pub fn getLargestDisplayRect() !sdl2.SDL_Rect {
    var num_displays = sdl2.SDL_GetNumVideoDisplays();

    var largest_rect: sdl2.SDL_Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };

    var i: c_int = 0;
    while (i < num_displays) : (i += 1) {
        var rect: sdl2.SDL_Rect = undefined;
        if (sdl2.SDL_GetDisplayBounds(i, &rect) < 0) {
            return error.ErrorCheckingDisplay;
        }

        if (rect.w > largest_rect.w or rect.h > largest_rect.h) {
            largest_rect = rect;
        }
    }
    return largest_rect;
}

pub fn main() !void {
    // Initialize the library
    if (sdl2.SDL_Init(sdl2.SDL_INIT_EVERYTHING) < 0) {
        sdl2.SDL_Log("SDL_Init failed. error: %s\n", sdl2.SDL_GetError());
        return;
    }
    if (sdl2.IMG_Init(sdl2.IMG_INIT_PNG) < 0) {
        sdl2.SDL_Log("IMG_Init failed. error: %s\n", sdl2.IMG_GetError());
        return;
    }
    // prepare these to be de-initialized after the program ends
    defer sdl2.SDL_Quit();
    defer sdl2.IMG_Quit();

    const displaymode = getLargestDisplayRect() catch {
        sdl2.SDL_Log("error finding largest display. error: %s\n", sdl2.SDL_GetError());
        return;
    };

    // window and renderer
    var window: *sdl2.SDL_Window = sdl2.SDL_CreateWindow("zenfield", 0, 0, displaymode.w, displaymode.h, sdl2.SDL_WINDOW_RESIZABLE | sdl2.SDL_WINDOW_MAXIMIZED) orelse {
        sdl2.SDL_Log("SDL_CreateWindow failed. error: %s\n", sdl2.SDL_GetError());
        return;
    };
    var renderer: *sdl2.SDL_Renderer = sdl2.SDL_CreateRenderer(window, -1, sdl2.SDL_RENDERER_ACCELERATED | sdl2.SDL_RENDERER_PRESENTVSYNC) orelse {
        sdl2.SDL_Log("SDL_CreateRenderer failed. error: %s\n", sdl2.SDL_GetError());
        return;
    };
    defer sdl2.SDL_DestroyWindow(window);
    defer sdl2.SDL_DestroyRenderer(renderer);

    _ = sdl2.SDL_SetHint(sdl2.SDL_HINT_RENDER_SCALE_QUALITY, "0");
    _ = sdl2.SDL_SetHint(sdl2.SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");

    const bmpfilestream: ?*sdl2.SDL_RWops = sdl2.SDL_RWFromConstMem(window_icon, window_icon.len);
    const icon: ?*sdl2.SDL_Surface = sdl2.SDL_LoadBMP_RW(bmpfilestream, 1);
    if (icon == null) {
        sdl2.SDL_Log("failed to load window icon. error: %s\n", sdl2.SDL_GetError());
    }
    sdl2.SDL_SetWindowIcon(window, icon);
    sdl2.SDL_SetWindowMinimumSize(window, 150, 100);

    var board: brd.Board = brd.Board.create(allocator, 100, 100, 1500);

    // initialize render data thing
    var board_render_config = gui.BoardRenderConfig.create(renderer);
    board_render_config.loadDefaultTileset();

    var ui_render_config = gui.UiRenderConfig.create(renderer);
    ui_render_config.loadDefaultTextures();

    var inputs = input.InputTracker{};

    _ = sdl2.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    _ = sdl2.SDL_RenderClear(renderer);
    _ = sdl2.SDL_RenderPresent(renderer);

    var screen_buffer: *sdl2.SDL_Texture = sdl2.SDL_CreateTexture(renderer, sdl2.SDL_PIXELFORMAT_RGBA8888, sdl2.SDL_TEXTUREACCESS_TARGET, displaymode.w, displaymode.h) orelse {
        sdl2.SDL_Log("failed to create screen buffer. error: %s\n", sdl2.SDL_GetError());
        return;
    };

    const screen_rect: sdl2.SDL_Rect = .{ .x = 0, .y = 0, .w = displaymode.w, .h = displaymode.h };

    game: while (true) {
        inputs.updateState() catch @panic("error collecting input events\n");
        for (inputs.event_queue.buffer[0..inputs.event_queue.len]) |event| {
            switch (event) {
                .quit => break :game,
                .click => |details| {
                    switch (details.button) {
                        .left => {
                            const tilexy = gui.getBoardTileXYOfScreenXY(&board_render_config, &board, details.posx, details.posy) catch continue;
                            const tile = board.tileAt(tilexy[0], tilexy[1]) catch continue;
                            if (tile.* == .cleared) try board.chordOpenTile(tilexy[0], tilexy[1]);
                            try board.openTile(tilexy[0], tilexy[1]);
                        },
                        .right => {
                            const tilexy = gui.getBoardTileXYOfScreenXY(&board_render_config, &board, details.posx, details.posy) catch continue;
                            board.toggleFlag(tilexy[0], tilexy[1]);
                        },
                    }
                    continue;
                },
                .drag => |details| {
                    const scale: f32 = @intToFloat(f32, board_render_config.tilesize) / @intToFloat(f32, gui.default_tilesize);
                    board_render_config.camera_offset.x += @intToFloat(f32, -details.vecx) / scale;
                    board_render_config.camera_offset.y += @intToFloat(f32, -details.vecy) / scale;
                    board.ready_for_redraw = true;
                    continue;
                },
                .window => {
                    board.ready_for_redraw = true;
                    continue;
                },
                .scroll => |y| {
                    if (y < 0) {
                        if (board_render_config.tilesize > 1) board_render_config.tilesize -= 1;
                    } else {
                        if (board_render_config.tilesize < 100) board_render_config.tilesize += 1;
                    }
                    board.ready_for_redraw = true;
                },
            }
        }

        if (board.ready_for_redraw) {
            // render the board and then ui on top of it
            board.ready_for_redraw = false;
            gui.drawBoard(&board_render_config, &board, screen_buffer);
            gui.drawUiComponents(&ui_render_config, &board, screen_buffer);
            _ = sdl2.SDL_RenderCopy(renderer, screen_buffer, null, &screen_rect);
            _ = sdl2.SDL_RenderPresent(renderer);
        }

        sdl2.SDL_Delay(10);
    }
}
