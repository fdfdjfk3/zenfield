/// Just a structure with state that should be shared across everywhere.
/// Most things that both the renderers *and* the board need should be in here.
pub const State = struct {
    board_ready_for_redraw: bool = true,
    board_pending_restart: bool = false,

    ui_ready_for_redraw: bool = true,

    texture_manager_pending_update: bool = false,
    texture_manager_activated_texture: enum {
        default,
    } = .default,
};
