-- ui.lua
-- HUD / layout helpers.
--
-- Draws the metal beveled frame around the well, the well background, all the
-- side panels (GRADE, NEXT GRADE AT, POINTS, LEVEL), the NEXT preview, the
-- timer, and helpers for drawing blocks/pieces into the well.
--
-- Layout (1280x720): well in the centre, GRADE/POINTS/LEVEL on the left,
-- NEXT preview and TIMER on the right.
--
-- UI.draw(game) expects a "game" table exposing:
--   game.board       (a Board)
--   game.scoring     (a Scoring)
--   game.nextPieces  (array of up to 5 piece letters for the preview)
--   game.time        (elapsed time in seconds, number)
--   game.paused      (boolean)
--   game.piece       (current active Piece, for drawing the falling piece)
--   game.ghostY      (resting Y for the ghost piece)
--   game.pieceGhost  (boolean: draw the ghost piece)

local UI = {}

local ASSETS  = require("src.assets")
local BOARD   = require("src.board")
local Piece   = require("src.piece")
local Scoring = require("src.scoring")

local CELL   = BOARD.CELL          -- 32
local COLS   = 10
local ROWS   = BOARD.VISIBLE_ROWS  -- 20
local TOP    = BOARD.VISIBLE_TOP   -- first visible row (3)

-- Well pixel rectangle.
local WELL_W = COLS * CELL           -- 320
local WELL_H = ROWS * CELL           -- 640
local WELL_X = (1280 - WELL_W) / 2   -- 480
local WELL_Y = (720 - WELL_H) / 2    -- 40

-- Side panel anchors.
local LEFT_X  = 150                  -- left panels (well frame starts at 464)
local RIGHT_X = WELL_X + WELL_W + 50 -- right panels

-- Grid row/col -> pixel.
local function rowToY(gridY)
    return WELL_Y + (gridY - TOP) * CELL
end
local function colToX(gridX)
    return WELL_X + (gridX - 1) * CELL
end

------------------------------------------------------------------------------
-- Low-level drawing helpers
------------------------------------------------------------------------------

-- Draw a block image at pixel coordinates, scaled to `size` pixels square.
-- FIX: the old call passed CELL as the shear arguments of love.graphics.draw,
-- which skewed every block wildly.
-- `shade` (optional, 0..1) darkens the image: 1 = normal, lower = darker.
function UI.drawBlock(px, py, img, alpha, size, shade)
    if not img then return end
    size = size or CELL
    alpha = alpha or 1
    shade = shade or 1
    love.graphics.setColor(shade, shade, shade, alpha)
    love.graphics.draw(img, px, py, 0, size / img:getWidth(), size / img:getHeight())
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw one grid cell (filled or empty).
function UI.drawCell(gridX, gridY, pieceType, alpha)
    local px = colToX(gridX)
    local py = rowToY(gridY)
    if pieceType then
        local img = ASSETS.blocks[pieceType] or ASSETS.blocks.garbage
        UI.drawBlock(px, py, img, alpha)
    end
    -- Empty cells draw nothing: the well is transparent with no grid lines.
end

------------------------------------------------------------------------------
-- Frame + well
------------------------------------------------------------------------------

-- Draw the metal beveled frame and the dark well background.
function UI.drawWellFrame()
    local m = 16  -- frame margin outside the well
    local x0, y0 = WELL_X - m, WELL_Y - m
    local w = WELL_W + 2 * m
    local h = WELL_H + 2 * m

    -- Draw only the frame ring (four strips) so the well interior stays
    -- fully transparent and the background shows through.
    local function ring(rx, ry, rw, rh, t)
        love.graphics.rectangle("fill", rx, ry, rw, t)                 -- top
        love.graphics.rectangle("fill", rx, ry + rh - t, rw, t)        -- bottom
        love.graphics.rectangle("fill", rx, ry + t, t, rh - 2 * t)     -- left
        love.graphics.rectangle("fill", rx + rw - t, ry + t, t, rh - 2 * t) -- right
    end

    -- Outer metal (light), 5px thick.
    love.graphics.setColor(0.55, 0.55, 0.58, 1)
    ring(x0, y0, w, h, 5)
    -- Inner metal (bevel shadow), the remaining thickness down to the well.
    love.graphics.setColor(0.35, 0.35, 0.38, 1)
    ring(x0 + 5, y0 + 5, w - 10, h - 10, m - 5)
    love.graphics.setColor(1, 1, 1, 1)
