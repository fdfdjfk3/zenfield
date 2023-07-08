const std = @import("std");
const brd = @import("board.zig");

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
        const default_tileset = @embedFile("res/tiles/default.png");

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
    const scale: f32 = @intToFloat(f32, brc.tilesize) / @intToFloat(f32, default_tilesize);
    const leftx: i32 = @divFloor(w, 2) - @floatToInt(i32, (@intToFloat(f32, board.grid_width) / 2.0) *
        @intToFloat(f32, brc.tilesize) + (brc.camera_offset.x * scale));
    const topy: i32 = @divFloor(h, 2) - @floatToInt(i32, (@intToFloat(f32, board.grid_height) / 2.0) *
        @intToFloat(f32, brc.tilesize) + (brc.camera_offset.y * scale));

    const tiles_from_top = @divFloor((y - topy), brc.tilesize);
    const tiles_from_left = @divFloor((x - leftx), brc.tilesize);

    if (tiles_from_top < 0 or tiles_from_left < 0) return error.outOfBounds;

    return .{ @intCast(u32, tiles_from_left), @intCast(u32, tiles_from_top) };
}

/// this function doesn't draw to the default renderer, but instead draws to the buffer passed in. this is for flexibility purposes.
/// TODO: remove all un-needed float to int conversions so precision is not lost as frequently.
/// this will help the jittering issue when zooming in and out.
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

    const scale: f32 = @intToFloat(f32, brc.tilesize) / @intToFloat(f32, default_tilesize);

    // the leftmost x and leftmost y positions. may be offscreen, so they are i32.
    const leftx: i32 = @divFloor(w, 2) - @floatToInt(i32, (@intToFloat(f32, board.grid_width) / 2.0) *
        @intToFloat(f32, brc.tilesize) + (brc.camera_offset.x * scale));
    const topy: i32 = @divFloor(h, 2) - @floatToInt(i32, (@intToFloat(f32, board.grid_height) / 2.0) *
        @intToFloat(f32, brc.tilesize) + (brc.camera_offset.y * scale));

    // this whole "hbound" and "wbound" part is just for calculating what cells actually need to be rendered
    const bottomy: i32 = topy + (brc.tilesize * @intCast(i32, board.grid_height)) + brc.tilesize;
    const rightx: i32 = leftx + (brc.tilesize * @intCast(i32, board.grid_width)) + brc.tilesize;

    // nothing needs to be rendered in this case.
    if (topy >= h or bottomy < 0 or leftx >= w or rightx < 0) {
        _ = sdl2.SDL_SetRenderTarget(brc.sdl_renderer, null);
        return;
    }

    const hbound = block: {
        const abs_topy = if (topy >= 0) 0 else -topy;
        const start = @intCast(u32, @divFloor(abs_topy, brc.tilesize));
        const end = @intCast(u32, @min(@intCast(u32, @divFloor(abs_topy + h, brc.tilesize) + 1), board.grid_height));
        break :block .{ start, end };
    };
    const wbound = block: {
        const abs_leftx = if (leftx >= 0) 0 else -leftx;
        const start = @intCast(u32, @divFloor(abs_leftx, brc.tilesize));
        const end = @intCast(u32, @min(@intCast(u32, @divFloor(abs_leftx + w, brc.tilesize) + 1), board.grid_width));
        break :block .{ start, end };
    };

    const tileset = &brc.active_tileset.?;

    // render loop
    for (board.grid[hbound[0]..hbound[1]]) |row, slice_y| {
        for (row[wbound[0]..wbound[1]]) |tile, slice_x| {
            const y = slice_y + hbound[0];
            const x = slice_x + wbound[0];

            const true_x = @intCast(c_int, leftx + (@intCast(i32, x) * brc.tilesize));
            const true_y = @intCast(c_int, topy + (@intCast(i32, y) * brc.tilesize));

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

const UiTextures = struct {
    texture: *sdl2.SDL_Texture,
    rects: struct {
        // TODO: make some of these work

        restart_normal: sdl2.SDL_Rect = .{ .x = 0, .y = 23, .w = 26, .h = 26 },
        //restart_normal_pressed: sdl2.SDL_Rect = .{ .x = 26, .y = 23, .w = 26, .h = 26 },
        //restart_nervous: sdl2.SDL_Rect = .{ .x = 0, .y = 49, .w = 26, .h = 26 },
        //restart_nervous_pressed: sdl2.SDL_Rect = .{ .x = 26, .y = 49, .w = 26, .h = 26 },
        restart_win: sdl2.SDL_Rect = .{ .x = 0, .y = 75, .w = 26, .h = 26 },
        //restart_win_pressed: sdl2.SDL_Rect = .{ .x = 26, .y = 75, .w = 26, .h = 26 },
        restart_lose: sdl2.SDL_Rect = .{ .x = 0, .y = 101, .w = 26, .h = 26 },
        //restart_lose_pressed: sdl2.SDL_Rect = .{ .x = 26, .y = 101, .w = 26, .h = 26 },
    },
};

pub const UiRenderConfig = struct {
    visible: bool = true,

    sdl_renderer: *sdl2.SDL_Renderer,
    active_textures: ?UiTextures,

    overlay: struct {
        restart: struct {
            rect: sdl2.SDL_Rect = .{ .x = 0, .y = 0, .w = 52, .h = 52 },
        } = .{},
    } = .{},

    context: enum {
        default,
        options_open,
    } = .default,

    pub fn create(renderer: *sdl2.SDL_Renderer) @This() {
        return @This(){ .sdl_renderer = renderer, .active_textures = null, .overlay = .{} };
    }

    pub fn loadDefaultTextures(self: *@This()) void {
        const default_textures = @embedFile("res/gui/default_ui.png");

        if (self.active_textures != null) {
            sdl2.SDL_DestroyTexture(self.active_textures.?.texture);
        }
        const stream: ?*sdl2.SDL_RWops = sdl2.SDL_RWFromConstMem(default_textures, default_textures.len);
        defer sdl2.SDL_FreeRW(stream);

        const sprite_surf: *sdl2.SDL_Surface = sdl2.IMG_LoadPNG_RW(stream) orelse
            @panic("couldn't load default ui textures. panicking.\n");

        defer sdl2.SDL_FreeSurface(sprite_surf);

        const texture = sdl2.SDL_CreateTextureFromSurface(self.sdl_renderer, sprite_surf) orelse
            @panic("unable to turn tilesheet surface into texture. panicking.\n");

        self.active_textures = UiTextures{ .texture = texture, .rects = .{} };
    }
};

pub fn drawUiComponents(urc: *UiRenderConfig, board: *brd.Board, buffer: *sdl2.SDL_Texture) void {
    std.debug.assert(urc.active_textures != null);
    const textures = &urc.active_textures.?;

    _ = sdl2.SDL_SetRenderTarget(urc.sdl_renderer, buffer);

    // don't clear because it needs to be rendered over the board.
    // i am currently calling drawBoard BEFORE this function, so i shouldn't clear the texture here.
    // this is a hacky workaround for now unitl i render the UI and board separately.
    // _ = sdl2.SDL_RenderClear(urc.sdl_renderer);

    if (urc.visible) {
        {
            var rect: sdl2.SDL_Rect = textures.rects.restart_normal;
            // render restart button
            switch (board.state) {
                .win => rect = textures.rects.restart_win,
                .lose => rect = textures.rects.restart_lose,
                else => {},
            }
            _ = sdl2.SDL_RenderCopy(urc.sdl_renderer, textures.texture, &rect, &urc.overlay.restart.rect);
        }

        _ = sdl2.SDL_SetRenderTarget(urc.sdl_renderer, null);
    }
}
