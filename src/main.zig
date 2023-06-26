const std = @import("std");
const brd = @import("board.zig");
const gui = @import("render.zig");

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

    _ = sdl2.SDL_SetHint(sdl2.SDL_HINT_RENDER_SCALE_QUALITY, 0);

    const bmpfilestream: ?*sdl2.SDL_RWops = sdl2.SDL_RWFromConstMem(window_icon, window_icon.len);
    const icon: ?*sdl2.SDL_Surface = sdl2.SDL_LoadBMP_RW(bmpfilestream, 1);
    if (icon == null) {
        sdl2.SDL_Log("failed to load window icon. error: %s\n", sdl2.SDL_GetError());
    }
    sdl2.SDL_SetWindowIcon(window, icon);
    sdl2.SDL_SetWindowMinimumSize(window, 150, 100);

    var board: brd.Board = brd.Board.create(allocator, 9, 9, 10);
    //board.openTile(0, 0);
    //board.openTile(10, 15);
    //board.openTile(20, 0);
    //board.openTile(4, 4);
    //std.debug.print("{any}\n", .{board.grid[1][2]});
    //board.debugPrint();

    var game_renderer = gui.GameRenderer.create(renderer);
    game_renderer.loadDefaultTileset();
    std.debug.print("{any}\n", .{game_renderer});

    _ = sdl2.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    _ = sdl2.SDL_RenderClear(renderer);
    _ = sdl2.SDL_RenderPresent(renderer);

    var screen_buffer: *sdl2.SDL_Texture = sdl2.SDL_CreateTexture(renderer, 0, sdl2.SDL_TEXTUREACCESS_TARGET, displaymode.w, displaymode.h) orelse {
        sdl2.SDL_Log("failed to create screen buffer. error: %s\n", sdl2.SDL_GetError());
        return;
    };
    const screen_rect: sdl2.SDL_Rect = .{ .x = 0, .y = 0, .w = displaymode.w, .h = displaymode.h };
    game: while (true) {
        var event: sdl2.SDL_Event = undefined;

        if (sdl2.SDL_PollEvent(&event) == 1) {
            switch (event.type) {
                sdl2.SDL_QUIT => break :game,
                sdl2.SDL_MOUSEMOTION => {
                    var x: c_int = undefined;
                    var y: c_int = undefined;
                    _ = sdl2.SDL_GetMouseState(&x, &y);
                    sdl2.SDL_Log("mouse moved, it's now at: %d, %d", x, y);
                    continue;
                },
                // re-render in case something happened to window
                sdl2.SDL_WINDOWEVENT => {
                    if (event.window.event == sdl2.SDL_WINDOWEVENT_RESIZED) {
                        board.ready_for_redraw = true;
                        continue;
                    }
                    _ = sdl2.SDL_RenderCopy(renderer, screen_buffer, null, &screen_rect);
                    _ = sdl2.SDL_RenderPresent(renderer);
                    continue;
                },
                sdl2.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        sdl2.SDLK_a => {
                            sdl2.SDL_Log("a\n");
                            game_renderer.camera_offset.x -= 5;
                            board.ready_for_redraw = true;
                            continue;
                        },
                        sdl2.SDLK_d => {
                            game_renderer.camera_offset.x += 5;
                            board.ready_for_redraw = true;
                            continue;
                        },
                        else => continue,
                    }
                },
                sdl2.SDL_MOUSEWHEEL => {
                    if (event.wheel.y > 0) {
                        game_renderer.tile_scale += 0.1;
                        board.ready_for_redraw = true;
                    } else if (event.wheel.y < 0) {
                        board.ready_for_redraw = true;
                        game_renderer.tile_scale -= 0.1;
                    }
                    continue;
                },
                sdl2.SDL_MOUSEBUTTONDOWN => {
                    const button = event.button;
                    if (button.button == sdl2.SDL_BUTTON_LEFT) {
                        const xy = game_renderer.getTileXYOfScreenXY(&board, button.x, button.y) catch continue;
                        board.openTile(xy[0], xy[1]) catch {
                            @panic("opening tile failed\n");
                        };
                    } else if (button.button == sdl2.SDL_BUTTON_RIGHT) {
                        const xy = game_renderer.getTileXYOfScreenXY(&board, button.x, button.y) catch continue;
                        board.toggleFlag(xy[0], xy[1]);
                    }
                    continue;
                },
                else => continue,
            }
        }
        if (board.ready_for_redraw) {
            game_renderer.drawBoard(&board, screen_buffer);
            _ = sdl2.SDL_RenderCopy(renderer, screen_buffer, null, &screen_rect);
            _ = sdl2.SDL_RenderPresent(renderer);
        }

        sdl2.SDL_Delay(10);
    }
}