end

------------------------------------------------------------------------------
-- Piece / ghost drawing
------------------------------------------------------------------------------

-- Draw a white line on every side of the cell at grid (gx, gy) that is NOT
-- touching another block. `filled(x, y)` returns true if that grid cell holds
-- a block (stack or falling piece).
local EDGE = 2  -- line thickness in pixels
function UI.drawEdges(gx, gy, filled)
    local px, py = colToX(gx), rowToY(gy)
    love.graphics.setColor(1, 1, 1, 1)
    if not filled(gx, gy - 1) then   -- top
        love.graphics.rectangle("fill", px, py, CELL, EDGE)
    end
    if not filled(gx, gy + 1) then   -- bottom
        love.graphics.rectangle("fill", px, py + CELL - EDGE, CELL, EDGE)
    end
    if not filled(gx - 1, gy) then   -- left
        love.graphics.rectangle("fill", px, py, EDGE, CELL)
    end
    if not filled(gx + 1, gy) then   -- right
        love.graphics.rectangle("fill", px + CELL - EDGE, py, EDGE, CELL)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw a piece (or its ghost) using the board's grid coordinates.
-- The ghost uses the piece's own block image, faded and darkened.
function UI.drawPieceAt(piece, drawGhost, ghostGridY)
    local m = piece:matrix()
    local baseY = drawGhost and ghostGridY or piece.y
    for dy = 0, 3 do
        for dx = 0, 3 do
            if m[dy + 1][dx + 1] == 1 then
                local gx = piece.x + dx
                local gy = baseY + dy
                if gy >= TOP and gy <= TOP + ROWS - 1 then
                    local img = ASSETS.blocks[piece.type]
                    if drawGhost then
                        -- Same colour as the piece, but half-transparent and darker.
                        UI.drawBlock(colToX(gx), rowToY(gy), img, 0.5, nil, 0.55)
                    else
                        UI.drawBlock(colToX(gx), rowToY(gy), img, 1)
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------------
-- Panels
------------------------------------------------------------------------------

local function drawText(text, font, x, y, r, g, b, a, align)
    love.graphics.setFont(font)
    love.graphics.setColor(r, g, b, a or 1)
    love.graphics.drawText(text, x, y, 0, 1, 1, align)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw text shrunk (if needed) so it never wider than maxW.
local function drawFitText(text, font, x, y, maxW, r, g, b)
    love.graphics.setFont(font)
    love.graphics.setColor(r, g, b, 1)
    local sc = math.min(1, maxW / math.max(1, font:getWidth(text)))
    love.graphics.drawText(text, x, y, 0, sc, sc, "left")
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw the NEXT preview (up to 5 pieces) to the right of the well.
-- FIX: the old version drew every piece at the same spot, off-screen above the
-- well; now they are stacked vertically.
function UI.drawNextPreview(pieces)
    drawText("NEXT", ASSETS.fonts.medium, RIGHT_X, WELL_Y, 0.9, 0.9, 0.9, 1)
    local pcell = 24
    local n = pieces and #pieces or 0
    for i = 1, n do
        local letter = pieces[i]
        local img = letter and ASSETS.blocks[letter]
        if img then
            -- Spawn orientation only uses the top two rows of the 4x4 matrix.
            local m = Piece.new(letter, 0, 0, 1):matrix()
            local oy = WELL_Y + 40 + (i - 1) * (pcell * 2 + 14)
            for dy = 0, 1 do
                for dx = 0, 3 do
                    if m[dy + 1][dx + 1] == 1 then
                        UI.drawBlock(RIGHT_X + dx * pcell, oy + dy * pcell, img, 1, pcell)
                    end
                end
            end
        end
    end
end

