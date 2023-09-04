const std = @import("std");
const brd = @import("board.zig");
const State = @import("state.zig").State;
const InputEvent = @import("input.zig").InputEvent;
const TextureManager = @import("texturemanager.zig").TextureManager;
const TextureID = @import("texturemanager.zig").TextureID;

const sdl2 = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

pub const default_tilesize = 16;
pub const BoardRenderConfig = struct {
    sdl_renderer: *sdl2.SDL_Renderer,

    // board details
    camera_offset: struct {
        x: f32,
        y: f32,
    },
    tilesize: c_int = 16,

    pub fn create(renderer: *sdl2.SDL_Renderer) @This() {
        return @This(){ .sdl_renderer = renderer, .camera_offset = .{ .x = 0.0, .y = 0.0 }, .tilesize = default_tilesize };
    }
};

/// get the X, Y position of the board based on the X, Y position on the screen. takes in BoardRenderConfig to accurately make this calculation.
/// returns an error if the X, Y is not on the board.
pub fn getBoardTileXYOfScreenXY(brc: *BoardRenderConfig, board: *brd.Board, x: i32, y: i32) !struct { u32, u32 } {
    const window = sdl2.SDL_RenderGetWindow(brc.sdl_renderer);
    var w: i32 = undefined;
    var h: i32 = undefined;
    sdl2.SDL_GetWindowSize(window, &w, &h);
    const scale: f32 = @as(f32, @floatFromInt(brc.tilesize)) / @as(f32, @floatFromInt(default_tilesize));
    const leftx: i32 = @divFloor(w, 2) - @as(i32, @intFromFloat((@as(f32, @floatFromInt(board.grid_width)) / 2.0) *
        @as(f32, @floatFromInt(brc.tilesize)) + (brc.camera_offset.x * scale)));
    const topy: i32 = @divFloor(h, 2) - @as(i32, @intFromFloat((@as(f32, @floatFromInt(board.grid_height)) / 2.0) *
        @as(f32, @floatFromInt(brc.tilesize)) + (brc.camera_offset.y * scale)));

    const tiles_from_top = @divFloor((y - topy), brc.tilesize);
    const tiles_from_left = @divFloor((x - leftx), brc.tilesize);

    if (tiles_from_top < 0 or tiles_from_left < 0) return error.outOfBounds;

    return .{ @intCast(tiles_from_left), @intCast(tiles_from_top) };
}

/// this function doesn't draw to the default renderer, but instead draws to the buffer passed in. this is for flexibility purposes.
pub fn drawBoard(brc: *BoardRenderConfig, board: *brd.Board, buffer: *sdl2.SDL_Texture, texture_manager: *TextureManager) void {
    // no need to render that.
    if (brc.tilesize < 1) {
        return;
    }

    _ = sdl2.SDL_SetRenderTarget(brc.sdl_renderer, buffer);
    _ = sdl2.SDL_RenderClear(brc.sdl_renderer);

    const window = sdl2.SDL_RenderGetWindow(brc.sdl_renderer);
    var w: i32 = undefined;
    var h: i32 = undefined;
    sdl2.SDL_GetWindowSize(window, &w, &h);

    const scale: f32 = @as(f32, @floatFromInt(brc.tilesize)) / @as(f32, @floatFromInt(default_tilesize));

    // the leftmost x and leftmost y positions. may be offscreen, so they are i32.
    const leftx: i32 = @divFloor(w, 2) - @as(i32, @intFromFloat((@as(f32, @floatFromInt(board.grid_width)) / 2.0) *
        @as(f32, @floatFromInt(brc.tilesize)) + (brc.camera_offset.x * scale)));
    const topy: i32 = @divFloor(h, 2) - @as(i32, @intFromFloat((@as(f32, @floatFromInt(board.grid_height)) / 2.0) *
        @as(f32, @floatFromInt(brc.tilesize)) + (brc.camera_offset.y * scale)));

    // this whole "hbound" and "wbound" part is just for calculating what cells actually need to be rendered
    const bottomy: i32 = topy + (brc.tilesize * @as(i32, @intCast(board.grid_height))) + brc.tilesize;
    const rightx: i32 = leftx + (brc.tilesize * @as(i32, @intCast(board.grid_width))) + brc.tilesize;

    // nothing needs to be rendered in this case.
    if (topy >= h or bottomy < 0 or leftx >= w or rightx < 0) {
        _ = sdl2.SDL_SetRenderTarget(brc.sdl_renderer, null);
        return;
    }

    const hbound = block: {
        const abs_topy = if (topy >= 0) 0 else -topy;
        const start: u32 = @intCast(@divFloor(abs_topy, brc.tilesize));
        const end: u32 = @intCast(@min(@as(u32, @intCast(@divFloor(abs_topy + h, brc.tilesize) + 1)), board.grid_height));
        break :block .{ start, end };
    };
    const wbound = block: {
        const abs_leftx = if (leftx >= 0) 0 else -leftx;
        const start: u32 = @intCast(@divFloor(abs_leftx, brc.tilesize));
        const end: u32 = @intCast(@min(@as(u32, @intCast(@divFloor(abs_leftx + w, brc.tilesize) + 1)), board.grid_width));
        break :block .{ start, end };
    };

    // render loop
    for (board.grid[hbound[0]..hbound[1]], 0..) |row, slice_y| {
        for (row[wbound[0]..wbound[1]], 0..) |tile, slice_x| {
            const y = slice_y + hbound[0];
            const x = slice_x + wbound[0];

            const true_x = @as(c_int, @intCast(leftx + (@as(i32, @intCast(x)) * brc.tilesize)));
            const true_y = @as(c_int, @intCast(topy + (@as(i32, @intCast(y)) * brc.tilesize)));

            const render_rect: sdl2.SDL_Rect = .{ .x = true_x, .y = true_y, .w = brc.tilesize, .h = brc.tilesize };
            switch (tile) {
                .uncleared => |info| {
                    var texture = texture_manager.textures.get(.tile_uncleared);
                    if (info.is_flagged) texture = texture_manager.textures.get(.tile_flagged);

                    _ = sdl2.SDL_RenderCopy(brc.sdl_renderer, texture, null, &render_rect);
                },
                .cleared => |info| {
                    const mines = info.mines_adjacent;
                    const texture = switch (mines) {
                        0 => texture_manager.textures.get(.tile_0),
                        1 => texture_manager.textures.get(.tile_1),
                        2 => texture_manager.textures.get(.tile_2),
                        3 => texture_manager.textures.get(.tile_3),
                        4 => texture_manager.textures.get(.tile_4),
                        5 => texture_manager.textures.get(.tile_5),
                        6 => texture_manager.textures.get(.tile_6),
                        7 => texture_manager.textures.get(.tile_7),
                        8 => texture_manager.textures.get(.tile_8),
                        else => @panic("somehow the number of mines of this tile was over 8. hmmm.\n"),
                    };

                    _ = sdl2.SDL_RenderCopy(brc.sdl_renderer, texture, null, &render_rect);
                },
                .mine => |info| {
                    var texture = texture_manager.textures.get(.tile_uncleared);
                    if (info.is_flagged) texture = texture_manager.textures.get(.tile_flagged);
                    if (board.state == .lose and !info.is_flagged) texture = texture_manager.textures.get(.tile_mine);

                    _ = sdl2.SDL_RenderCopy(brc.sdl_renderer, texture, null, &render_rect);
                },
            }
        }
    }
    _ = sdl2.SDL_SetRenderTarget(brc.sdl_renderer, null);
}

