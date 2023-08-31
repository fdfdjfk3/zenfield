const std = @import("std");
const brd = @import("board.zig");
const State = @import("state.zig").State;

const sdl2 = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

inline fn tilerect(tilesize: u16, x: u16, y: u16) sdl2.SDL_Rect {
    return .{ .x = x, .y = y, .w = tilesize, .h = tilesize };
}

const Tileset = struct {
    texture: *sdl2.SDL_Texture,
    rects: struct {
        nums: [9]sdl2.SDL_Rect,
        uncleared: sdl2.SDL_Rect,
        flag: sdl2.SDL_Rect,
        mine: sdl2.SDL_Rect,
        blank: sdl2.SDL_Rect,
        unknown: sdl2.SDL_Rect, // fallback tile texture if none of the others apply (somehow)
    },
    pub fn from(texture: *sdl2.SDL_Texture, ts: u16) @This() {
        return @This(){
            .texture = texture,
            .rects = .{
                .nums = [9]sdl2.SDL_Rect{
                    tilerect(ts, ts * 2, 0),
                    tilerect(ts, 0, ts),
                    tilerect(ts, ts, ts),
                    tilerect(ts, ts * 2, ts),
                    tilerect(ts, ts * 3, ts),
                    tilerect(ts, 0, ts * 2),
                    tilerect(ts, ts, ts * 2),
                    tilerect(ts, ts * 2, ts * 2),
                    tilerect(ts, ts * 3, ts * 2),
                },
                .uncleared = tilerect(ts, 0, 0),
                .flag = tilerect(ts, ts, 0),
                .mine = tilerect(ts, ts * 3, 0),
                .blank = tilerect(ts, 0, 0),
                .unknown = tilerect(ts, ts, ts * 3),
            },
        };
    }
};

pub const default_tilesize = 16;
pub const BoardRenderConfig = struct {
    sdl_renderer: *sdl2.SDL_Renderer,
    active_tileset: ?Tileset,

    // board details
    camera_offset: struct {
        x: f32,
        y: f32,
    },
    tilesize: c_int = 16,

    pub fn create(renderer: *sdl2.SDL_Renderer) @This() {
        return @This(){ .sdl_renderer = renderer, .active_tileset = null, .camera_offset = .{ .x = 0.0, .y = 0.0 }, .tilesize = default_tilesize };
    }

    /// Loads the default tileset that will always be embedded in the file.
    pub fn loadDefaultTileset(self: *@This()) void {
        const default_tileset = @embedFile("res/default/tileset.png");

        if (self.active_tileset != null) {
            sdl2.SDL_DestroyTexture(self.active_tileset.?.texture);
        }
        const stream: ?*sdl2.SDL_RWops = sdl2.SDL_RWFromConstMem(default_tileset, default_tileset.len);
        defer sdl2.SDL_FreeRW(stream);

        const sprite_surf: *sdl2.SDL_Surface = sdl2.IMG_LoadPNG_RW(stream) orelse
            @panic("couldn't load default tileset. panicking.\n");

        defer sdl2.SDL_FreeSurface(sprite_surf);

        const texture = sdl2.SDL_CreateTextureFromSurface(self.sdl_renderer, sprite_surf) orelse
            @panic("unable to turn tilesheet surface into texture. panicking.\n");

        const tilesize = 16;
        self.active_tileset = Tileset.from(texture, tilesize);
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
pub fn drawBoard(brc: *BoardRenderConfig, board: *brd.Board, buffer: *sdl2.SDL_Texture) void {
    std.debug.assert(brc.active_tileset != null);

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

    const tileset = &brc.active_tileset.?;

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
                    var rect = tileset.rects.blank;
                    if (info.is_flagged) rect = tileset.rects.flag;

                    _ = sdl2.SDL_RenderCopy(brc.sdl_renderer, tileset.texture, &rect, &render_rect);
                },
                .cleared => |info| {
                    const mines = info.mines_adjacent;
                    if (mines > 8) @panic("somehow the number of mines of this tile was over 8. hmmm.\n");
                    _ = sdl2.SDL_RenderCopy(brc.sdl_renderer, tileset.texture, &tileset.rects.nums[mines], &render_rect);
                },
                .mine => |info| {
                    var rect = tileset.rects.blank;
                    if (info.is_flagged) rect = tileset.rects.flag;
                    if (board.state == .lose and !info.is_flagged) rect = tileset.rects.mine;

                    _ = sdl2.SDL_RenderCopy(brc.sdl_renderer, tileset.texture, &rect, &render_rect);
                },
            }
        }
    }
    _ = sdl2.SDL_SetRenderTarget(brc.sdl_renderer, null);
}

//---------------------------
// UI stuff beyond this point
//---------------------------

const Button = struct {
    rect: sdl2.SDL_Rect,
    is_active: bool,
};

const UiTexture = enum {
    restart_normal,
    restart_normal_pressed,
    restart_nervous,
    restart_nervous_pressed,
    restart_win,
    restart_win_pressed,
    restart_lose,
    restart_lose_pressed,
    settings,
    settings_pressed,
    settings_button,
    settings_button_unchecked,
};

pub const ButtonEvent = enum {
    reset_board,
    toggle_settings,
    toggle_timer,
};

