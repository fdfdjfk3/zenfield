const std = @import("std");
const brd = @import("board.zig");

const sdl2 = @cImport({
    @cInclude("SDL2/SDL.h");

    @cInclude("SDL2/SDL_image.h");
});

const default_tileset = @embedFile("res/tiles/default.png");

inline fn tilerect(tilesize: u16, x: u16, y: u16) sdl2.SDL_Rect {
    return .{ .x = x, .y = y, .w = tilesize, .h = tilesize };
}

fn generate_tileset(texture: *sdl2.SDL_Texture, ts: u16) Tileset {
    return Tileset{
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
};

pub const GameRenderer = struct {
    sdl_renderer: *sdl2.SDL_Renderer,
    tileset: ?Tileset,

    // board details
    camera_offset: struct {
        x: f32,
        y: f32,
    },
    tile_scale: f32,

    pub fn getTileXYOfScreenXY(self: *GameRenderer, board: *brd.Board, x: i32, y: i32) !std.meta.Tuple(&[_]type{ u32, u32 }) {
        const window = sdl2.SDL_RenderGetWindow(self.sdl_renderer);
        var w: i32 = undefined;
        var h: i32 = undefined;
        sdl2.SDL_GetWindowSize(window, &w, &h);
        const true_tilesize: i32 = @floatToInt(i32, 16 * self.tile_scale);
        const leftx: i32 = @divFloor(w, 2) - (@intCast(i32, @divFloor(board.grid_width, 2)) * true_tilesize) - @floatToInt(i32, self.camera_offset.x * self.tile_scale);
        const topy: i32 = @divFloor(h, 2) - (@intCast(i32, @divFloor(board.grid_height, 2)) * true_tilesize) - @floatToInt(i32, self.camera_offset.y * self.tile_scale);

        const tiles_from_top = @divFloor((y - topy), true_tilesize);
        const tiles_from_left = @divFloor((x - leftx), true_tilesize);

        if (tiles_from_top < 0 or tiles_from_left < 0) return error.outOfBounds;

        return .{ @intCast(u32, tiles_from_left), @intCast(u32, tiles_from_top) };
    }

    pub fn create(renderer: *sdl2.SDL_Renderer) GameRenderer {
        return GameRenderer{ .sdl_renderer = renderer, .tileset = null, .camera_offset = .{ .x = 0.0, .y = 0.0 }, .tile_scale = 1.0 };
    }

    pub fn loadDefaultTileset(self: *GameRenderer) void {
        if (self.tileset != null) {
            sdl2.SDL_DestroyTexture(self.tileset.?.texture);
        }

        const stream: ?*sdl2.SDL_RWops = sdl2.SDL_RWFromConstMem(default_tileset, default_tileset.len);
        defer sdl2.SDL_FreeRW(stream);

        const sprite_surf: *sdl2.SDL_Surface = sdl2.IMG_LoadPNG_RW(stream) orelse @panic("couldn't load default tileset. panicking.\n");
        defer sdl2.SDL_FreeSurface(sprite_surf);

        const texture = sdl2.SDL_CreateTextureFromSurface(self.sdl_renderer, sprite_surf) orelse @panic("unable to turn tilesheet surface into texture. panicking.\n");
        const tilesize = 16;
        self.tileset = generate_tileset(texture, tilesize);
    }

    /// this function doesn't draw to the default renderer, but instead draws to the buffer passed in. this is for flexibility purposes.
    pub fn drawBoard(self: *GameRenderer, board: *brd.Board, buffer: *sdl2.SDL_Texture) void {
        if (self.tileset == null) @panic("can't draw the board: tilset is not initialized\n");

        // we are drawing the board, so it shouldn't be redrawn until it's modified again
        board.ready_for_redraw = false;

        const tileset = &self.tileset.?;

        _ = sdl2.SDL_SetRenderTarget(self.sdl_renderer, buffer);
        _ = sdl2.SDL_RenderClear(self.sdl_renderer);

        const window = sdl2.SDL_RenderGetWindow(self.sdl_renderer);
        var w: i32 = undefined;
        var h: i32 = undefined;
        sdl2.SDL_GetWindowSize(window, &w, &h);

        const true_tilesize: i32 = @floatToInt(i32, 16 * self.tile_scale);

        // the leftmost x and leftmost y positions. may be offscreen, so they are i32.
        const leftx: i32 = @divFloor(w, 2) - (@intCast(i32, @divFloor(board.grid_width, 2)) * true_tilesize) - @floatToInt(i32, self.camera_offset.x * self.tile_scale);
        const topy: i32 = @divFloor(h, 2) - (@intCast(i32, @divFloor(board.grid_height, 2)) * true_tilesize) - @floatToInt(i32, self.camera_offset.y * self.tile_scale);

        _ = block: {
            const upper_bound = if (topy >= 0) 0 else @divFloor(-topy, true_tilesize);
            std.debug.assert(upper_bound >= 0);
            break :block .{ @intCast(u32, upper_bound), @intCast(u32, @divFloor(h, true_tilesize) + upper_bound) };
        };

        for (board.grid[0..board.grid_height]) |row, y| {
            for (row[0..board.grid_width]) |tile, x| {
                // const y = slice_y + hbound[0];

                const true_x = @intCast(c_int, leftx + (@intCast(i32, x) * true_tilesize));
                const true_y = @intCast(c_int, topy + (@intCast(i32, y) * true_tilesize));

                // if the tile is in a spot that is not visible, skip so not as much needs to be rendered
                if (true_x + true_tilesize < 0 or true_x > leftx + (@intCast(i32, board.grid_width) * true_tilesize) or true_y + true_tilesize < 0 or true_y > topy + (@intCast(i32, board.grid_height) * true_tilesize)) continue;

                const render_rect: sdl2.SDL_Rect = .{ .x = true_x, .y = true_y, .w = true_tilesize, .h = true_tilesize };
                switch (tile) {
                    .uncleared => |info| {
                        var rect = tileset.rects.blank;
                        if (info.is_flagged) rect = tileset.rects.flag;

                        _ = sdl2.SDL_RenderCopy(self.sdl_renderer, tileset.texture, &rect, &render_rect);
                    },
                    .cleared => |info| {
                        const mines = info.mines_adjacent;
                        if (mines > 8) @panic("somehow the number of mines of this tile was over 8. hmmm.\n");
                        _ = sdl2.SDL_RenderCopy(self.sdl_renderer, tileset.texture, &tileset.rects.nums[mines], &render_rect);
                    },
                    .mine => |info| {
                        var rect = tileset.rects.blank;
                        if (info.is_flagged) rect = tileset.rects.flag;
                        if (board.state == .lose and !info.is_flagged) rect = tileset.rects.mine;

                        _ = sdl2.SDL_RenderCopy(self.sdl_renderer, tileset.texture, &rect, &render_rect);
                    },
                }
            }
        }
        _ = sdl2.SDL_SetRenderTarget(self.sdl_renderer, null);
    }
};
