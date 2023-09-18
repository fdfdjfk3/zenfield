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

pub fn rect(x: c_int, y: c_int, w: c_int, h: c_int) sdl2.SDL_Rect {
    return .{ .x = x, .y = y, .w = w, .h = h };
}

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
pub fn getBoardTileXYOfScreenXY(brc: *BoardRenderConfig, board: *brd.Board, x: i32, y: i32) !std.meta.Tuple(&[_]type{ u32, u32 }) {
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

    var hesitating_tile: ?std.meta.Tuple(&[_]type{ u32, u32 }) = null;
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
                    if (hesitating_tile != null and x == hesitating_tile.?[0] and y == hesitating_tile.?[1] and !info.is_flagged) {
                        texture = texture_manager.textures.get(.tile_0);
                    }

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
    board_options,
    a,
};

pub const Message = union(enum) {
    clicked_on,
    input: struct {
        event: InputEvent,
        touching: bool,
    },
};

pub const Element = union(enum) {
    decoration: struct {
        rect: sdl2.SDL_Rect,
        texture: TextureID,
    },
    button: struct {
        id: u32,
        label: []const u8,
        rect: sdl2.SDL_Rect,
        texture: TextureID,
        message: *const fn (Message, *Element, *Interface, *State) bool,
    },
    pub fn newButton(
        id: u32,
        label: []const u8,
        r: sdl2.SDL_Rect,
        texture: TextureID,
        message: *const fn (Message, *Element, *Interface, *State) bool,
    ) Element {
        return Element{ .button = .{ .id = id, .label = label, .rect = r, .texture = texture, .message = message } };
    }
};

pub const Interface = struct {
    menus: std.EnumArray(MenuType, []Element) = std.EnumArray(MenuType, []Element).initUndefined(),
    menus_activated: std.EnumArray(MenuType, bool) = std.EnumArray(MenuType, bool).initFill(false),

    pub fn toggleMenu(self: *@This(), menu: MenuType) void {
        const status = self.menus_activated.get(menu);
        self.menus_activated.set(menu, !status);
    }

    pub fn registerMenu(self: *@This(), menu: MenuType, elements: []Element) void {
        self.menus.set(menu, elements);
    }

    pub fn tryToClick(self: *@This(), pos: struct { c_int, c_int }, state: *State) bool {
        for (0..self.menus.values.len) |i| {
            // if this menu is not activated, keep trying other ones
            if (!self.menus_activated.get(@enumFromInt(i))) continue;

            var elements = self.menus.getPtr(@enumFromInt(i));
            for (elements.*) |*element| {
                switch (element.*) {
                    .button => |info| {
                        if (!(pos[0] > info.rect.x and
                            pos[0] < info.rect.x + info.rect.w and
                            pos[1] > info.rect.y and
                            pos[1] < info.rect.y + info.rect.h)) continue;

                        const something_updated = info.message(.clicked_on, element, self, state);

                        if (something_updated) {
                            state.board_ready_for_redraw = true;
                        }
                        return true;
                    },
                    .decoration => return true,
                }
            }
        }
        return false;
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
            Element.newButton(0, "restart", rect(0, 0, 52, 52), .button_restart_normal, &restartBtn),
            Element.newButton(1, "options", rect(0, 52, 52, 52), .button_options, &optionsBtn),
        };
        var options = [_]Element{
            Element.newButton(2, "open board options", rect(26, 128, 32, 32), .button_options, &boardOptionsBtn),
            // Element.newButton(3, "toggle timer", rect(26, 160, 32, 32), .button_checkbox, &noMessage),
        };
        var board_options = [_]Element{
            Element.newButton(4, "beginner difficulty", rect(75, 128, 64, 64), .button_difficulty_beginner, &changeDiff),
            Element.newButton(5, "intermediate difficulty", rect(75, 200, 64, 64), .button_difficulty_intermediate, &changeDiff),
            Element.newButton(6, "expert difficulty", rect(75, 272, 64, 64), .button_difficulty_expert, &changeDiff),
        };
    };

    var interface = Interface{};

    interface.registerMenu(.main_overlay, Layouts.main_overlay[0..]);
    interface.registerMenu(.options, Layouts.options[0..]);
    interface.registerMenu(.board_options, Layouts.board_options[0..]);

    interface.menus_activated.set(.main_overlay, true);

    return interface;
}

fn noMessage(_: Message, _: *Element, _: *Interface, _: *State) bool {
    return false;
}

fn restartBtn(m: Message, _: *Element, _: *Interface, s: *State) bool {
    switch (m) {
        .clicked_on => {
            s.board_pending_restart = true;
            return true;
        },
        else => return false,
    }
}

fn boardOptionsBtn(m: Message, _: *Element, i: *Interface, _: *State) bool {
    switch (m) {
        .clicked_on => {
            i.toggleMenu(.board_options);
            return true;
        },
        else => return false,
    }
}

fn optionsBtn(m: Message, _: *Element, i: *Interface, _: *State) bool {
    switch (m) {
        .clicked_on => {
            i.toggleMenu(.options);
            i.menus_activated.set(.board_options, false);
            return true;
        },
        else => return false,
    }
}

fn changeDiff(m: Message, e: *Element, _: *Interface, s: *State) bool {
    switch (m) {
        .clicked_on => {
            s.board_size_option = switch (e.*.button.id) {
                4 => .beginner,
                5 => .intermediate,
                6 => .expert,
                else => unreachable,
            };
            s.board_size_pending_update = true;
            return false;
        },
        else => return false,
    }
}
