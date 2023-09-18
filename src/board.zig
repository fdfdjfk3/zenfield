const std = @import("std");

pub const BoardSizeOption = union(enum) {
    beginner,
    intermediate,
    expert,
    custom: struct {
        width: u32,
        height: u32,
        mines: u32,
    },
    pub fn details(self: BoardSizeOption) struct { u32, u32, u32 } {
        switch (self) {
            .beginner => return .{ 9, 9, 10 },
            .intermediate => return .{ 16, 16, 40 },
            .expert => return .{ 30, 16, 99 },
            .custom => |c| return .{ c.width, c.height, c.mines },
        }
    }
};

const max_size = 256;

const Tile = union(enum) {
    uncleared: struct {
        is_flagged: bool,
        mines_adjacent: u8,
    },
    cleared: struct {
        mines_adjacent: u8,
    },
    mine: struct {
        is_flagged: bool,
    },

    pub fn incMinesAdjacent(self: *Tile) void {
        if (self.* == .uncleared) {
            self.uncleared.mines_adjacent += 1;
        }
    }

    pub fn isFlagged(self: *const Tile) bool {
        if (self.* == .uncleared) {
            return self.uncleared.is_flagged;
        } else if (self.* == .mine) {
            return self.mine.is_flagged;
        }
        return false;
    }
};

