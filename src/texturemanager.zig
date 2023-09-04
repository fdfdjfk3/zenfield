const std = @import("std");

const sdl2 = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

const missing_texture_data = @embedFile("res/missing.png");
var missing_texture: ?*sdl2.SDL_Texture = null;

pub const TextureID = enum {
    tile_uncleared,
    tile_flagged,
    tile_mine,
    tile_0,
    tile_1,
    tile_2,
    tile_3,
    tile_4,
    tile_5,
    tile_6,
    tile_7,
    tile_8,
    button_restart_normal,
    button_restart_normal_pressed,
    button_restart_dead,
    button_restart_dead_pressed,
    button_options,
    button_options_pressed,
    button_checkbox,
    button_checkbox_checked,
};

pub const TextureManager = struct {
    renderer: *sdl2.SDL_Renderer,
    textures: std.EnumArray(TextureID, *sdl2.SDL_Texture),

    fn loadTextureRaw(self: *TextureManager, mem: []const u8) error{LoadError}!*sdl2.SDL_Texture {
        const stream = sdl2.SDL_RWFromConstMem(@ptrCast(mem), @intCast(mem.len)) orelse return error.LoadError;
        defer sdl2.SDL_FreeRW(stream);
        const surface = sdl2.IMG_LoadPNG_RW(stream) orelse return error.LoadError;
        defer sdl2.SDL_FreeSurface(surface);

        const texture: *sdl2.SDL_Texture = sdl2.SDL_CreateTextureFromSurface(self.renderer, surface) orelse return error.LoadError;
        return texture;
    }

    pub fn init(renderer: *sdl2.SDL_Renderer) TextureManager {
        var texture_manager = TextureManager{
            .renderer = renderer,
            .textures = std.EnumArray(TextureID, *sdl2.SDL_Texture).initUndefined(),
        };
        missing_texture = texture_manager.loadTextureRaw(missing_texture_data[0..]) catch @panic("Unable to load fallback texture.\n");

        return texture_manager;
    }

    pub fn loadDefaultTextures(self: *TextureManager) void {
        inline for (@typeInfo(TextureID).Enum.fields) |field| {
            self.textures.set(@enumFromInt(field.value), self.loadTextureRaw(@embedFile("res/default/" ++ field.name ++ ".png")[0..]) catch missing_texture.?);
        }
    }
};