-- Draw the GRADE box (top-left of the well) + NEXT GRADE AT info.
function UI.drawGradeBox(scoring)
    local boxX, boxY = LEFT_X, WELL_Y
    local boxW, boxH = 200, 116

    -- Brown/gold background.
    love.graphics.setColor(0.45, 0.30, 0.10, 1)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH)
    love.graphics.setColor(0.85, 0.65, 0.20, 1)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH)

    -- Big white grade, centred in the box.
    local font = ASSETS.fonts.large
    drawText(tostring(scoring.grade), font,
        boxX + boxW / 2, boxY + (boxH - font:getHeight()) / 2, 1, 1, 1, 1, "center")

    -- NEXT GRADE AT info below the box.
    local y = boxY + boxH + 10
    drawText("NEXT GRADE AT", ASSETS.fonts.small, boxX, y, 0.85, 0.85, 0.85, 1)
    drawFitText(tostring(scoring:nextGradePoints()), ASSETS.fonts.medium, boxX, y + 22, 280, 1, 1, 1)
    drawText("POINTS", ASSETS.fonts.small, boxX, y + 56, 0.85, 0.85, 0.85, 1)
end

-- Draw the POINTS panel (left of well, middle).
function UI.drawPointsPanel(scoring)
    local x = LEFT_X
    local y = WELL_Y + WELL_H / 2 - 20
    drawText("POINTS", ASSETS.fonts.medium, x, y, 0.9, 0.9, 0.9, 1)
    drawFitText(string.format("%08d", scoring.points), ASSETS.fonts.large, x, y + 30, 290, 1, 1, 1)
end

-- Draw the LEVEL panel (left of well, bottom).
function UI.drawLevelPanel(scoring)
    local x = LEFT_X
    local y = WELL_Y + WELL_H - 150
    drawText("LEVEL", ASSETS.fonts.medium, x, y, 0.9, 0.9, 0.9, 1)
    drawFitText(tostring(scoring.level), ASSETS.fonts.large, x, y + 26, 290, 1, 1, 1)
    -- Divider line.
    love.graphics.setColor(0.6, 0.6, 0.6, 1)
    love.graphics.rectangle("fill", x, y + 88, 90, 2)
    love.graphics.setColor(1, 1, 1, 1)
    -- Max level below.
    drawText("MAX", ASSETS.fonts.small, x, y + 96, 0.75, 0.75, 0.75, 1)
    drawText(tostring(Scoring.MAX_LEVEL or 999), ASSETS.fonts.medium, x, y + 114, 1, 1, 1, 1)
end

-- Draw the timer (MM:SS:CC = minutes:seconds:centiseconds), right of the well.
function UI.drawTimer(seconds)
    local s = math.max(0, seconds or 0)
    local totalSec = math.floor(s)
    local ss = totalSec % 60
    local mm = math.floor(totalSec / 60)
    local cc = math.floor((s - totalSec) * 100)
    local str = string.format("%02d:%02d:%02d", mm, ss, cc)
    local y = WELL_Y + WELL_H - 90
    drawText("TIME", ASSETS.fonts.medium, RIGHT_X, y, 0.9, 0.9, 0.9, 1)
    drawFitText(str, ASSETS.fonts.large, RIGHT_X, y + 28, 380, 1, 1, 1)
end

------------------------------------------------------------------------------
-- Main HUD draw
------------------------------------------------------------------------------

-- Draw the complete HUD for the given game state.
function UI.draw(game)
    UI.drawWellFrame()

    -- Filled cells of the stack (visible rows only).
    local board = game.board

    -- Used to decide which stacked-block sides get a white line. A side gets
    -- no line if it touches another block OR a wall/floor of the well. The
    -- falling piece is not part of this and gets no lines at all.
    local lastRow = TOP + ROWS - 1
    local function filled(x, y)
        if x < 1 or x > COLS or y > lastRow then return true end  -- wall / floor
        local row = board.grid[y]
        return row ~= nil and row[x] ~= nil
    end

    for gy = TOP, TOP + ROWS - 1 do
        for gx = 1, COLS do
            local cell = board.grid[gy][gx]
            if cell then
                UI.drawCell(gx, gy, cell, 1)
                UI.drawEdges(gx, gy, filled)
            end
        end
    end

    -- Ghost piece.
    if game.piece and game.pieceGhost and game.ghostY then
        UI.drawPieceAt(game.piece, true, game.ghostY)
    end
    -- Active falling piece (no edge lines).
    if game.piece then
        UI.drawPieceAt(game.piece, false, 0)
    end

    -- Panels.
    UI.drawNextPreview(game.nextPieces)
    UI.drawGradeBox(game.scoring)
    UI.drawPointsPanel(game.scoring)
    UI.drawLevelPanel(game.scoring)
    UI.drawTimer(game.time)

    -- Pause / game-over overlay handled by the scene (they draw on top).
end

return UI
