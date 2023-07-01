const std = @import("std");

const sdl2 = @cImport({
    @cInclude("SDL2/SDL.h");
});

const InputEvent = union(enum) {
    quit,
    keypress: struct {
        key: sdl2.SDL_Keycode,
    },
    click: struct {
        button: enum {
            left,
            right,
        },
        posx: u32,
        posy: u32,
    },
    drag: struct {
        vecx: u32,
        vecy: u32,
    },
};

const max_inputs: comptime_int = 64;
pub const InputTracker = struct {
    event_queue: std.BoundedArray(InputEvent, max_inputs).init(0),

    // 322 is the number of sdlk events from sdl2
    keys: std.bit_set.IntegerBitSet(322) = std.bit_set.IntegerBitSet(322).initFull(),

    // two primary mouse buttons
    mouse_l_down: bool = false,
    mouse_r_down: bool = false,

    mouse_pos: struct {
        x: c_int = 0,
        y: c_int = 0,
    },

    mouse_drag: bool = false,

    pub fn lastEventWasDrag(self: *InputTracker) bool {
        if (self.event_queue.len == 0) return false;
        return self.event_queue.buffer[self.event_queue.len - 1] == .drag;
    }

    pub fn updateState(self: *InputTracker) !void {
        var event: sdl2.SDL_Event = undefined;
        while (sdl2.SDL_PollEvent(&event) == 1) {
            switch (event.type) {
                sdl2.SDL_QUIT => {
                    try self.event_queue.append(.quit);

                    // no need to continue. it's going to be over soon anyways.
                    break;
                },
                sdl2.MOUSEMOTION => {
                    var temp_x: c_int = undefined;
                    var temp_y: c_int = undefined;
                    _ = sdl2.SDL_GetMouseState(&temp_x, &temp_y);

                    temp_x -= self.mouse_pos.x;
                    temp_y -= self.mouse_pos.y;

                    // if the mouse is dragging and either (temp_x/temp_y > 3 or last event was also a drag event)
                    if (self.mouse_drag and ((@fabs(temp_x) > 3 or @fabs(temp_y) > 3) or self.lastEventWasDrag())) {
                        // if the previous event was a drag event too, merge it with the last one
                        if (self.event_queue.len > 0 and self.lastEventWasDrag()) {
                            const arr_end = self.event_queue.len - 1;
                            const prior_drag_event = self.event_queue.buffer[arr_end].drag;
                            temp_x += prior_drag_event.x;
                            temp_y += prior_drag_event.y;
                            self.event_queue.buffer[arr_end] = .drag{ .x = temp_x, .y = temp_y };

                            // continue early.
                            continue;
                        }

                        self.event_queue.append(.drag{ .x = temp_x - self.mouse_pos.x, .y = temp_y - self.mouse_pos.y });
                    }
                    _ = sdl2.SDL_GetMouseState(&self.mouse_pos.x, &self.mouse_pos.y);
                    continue;
                },
                sdl2.SDL_MOUSEBUTTONDOWN => {
                    const button = event.button;
                    if (button.button == sdl2.SDL_BUTTON_LEFT) {
                        self.mouse_l_down = true;
                    } else if (button.button == sdl2.SDL_BUTTON_RIGHT) {
                        self.mouse_r_down = true;
                    }
                    continue;
                },
                sdl2.SDL_MOUSEBUTTONUP => {
                    const button = event.button;
                    if (button.button == sdl2.SDL_BUTTON_LEFT) {
                        if (self.mouse_l_down) {
                            self.mouse_l_down = false;
                            if (!self.mouse_drag) {
                                self.event_queue.append(.click{ .button = .left, .posx = self.mouse_pos.x, .posy = self.mouse_pos.y });
                            }
                            self.mouse_drag = false;
                        }
                    } else if (button.button == sdl2.SDL_BUTTON_RIGHT) {
                        if (self.mouse_r_down) {
                            self.mouse_r_down = false;
                            self.event_queue.append(.click{ .button = .right, .posx = self.mouse_pos.x, .posy = self.mouse_pos.y });
                        }
                    }
                    continue;
                },
                else => continue,
            }
        }
    }
};