fn initTextureLookup() std.EnumArray(UiTexture, sdl2.SDL_Rect) {
    var arr = std.EnumArray(UiTexture, sdl2.SDL_Rect).initUndefined();
    arr.set(.restart_normal, .{ .x = 0, .y = 23, .w = 26, .h = 26 });
    arr.set(.restart_normal_pressed, .{ .x = 26, .y = 23, .w = 26, .h = 26 });
    arr.set(.restart_nervous, .{ .x = 0, .y = 49, .w = 26, .h = 26 });
    arr.set(.restart_nervous_pressed, .{ .x = 26, .y = 49, .w = 26, .h = 26 });
    arr.set(.restart_win, .{ .x = 0, .y = 75, .w = 26, .h = 26 });
    arr.set(.restart_win_pressed, .{ .x = 26, .y = 75, .w = 26, .h = 26 });
    arr.set(.restart_lose, .{ .x = 0, .y = 101, .w = 26, .h = 26 });
    arr.set(.restart_lose_pressed, .{ .x = 26, .y = 101, .w = 26, .h = 26 });
    arr.set(.settings, .{ .x = 52, .y = 23, .w = 26, .h = 26 });
    arr.set(.settings_pressed, .{ .x = 78, .y = 23, .w = 26, .h = 26 });
    arr.set(.settings_button, .{ .x = 52, .y = 49, .w = 16, .h = 16 });
    arr.set(.settings_button_unchecked, .{ .x = 68, .y = 49, .w = 16, .h = 16 });

    return arr;
}

pub const UiRenderConfig = struct {
    visible: bool = true,

    sdl_renderer: *sdl2.SDL_Renderer,

    active_texture: ?*sdl2.SDL_Texture,

    t_rects: std.EnumArray(UiTexture, sdl2.SDL_Rect) = initTextureLookup(),
    buttons: [3]Button = [3]Button{
        .{ // restart button
            .rect = .{ .x = 0, .y = 0, .w = 52, .h = 52 },
            .is_active = true,
        },
        .{ // open settings button pos
            .rect = .{ .x = 0, .y = 52, .w = 52, .h = 52 },
            .is_active = true,
        },
        .{ // toggle timer button
            .rect = .{ .x = 26, .y = 128, .w = 32, .h = 32 },
            .is_active = false,
        },
    },

    settings_open: bool = false,

    pub fn create(renderer: *sdl2.SDL_Renderer) @This() {
        return @This(){
            .sdl_renderer = renderer,
            .active_texture = null,
        };
    }

    pub fn loadDefaultTextures(self: *@This()) void {
        const default_textures = @embedFile("res/default/ui.png");

        if (self.active_texture != null) {
            sdl2.SDL_DestroyTexture(self.active_texture.?);
        }
        const stream: ?*sdl2.SDL_RWops = sdl2.SDL_RWFromConstMem(default_textures, default_textures.len);
        defer sdl2.SDL_FreeRW(stream);

        const sprite_surf: *sdl2.SDL_Surface = sdl2.IMG_LoadPNG_RW(stream) orelse
            @panic("couldn't load default ui textures. panicking.\n");

        defer sdl2.SDL_FreeSurface(sprite_surf);

        const texture = sdl2.SDL_CreateTextureFromSurface(self.sdl_renderer, sprite_surf) orelse
            @panic("unable to turn tilesheet surface into texture. panicking.\n");

        self.active_texture = texture;
    }

    pub fn posIsOnUi(self: *UiRenderConfig, x: c_int, y: c_int) bool {
        for (&self.buttons) |button| {
            if (button.is_active and
                button.rect.x <= x and
                (button.rect.x + button.rect.w) >= x and
                button.rect.y <= y and
                button.rect.y + button.rect.h >= y) return true;
        }
        return false;
    }

    pub fn clickButtonAtXY(self: *UiRenderConfig, x: c_int, y: c_int, state: *State) void {
        for (&self.buttons, 0..) |button, i| {
            if (!(button.is_active and
                button.rect.x <= x and
                (button.rect.x + button.rect.w) >= x and
                button.rect.y <= y and
                button.rect.y + button.rect.h >= y)) continue;

            switch (i) {
                0 => state.board_pending_restart = true,
                1 => self.toggleSettingsMenu(),

                else => unreachable,
            }
            break;
        }
        // temp, use ui_ready_for_redraw as soon as it's ready to be used that way
        state.board_ready_for_redraw = true;
    }

    fn toggleSettingsMenu(self: *UiRenderConfig) void {
        self.settings_open = !self.settings_open;
        self.buttons[2].is_active = self.settings_open;
    }
};

pub fn drawUiComponents(urc: *UiRenderConfig, _: *brd.Board, buffer: *sdl2.SDL_Texture) void {
    std.debug.assert(urc.active_texture != null);

    _ = sdl2.SDL_SetRenderTarget(urc.sdl_renderer, buffer);
    const texture = urc.active_texture;

    // don't clear because it needs to be rendered over the board.
    // i am currently calling drawBoard BEFORE this function, so i shouldn't clear the texture here.
    // this is a hacky workaround for now unitl i render the UI and board separately.
    // _ = sdl2.SDL_RenderClear(urc.sdl_renderer);

    if (urc.visible) {
        if (urc.buttons[0].is_active) _ = sdl2.SDL_RenderCopy(urc.sdl_renderer, texture, &urc.t_rects.get(.restart_normal), &urc.buttons[0].rect);
        if (urc.buttons[1].is_active) _ = sdl2.SDL_RenderCopy(urc.sdl_renderer, texture, &urc.t_rects.get(.settings), &urc.buttons[1].rect);
        if (urc.buttons[2].is_active) _ = sdl2.SDL_RenderCopy(urc.sdl_renderer, texture, &urc.t_rects.get(.settings_button), &urc.buttons[2].rect);

        _ = sdl2.SDL_SetRenderTarget(urc.sdl_renderer, null);
    }
}