//---------------------------
// UI stuff beyond this point
//---------------------------

pub const MenuType = enum {
    main_overlay,
    options,
};

pub const Element = union(enum) {
    decoration: struct {
        rect: sdl2.SDL_Rect,
        texture: TextureID,
    },
    button: struct {
        label: []const u8,
        rect: sdl2.SDL_Rect,
        texture: TextureID,
        on_click: *const fn (*Element, *Interface, *State) bool,
        on_step: ?*const fn (*Element, *Interface, *State, []InputEvent) bool,
    },
};

pub const Interface = struct {
    menus: std.EnumArray(MenuType, []Element) = std.EnumArray(MenuType, []Element).initUndefined(),
    menus_activated: std.EnumArray(MenuType, bool) = std.EnumArray(MenuType, bool).initFill(false),

    pub fn toggleMenu(self: *Interface, menu: MenuType) void {
        self.menus_activated.set(menu, !self.menus_activated.get(menu));
    }

    pub fn registerMenu(comptime self: *@This(), comptime menu: MenuType, comptime elements: []Element) void {
        self.menus.set(menu, elements);
    }
};

pub fn drawInterface(interface: *Interface, buffer: *sdl2.SDL_Texture, texture_manager: *TextureManager) void {
    _ = sdl2.SDL_SetRenderTarget(texture_manager.renderer, buffer);
    // _ = sdl2.SDL_RenderClear(texture_manager.renderer);

    for (0..interface.menus.values.len) |i| {
        if (interface.menus_activated.get(@enumFromInt(i))) {
            for (interface.menus.get(@enumFromInt(i))) |element| {
                switch (element) {
                    .button => |btn| {
                        _ = sdl2.SDL_RenderCopy(texture_manager.renderer, texture_manager.textures.get(btn.texture), null, &btn.rect);
                    },
                    else => @panic("unimplemented\n"),
                }
            }
        }
    }

    _ = sdl2.SDL_SetRenderTarget(texture_manager.renderer, null);
}

pub fn createInterface() Interface {
    const Layouts = struct {
        var main_overlay = [_]Element{
            .{ .button = .{ .label = "restart", .rect = .{ .x = 0, .y = 0, .w = 52, .h = 52 }, .texture = .button_restart_normal, .on_click = &onClickRestartBtn, .on_step = &onStepRestartBtn } },
            .{ .button = .{ .label = "options", .rect = .{ .x = 0, .y = 52, .w = 52, .h = 52 }, .texture = .button_options, .on_click = onClickOptionsBtn, .on_step = null } },
        };
        var options = [_]Element{
            .{ .button = .{ .label = "toggle timer", .rect = .{ .x = 26, .y = 128, .w = 32, .h = 32 }, .texture = .button_checkbox, .on_click = &onClickDoNothing, .on_step = null } },
        };
    };

    var interface = Interface{};

    interface.registerMenu(.main_overlay, Layouts.main_overlay[0..]);
    interface.registerMenu(.options, Layouts.options[0..]);

    interface.menus_activated.set(.main_overlay, true);

    return interface;
}

fn onClickDoNothing(_: *Element, _: *Interface, _: *State) bool {
    return false;
}

fn onClickRestartBtn(_: *Element, _: *Interface, s: *State) bool {
    s.board_pending_restart = true;
    return false;
}

fn onStepRestartBtn(_: *Element, _: *Interface, _: *State, _: []InputEvent) bool {
    // Todo!
    return false;
}

fn onClickOptionsBtn(_: *Element, i: *Interface, _: *State) bool {
    i.toggleMenu(.options);
    return true;
}
