-- board.lua
-- Playfield logic ONLY (no drawing).
--
-- The grid is 10 columns wide and 22 rows tall: 20 visible rows plus 2 hidden
-- rows above the play area. Rows are stored as grid[y][x] with y in 1..22 and
-- x in 1..10. A cell holds nil (empty) or a piece letter ("I","O",...).
--
-- The "spawn row" for newly dropped pieces sits at the top of the visible area
-- (row 3), so the two hidden rows (1 and 2) give pieces room to appear before
-- they are visible.

local Board = {}
Board.__index = Board

local Piece = require("src.piece")

local COLS = 10
local VISIBLE_ROWS = 20
local HIDDEN_ROWS = 2
local TOTAL_ROWS = VISIBLE_ROWS + HIDDEN_ROWS  -- 22
local CELL = 32  -- pixel size of one cell (used for UI sizing)

-- Row (1-based from the top of the visible play area) at which a new piece
-- spawns. Row 1 of the visible area == TOTAL_ROWS - VISIBLE_ROWS + 1.
local SPAWN_ROW = HIDDEN_ROWS + 1  -- == 3

-- Export the layout constants so the UI can translate grid rows to pixels.
Board.SPAWN_ROW     = SPAWN_ROW   -- first visible row (== 3)
Board.VISIBLE_TOP   = SPAWN_ROW   -- alias
Board.VISIBLE_ROWS  = VISIBLE_ROWS-- == 20
Board.CELL          = CELL        -- pixel size of one cell (for UI sizing)

-- Create an empty board.
function Board.new()
    local self = setmetatable({}, Board)
    self.cols = COLS
    self.totalRows = TOTAL_ROWS
    self.grid = {}
    for y = 1, TOTAL_ROWS do
        self.grid[y] = {}
        for x = 1, COLS do
            self.grid[y][x] = nil
        end
    end
    self.garbageOffset = 0  -- not used by core logic, kept for completeness
    return self
end

-- True if the given piece shape fits at (x, y) with the given rotation.
-- `piece` is a Piece object; x/y/rot override the piece's own position.
-- `allowTop` lets a piece occupy the two rows just above the visible field
-- (needed for spawning) without counting as game over.
function Board:canPlace(piece, x, y, rot)
    rot = rot or piece.rot
    local m = Piece.new(piece.type, 0, 0, rot):matrix()
    for dy = 0, 3 do
        for dx = 0, 3 do
            if m[dy + 1][dx + 1] == 1 then
                local gx = x + dx
                local gy = y + dy
                -- Horizontal bounds.
                if gx < 1 or gx > self.cols then
                    return false
                end
                -- Vertical bounds.
                if gy < 1 or gy > self.totalRows then
                    return false
                end
                -- Collision with an existing cell.
                if self.grid[gy][gx] then
                    return false
                end
            end
        end
    end
    return true
end

-- Convenience: does the piece's shape currently overlap the stack (ignoring
-- the two rows above the visible area)? Used for lock detection.
function Board:collides(piece)
    local m = piece:matrix()
    for dy = 0, 3 do
        for dx = 0, 3 do
            if m[dy + 1][dx + 1] == 1 then
                local gx = piece.x + dx
                local gy = piece.y + dy
                if gx < 1 or gx > self.cols then
                    return true
                end
                if gy > self.totalRows then
                    return true
                end
                if gy >= 1 and self.grid[gy][gx] then
                    return true
                end
            end
        end
    end
    return false
end

-- Return the resting Y for a piece moving down from (x, y, rot).
-- The returned y is the highest (smallest) y at which the piece still fits,
-- i.e. one row above where it will lock.
function Board:restingY(piece, x, y, rot)
    x = x or piece.x
    y = y or piece.y
    rot = rot or piece.rot
    while self:canPlace(piece, x, y + 1, rot) do
        y = y + 1
    end
    return y
end

-- Compute the ghost (resting) position for drawing.
function Board:ghostY(piece)
    return self:restingY(piece)
end

-- Lock the piece into the stack. `piece` must already be resting.
function Board:lock(piece)
    local m = piece:matrix()
    for dy = 0, 3 do
        for dx = 0, 3 do
            if m[dy + 1][dx + 1] == 1 then
                local gx = piece.x + dx
                local gy = piece.y + dy
                if gy >= 1 and gy <= self.totalRows and gx >= 1 and gx <= self.cols then
                    self.grid[gy][gx] = piece.type
                end
            end
        end
    end
end

-- Remove any complete rows. Returns the number of lines cleared.
-- Rows fall down after clearing (TGM gravity).
function Board:clearLines()
    local cleared = 0
    local keep = {}
    for y = 1, self.totalRows do
        local full = true
        for x = 1, self.cols do
            if not self.grid[y][x] then
                full = false
                break
            end
        end
        if full then
            cleared = cleared + 1
        else
            table.insert(keep, y)
        end
    end

    if cleared == 0 then
        return 0
    end

    -- Rebuild the grid: keep non-full rows in order, pad the top with empties.
    local newGrid = {}
    for y = 1, self.totalRows do
        newGrid[y] = {}
    end
    -- Fill from the bottom up.
    local writeRow = self.totalRows
    for i = #keep, 1, -1 do
        local src = keep[i]
        for x = 1, self.cols do
            newGrid[writeRow][x] = self.grid[src][x]
        end
        writeRow = writeRow - 1
    end
    self.grid = newGrid
    return cleared
end

-- Return true if no cell anywhere on the board is filled. Used to detect a
-- Perfect Clear (the whole field is empty after a clear), which awards Bravo.
function Board:isEmpty()
    for y = 1, self.totalRows do
        for x = 1, self.cols do
            if self.grid[y][x] then
                return false
            end
        end
    end
    return true
end

-- True if a freshly spawned piece at the spawn position cannot be placed.
-- This is the game-over test. Uses a representative piece at the spawn spot.
function Board:isTopOut()
    -- Spawn at the standard TGM horizontal centre, rotation 1.
    local sx = math.floor((self.cols - 4) / 2) + 1  -- == 4
    local p = Piece.new("I", sx, SPAWN_ROW, 1)
    return not self:canPlace(p, p.x, p.y, p.rot)
end

-- Insert a garbage row with a single hole at column `hole`.
-- Returns true if a hole column was provided (single-hole row).
function Board:insertGarbage(hole)
    -- Shift everything up by one row.
    for y = 1, self.totalRows - 1 do
        self.grid[y] = self.grid[y + 1]
    end
    -- New bottom row.
    local bottom = self.totalRows
    self.grid[bottom] = {}
    if hole then
        for x = 1, self.cols do
            self.grid[bottom][x] = "garbage"
        end
        self.grid[bottom][hole] = nil
    else
        for x = 1, self.cols do
            self.grid[bottom][x] = "garbage"
        end
    end
end

return Board
