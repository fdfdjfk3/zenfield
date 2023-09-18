const std = @import("std");
const BoardSizeOption = @import("board.zig").BoardSizeOption;

/// Just a structure with state that should be shared across everywhere.
/// Most things that both the renderers *and* the board need should be in here.
pub const State = struct {
    board_ready_for_redraw: bool = true,
    board_pending_restart: bool = false,

    board_size_option: BoardSizeOption = .intermediate,
    board_size_pending_update: bool = false,

    ui_ready_for_redraw: bool = true,
};
