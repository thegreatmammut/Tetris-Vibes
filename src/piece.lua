-- piece.lua
-- Tetromino definitions and the Piece object.
--
-- Each tetromino is stored as a 4x4 matrix (table of 4 rows, each a table of
-- 4 cells). A value of 1 marks a filled cell, 0 an empty one. Rotations are
-- pre-computed so the game never has to rotate matrices at runtime.
--
-- Spawn layout (TGM-style): pieces spawn flat-side-down near the top of the
-- well, centred. The matrices below are oriented so that a rotation of 0 is
-- the "flat side down" spawn orientation.

local Piece = {}
Piece.__index = Piece

-- Rotation state names used by the board/scoring (0..3).
local STATES = 4

------------------------------------------------------------------------------
-- Matrix helpers
------------------------------------------------------------------------------

-- Deep-copy a 4x4 matrix.
local function cloneMatrix(m)
    local out = {}
    for y = 1, 4 do
        out[y] = {}
        for x = 1, 4 do
            out[y][x] = m[y][x]
        end
    end
    return out
end

-- Rotate a 4x4 matrix 90 degrees clockwise (standard matrix rotation).
local function rotateCW(m)
    local out = {}
    for y = 1, 4 do
        out[y] = {}
        for x = 1, 4 do
            out[y][x] = m[5 - x][y]
        end
    end
    return out
end

-- Build all 4 rotation states for a base matrix.
local function buildStates(base)
    local states = {}
    local cur = cloneMatrix(base)
    for i = 1, STATES do
        states[i] = cloneMatrix(cur)
        cur = rotateCW(cur)
    end
    return states
end

------------------------------------------------------------------------------
-- Base (rotation 0) matrices for each tetromino.
-- These are the classic flat-side-down spawn shapes in a 4x4 box.
------------------------------------------------------------------------------

local BASE = {
    I = {
        { 0, 0, 0, 0 },
        { 1, 1, 1, 1 },
        { 0, 0, 0, 0 },
        { 0, 0, 0, 0 },
    },
    O = {
        { 0, 1, 1, 0 },
        { 0, 1, 1, 0 },
        { 0, 0, 0, 0 },
        { 0, 0, 0, 0 },
    },
    T = {
        { 0, 1, 0, 0 },
        { 1, 1, 1, 0 },
        { 0, 0, 0, 0 },
        { 0, 0, 0, 0 },
    },
    S = {
        { 0, 1, 1, 0 },
        { 1, 1, 0, 0 },
        { 0, 0, 0, 0 },
        { 0, 0, 0, 0 },
    },
    Z = {
        { 1, 1, 0, 0 },
        { 0, 1, 1, 0 },
        { 0, 0, 0, 0 },
        { 0, 0, 0, 0 },
    },
    J = {
        { 1, 0, 0, 0 },
        { 1, 1, 1, 0 },
        { 0, 0, 0, 0 },
        { 0, 0, 0, 0 },
    },
    L = {
        { 0, 0, 1, 0 },
        { 1, 1, 1, 0 },
        { 0, 0, 0, 0 },
        { 0, 0, 0, 0 },
    },
}

-- Pre-compute all rotation states for every piece type.
local STATES_TABLE = {}
for type, base in pairs(BASE) do
    STATES_TABLE[type] = buildStates(base)
end

------------------------------------------------------------------------------
-- Piece object
------------------------------------------------------------------------------

-- Create a new piece.
-- type: one of "I","O","T","S","Z","J","L"
-- x,y : spawn position in the board grid.
-- rot : rotation state 1..4 (defaults to 1 = spawn orientation).
function Piece.new(type, x, y, rot)
    assert(STATES_TABLE[type], "unknown piece type: " .. tostring(type))
    local self = setmetatable({}, Piece)
    self.type = type
    self.rot  = rot or 1
    self.x    = x
    self.y    = y
    return self
end

-- Return the 4x4 matrix for the piece's current rotation.
function Piece:matrix()
    return STATES_TABLE[self.type][self.rot]
end

-- Rotate clockwise (1..4 wraps to 1).
function Piece:rotateCW()
    self.rot = (self.rot % 4) + 1
end

-- Rotate counter-clockwise (1..4 wraps to 4).
function Piece:rotateCCW()
    self.rot = self.rot - 1
    if self.rot < 1 then self.rot = 4 end
end

-- Move by (dx, dy).
function Piece:move(dx, dy)
    self.x = self.x + dx
    self.y = self.y + dy
end

return Piece
