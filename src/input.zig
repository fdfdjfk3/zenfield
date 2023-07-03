const std = @import("std");

const sdl2 = @cImport({
    @cInclude("SDL2/SDL.h");
});

const InputEvent = union(enum) {
    quit,
    //keypress: struct {
    //    key: sdl2.SDL_Keycode,
    //},
    click: struct {
        button: enum {
            left,
            right,
        },
        posx: c_int,
        posy: c_int,
    },
    drag: struct {
        vecx: c_int,
        vecy: c_int,
    },
    window,
    scroll: c_int,
};

const max_inputs: comptime_int = 64;
pub const InputTracker = struct {
    event_queue: std.BoundedArray(InputEvent, max_inputs) = std.BoundedArray(InputEvent, max_inputs).init(0) catch @panic("couldn't init event queue\n"),

    // 322 is the number of sdlk events from sdl2 (this is unused rn)
    // keys: std.bit_set.IntegerBitSet(322) = std.bit_set.IntegerBitSet(322).initFull(),
    ctrl_down: bool = false,

    // two primary mouse buttons
    mouse_l_down: bool = false,
    moved_since_lmb_down: struct {
        x: c_int,
        y: c_int,
    } = .{ .x = 0, .y = 0 },

    mouse_r_down: bool = false,

    mouse_pos: struct {
        x: c_int,
        y: c_int,
    } = .{ .x = -1, .y = -1 },

    mouse_drag: bool = false,

    pub fn lastEventWasDrag(self: *InputTracker) bool {
        if (self.event_queue.len == 0) return false;
        return self.event_queue.buffer[self.event_queue.len - 1] == .drag;
    }

    pub fn updateState(self: *InputTracker) !void {
        self.event_queue.len = 0;
        var event: sdl2.SDL_Event = undefined;
        while (sdl2.SDL_PollEvent(&event) == 1) {
            if (self.event_queue.len >= max_inputs) return;

            switch (event.type) {
                sdl2.SDL_QUIT => {
                    try self.event_queue.append(.quit);

                    // no need to continue. it's going to be over soon anyways.
                    break;
                },
                // I hate everything about this upcoming code. but i'm too lazy to change it because it already works well enough(TM) :3
                sdl2.SDL_MOUSEMOTION => {
                    if (self.mouse_pos.x < 0 or self.mouse_pos.y < 0) {
                        _ = sdl2.SDL_GetMouseState(&self.mouse_pos.x, &self.mouse_pos.y);
                        continue;
                    }

                    var temp_x: c_int = undefined;
                    var temp_y: c_int = undefined;
                    _ = sdl2.SDL_GetMouseState(&temp_x, &temp_y);

                    temp_x -= self.mouse_pos.x;
                    temp_y -= self.mouse_pos.y;

                    if (self.mouse_l_down) {
                        self.moved_since_lmb_down.x += temp_x;
                        self.moved_since_lmb_down.y += temp_y;
                    }

                    if (try std.math.absInt(self.moved_since_lmb_down.x) > 40 or try std.math.absInt(self.moved_since_lmb_down.y) > 40) {
                        self.mouse_drag = true;
                    }

                    if (self.mouse_drag or (self.mouse_drag and self.lastEventWasDrag())) {
                        // if the previous event was a drag event too, merge it with the last one
                        if (self.event_queue.len > 0 and self.lastEventWasDrag()) {
                            const arr_end = self.event_queue.len - 1;
                            const prior_drag_event = self.event_queue.buffer[arr_end].drag;
                            temp_x += prior_drag_event.vecx;
                            temp_y += prior_drag_event.vecy;
                            self.event_queue.buffer[arr_end] = InputEvent{ .drag = .{ .vecx = temp_x, .vecy = temp_y } };

                            // continue early.
                            _ = sdl2.SDL_GetMouseState(&self.mouse_pos.x, &self.mouse_pos.y);
                            continue;
                        }

                        try self.event_queue.append(InputEvent{ .drag = .{ .vecx = temp_x, .vecy = temp_y } });
                    }
                    _ = sdl2.SDL_GetMouseState(&self.mouse_pos.x, &self.mouse_pos.y);
                    continue;
                },
                sdl2.SDL_MOUSEBUTTONDOWN => {
                    const button = event.button;
                    if (button.button == sdl2.SDL_BUTTON_LEFT) {
                        self.mouse_l_down = true;
                        self.moved_since_lmb_down.x = 0;
                        self.moved_since_lmb_down.y = 0;
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
                            self.moved_since_lmb_down.x = 0;
                            self.moved_since_lmb_down.y = 0;
                            if (!self.mouse_drag) {
                                try self.event_queue.append(InputEvent{ .click = .{ .button = .left, .posx = self.mouse_pos.x, .posy = self.mouse_pos.y } });
                            }
                        }
                        self.mouse_drag = false;
                    } else if (button.button == sdl2.SDL_BUTTON_RIGHT) {
                        if (self.mouse_r_down) {
                            self.mouse_r_down = false;
                            try self.event_queue.append(InputEvent{ .click = .{ .button = .right, .posx = self.mouse_pos.x, .posy = self.mouse_pos.y } });
                        }
                    }
                    continue;
                },
                sdl2.SDL_KEYDOWN => {
                    if (event.key.keysym.sym == sdl2.SDLK_LCTRL) {
                        self.ctrl_down = true;
                    }
                },
                sdl2.SDL_KEYUP => {
                    if (event.key.keysym.sym == sdl2.SDLK_LCTRL) {
                        self.ctrl_down = false;
                    }
                },
                sdl2.SDL_MOUSEWHEEL => {
                    const y = event.wheel.y;
                    try self.event_queue.append(InputEvent{ .scroll = y });
                },
                sdl2.SDL_WINDOWEVENT => {
                    try self.event_queue.append(.window);
                },
                else => continue,
            }
        }
    }
};