pub const Board = struct {
    grid_width: u32,
    grid_height: u32,
    grid: [max_size][max_size]Tile,

    mines: u32,
    state: enum {
        in_progress,
        lose,
        win,
    },

    allocator: std.mem.Allocator,
    open_tile_list: std.ArrayList(std.meta.Tuple(&[_]type{ u32, u32 })),

    pub fn tileAt(self: *Board, x: u32, y: u32) !*Tile {
        if (x >= self.grid_width or y >= self.grid_height) return error.outOfBounds;
        return &self.grid[y][x];
    }

    /// creates an initial board object
    pub fn create(allocator: std.mem.Allocator) Board {
        var board = Board{
            .grid_width = 0,
            .grid_height = 0,
            .grid = [1][max_size]Tile{[1]Tile{.{ .uncleared = .{ .is_flagged = false, .mines_adjacent = 0 } }} ** max_size} ** max_size,
            .mines = 0,
            .state = .in_progress,
            .allocator = allocator,
            .open_tile_list = std.ArrayList(std.meta.Tuple(&[_]type{ u32, u32 })).initCapacity(allocator, 32) catch @panic("unable to initialize board open_tile_list\n"),
        };
        board.setMines() catch @panic("failed to set mines on board\n");
        return board;
    }

    /// sets all tiles of the active board to Tile { .uncleared = .{ .is_flagged = false, .mines_adjacent = 0 } }
    pub fn clear(self: *Board) void {
        for (self.grid[0..self.grid_height]) |*row| {
            for (row[0..self.grid_width]) |*tile| {
                tile.* = Tile{ .uncleared = .{ .is_flagged = false, .mines_adjacent = 0 } };
            }
        }
        self.state = .in_progress;
    }

    /// places all the mines down randomly. this is only called by other functions in this object because if it's not called at the right time it can potentially cause an infinite loop (if there are no spaces to put a mine)
    pub fn setMines(self: *Board) !void {
        if (self.mines > self.grid_width * self.grid_height) return error.tooManyMines;

        var rand = std.rand.DefaultPrng.init(block: {
            var seed: u64 = undefined;
            try std.os.getrandom(std.mem.asBytes(&seed));
            break :block seed;
        });
        var placed: u64 = 0;
        while (placed < self.mines) {
            const x = rand.random().intRangeAtMost(u32, 0, self.grid_width - 1);
            const y = rand.random().intRangeAtMost(u32, 0, self.grid_height - 1);
            switch (self.grid[y][x]) {
                .uncleared => {
                    self.grid[y][x] = Tile{ .mine = .{ .is_flagged = false } };
                    placed += 1;

                    // This looks messy but all its doing is incrementing all mines_adjacent values of the spots around the mine
                    const top: bool = (y > 0);
                    const bottom: bool = (y + 1 < self.grid_height);
                    const left: bool = (x > 0);
                    const right: bool = (x + 1 < self.grid_width);

                    if (top) self.grid[y - 1][x].incMinesAdjacent();
                    if (bottom) self.grid[y + 1][x].incMinesAdjacent();
                    if (left) self.grid[y][x - 1].incMinesAdjacent();
                    if (right) self.grid[y][x + 1].incMinesAdjacent();
                    if (top and left) self.grid[y - 1][x - 1].incMinesAdjacent();
                    if (top and right) self.grid[y - 1][x + 1].incMinesAdjacent();
                    if (bottom and left) self.grid[y + 1][x - 1].incMinesAdjacent();
                    if (bottom and right) self.grid[y + 1][x + 1].incMinesAdjacent();
                },
                .mine => continue,
                else => unreachable,
            }
        }
    }
    pub fn chordOpenTile(self: *Board, orig_x: u32, orig_y: u32) !bool {
        if (orig_x >= self.grid_width or orig_y >= self.grid_height) return false;
        if (self.grid[orig_y][orig_x] != .cleared) return false;

        var surrounding_flags: u32 = 0;
        var something_updated: bool = false;

        const top: u32 = if (orig_y > 0) orig_y - 1 else orig_y;
        const bottom: u32 = if (orig_y < self.grid_height - 1) orig_y + 1 else orig_y;
        const left: u32 = if (orig_x > 0) orig_x - 1 else orig_x;
        const right: u32 = if (orig_x < self.grid_width - 1) orig_x + 1 else orig_x;

        for (self.grid[top .. bottom + 1], 0..) |row, y| {
            for (row[left .. right + 1], 0..) |tile, x| {
                if (x + left == orig_x and y + top == orig_y) continue;

                if (tile.isFlagged()) surrounding_flags += 1;
            }
        }

        if (surrounding_flags == self.grid[orig_y][orig_x].cleared.mines_adjacent) {
            for (self.grid[top .. bottom + 1], 0..) |row, y| {
                for (row[left .. right + 1], 0..) |_, x| {
                    if (x + left == orig_x and y + top == orig_y) continue;

                    const updated = try self.openTile(@intCast(x + left), @intCast(y + top));
                    something_updated = something_updated or updated;
                }
            }
        }

        return something_updated;
    }

    pub fn openTile(self: *Board, i_x: u32, i_y: u32) !bool {
        if (self.state == .lose) return false;
        try self.open_tile_list.append(.{ i_x, i_y });

        while (self.open_tile_list.items.len > 0) {
            const tuple = self.open_tile_list.pop();
            const x = tuple[0];
            const y = tuple[1];

            if (x >= self.grid_width or y >= self.grid_height) continue;
            const tile: *Tile = &self.grid[y][x];
            switch (tile.*) {
                .uncleared => |info| {
                    if (info.is_flagged) continue; // can't open a flagged spot
                    tile.* = Tile{ .cleared = .{ .mines_adjacent = tile.uncleared.mines_adjacent } };
                    if (tile.cleared.mines_adjacent == 0) {
                        // open the eight adjacent squares since there can't be a mine in any of them.
                        const top: bool = (y > 0);
                        const bottom: bool = (y < self.grid_height - 1);
                        const left: bool = (x > 0);
                        const right: bool = (x < self.grid_width - 1);

                        if (left and top) try self.open_tile_list.append(.{ x - 1, y - 1 });
                        if (left) try self.open_tile_list.append(.{ x - 1, y });
                        if (left and bottom) try self.open_tile_list.append(.{ x - 1, y + 1 });
                        if (top) try self.open_tile_list.append(.{ x, y - 1 });
                        if (bottom) try self.open_tile_list.append(.{ x, y + 1 });
                        if (right and top) try self.open_tile_list.append(.{ x + 1, y - 1 });
                        if (right) try self.open_tile_list.append(.{ x + 1, y });
                        if (right and bottom) try self.open_tile_list.append(.{ x + 1, y + 1 });

                        continue;
                    }
                },
                // if the tile is already cleared, ignore!
                .cleared => continue,
                .mine => |info| {
                    if (info.is_flagged) continue;
                    self.state = .lose;
                },
            }
        }
        return true;
    }

    /// toggle a flag on the board. returns a boolean based on whether something on the board was changed
    pub fn toggleFlag(self: *Board, x: u32, y: u32) bool {
        if (self.state == .lose) return false;
        if (x >= self.grid_width or y >= self.grid_height) return false;

        var tile: *Tile = &self.grid[y][x];
        if (tile.* == .uncleared) {
            tile.uncleared.is_flagged = !tile.uncleared.is_flagged;
            return true;
        } else if (tile.* == .mine) {
            tile.mine.is_flagged = !tile.mine.is_flagged;
            return true;
        }
        return false;
    }

    pub fn clearAndResize(self: *Board, option: BoardSizeOption) !void {
        const details = option.details();
        const width = details[0];
        const height = details[1];
        const mines = details[2];

        self.grid_width = width;
        self.grid_height = height;
        self.mines = mines;
        self.clear();
        try self.setMines();
    }
};
