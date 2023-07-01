const std = @import("std");

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

    pub fn isFlagged(self: *Tile) bool {
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
    // this is the only variable that i will be mutating in external functions, and even then, it will only
    // be mutated in functions like render.GameRenderer.drawBoard();
    ready_for_redraw: bool,

    allocator: std.mem.Allocator,
    open_tile_list: std.ArrayList(std.meta.Tuple(&[_]type{ u32, u32 })),

    /// print board in text format
    pub fn debugPrint(self: *Board) void {
        for (self.grid[0..self.grid_height]) |row| {
            for (row[0..self.grid_width]) |tile| {
                std.debug.print("{any} | ", .{tile});
            }
            std.debug.print("\n", .{});
        }
    }
    /// creates an initial board object
    pub fn create(allocator: std.mem.Allocator, width: u32, height: u32, mines: u32) Board {
        var board = Board{
            .grid_width = @min(width, max_size),
            .grid_height = @min(height, max_size),
            .grid = [1][max_size]Tile{[1]Tile{.{ .uncleared = .{ .is_flagged = false, .mines_adjacent = 0 } }} ** max_size} ** max_size,
            .mines = @min(width * height, mines),
            .state = .in_progress,
            // this is true to start so render.GameRender.drawBoard() draws the initial state of the board
            .ready_for_redraw = true,
            .allocator = allocator,
            .open_tile_list = std.ArrayList(std.meta.Tuple(&[_]type{ u32, u32 })).initCapacity(allocator, 32) catch @panic("unable to initialize board open_tile_list\n"),
        };
        board.setMines() catch @panic("failed to set mines on board\n");
        return board;
    }
    /// places all the mines down randomly. this is only called by other functions in this object because if it's not called at the right time it can potentially cause an infinite loop (if there are no spaces to put a mine)
    fn setMines(self: *Board) !void {
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
                else => @panic("this shouldn't be reached. attempted to place mines on board but there were open spots, which shouldn't exist\n"),
            }
        }
    }
    pub fn chordOpenTile(self: *Board, orig_x: u32, orig_y: u32) !void {
        if (orig_x >= self.grid_width or orig_y >= self.grid_height) return;
        if (self.grid[orig_y][orig_x] != .cleared) return;

        var surrounding_flags: u32 = 0;
        const top: bool = (orig_y > 0);
        const bottom: bool = (orig_y < self.grid_height - 1);
        const left: bool = (orig_x > 0);
        const right: bool = (orig_x < self.grid_width - 1);

        if (left and top and self.grid[orig_y - 1][orig_x - 1].isFlagged()) surrounding_flags += 1;
        if (left and self.grid[orig_y][orig_x - 1].isFlagged()) surrounding_flags += 1;
        if (left and bottom and self.grid[orig_y + 1][orig_x - 1].isFlagged()) surrounding_flags += 1;
        if (top and self.grid[orig_y - 1][orig_x].isFlagged()) surrounding_flags += 1;
        if (bottom and self.grid[orig_y + 1][orig_x].isFlagged()) surrounding_flags += 1;
        if (right and top and self.grid[orig_y - 1][orig_x + 1].isFlagged()) surrounding_flags += 1;
        if (right and self.grid[orig_y][orig_x + 1].isFlagged()) surrounding_flags += 1;
        if (right and bottom and self.grid[orig_y + 1][orig_x + 1].isFlagged()) surrounding_flags += 1;

        std.debug.print("surrounding: {}\n", .{surrounding_flags});

        if (surrounding_flags == self.grid[orig_y][orig_x].cleared.mines_adjacent) {
            if (left and top) try self.openTile(orig_x - 1, orig_y - 1);
            if (left) try self.openTile(orig_x - 1, orig_y);
            if (left and bottom) try self.openTile(orig_x - 1, orig_y + 1);
            if (top) try self.openTile(orig_x, orig_y - 1);
            if (bottom) try self.openTile(orig_x, orig_y + 1);
            if (right and top) try self.openTile(orig_x + 1, orig_y - 1);
            if (right) try self.openTile(orig_x + 1, orig_y);
            if (right and bottom) try self.openTile(orig_x + 1, orig_y + 1);
        }
    }
    pub fn openTile(self: *Board, i_x: u32, i_y: u32) !void {
        if (self.state == .lose) return;
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
                    std.debug.print("0, 0 is a mine!\n", .{});
                    self.state = .lose;
                },
            }
        }
        self.ready_for_redraw = true;
    }
    pub fn toggleFlag(self: *Board, x: u32, y: u32) void {
        if (self.state == .lose) return;
        if (x >= self.grid_width or y >= self.grid_height) return;

        var tile: *Tile = &self.grid[y][x];
        if (tile.* == .uncleared) {
            tile.uncleared.is_flagged = !tile.uncleared.is_flagged;
            self.ready_for_redraw = true;
        } else if (tile.* == .mine) {
            tile.mine.is_flagged = !tile.mine.is_flagged;
            self.ready_for_redraw = true;
        }
    }
};
