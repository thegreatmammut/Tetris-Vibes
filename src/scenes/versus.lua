-- scenes/versus.lua
-- Versus scene: the player (left well) against a computer opponent (right well).
--
-- Each side has its own board, 7-bag, falling piece, gravity and lock delay.
-- Clearing lines sends garbage to the opponent: every cleared line queues one
-- grey garbage row containing GARBAGE_BLOCKS_PER_LINE (4) grey blocks. Queued
-- garbage is shown as a red meter beside the well and lands in the opponent's
-- well after their next piece locks without clearing a line. Clearing lines
-- yourself first cancels garbage you have waiting. First side to top out loses.
--
-- Controls (same as the single player game):
--   Left / Right : move (DAS)     Down : soft drop      Up : hard drop
--   Z / X        : rotate CCW/CW  Escape : pause menu

local Assets = require("src.assets")
local Board  = require("src.board")
local Piece  = require("src.piece")
local Bag    = require("src.bag")

----------------------------------------------------------------------------
-- Tunables
----------------------------------------------------------------------------
local STEP = 1 / 60                  -- fixed logic step (seconds)
local LOCK_FRAMES = 30
local LOCK_MAX_RESETS = 15
local DAS_FRAMES = 16
local ARR_FRAMES = 4
local SPAWN_X = 4
local SPAWN_Y = Board.SPAWN_ROW

local GARBAGE_BLOCKS_PER_LINE = 4    -- grey blocks sent per cleared line
local MAX_GARBAGE_PER_DROP = 8       -- max garbage rows landing at once

-- Gravity (frames per row): starts slow and speeds up as the match goes on.
local GRAVITY_START_FRAMES = 48
local GRAVITY_MIN_FRAMES   = 6
local GRAVITY_STEP_FRAMES  = 3       -- frames removed per speed-up
local GRAVITY_STEP_SECONDS = 15      -- seconds between speed-ups

-- Computer opponent difficulty presets (chosen in the title menu).
--   actionFrames : frames between CPU moves/rotations (bigger = slower)
--   thinkFrames  : extra pause after each new piece appears
--   noise        : random wobble added to move scores (bigger = sloppier)
--   mistake      : chance per piece that the CPU just picks a random spot
--   lineWeight   : how much it values clearing lines (aggression)
--   lookahead    : also plans for the next piece
--   hardDrop     : slams pieces down (false = soft-drops them instead)
--   sendMul      : multiplier on garbage the CPU sends
--   recvMul      : multiplier on garbage the CPU receives
local DIFFICULTIES = {
    easy   = { name = "EASY",   actionFrames = 16, thinkFrames = 24, noise = 3.0, mistake = 0.25,
               lineWeight = 0.5, lookahead = false, hardDrop = false, sendMul = 1, recvMul = 1 },
    medium = { name = "MEDIUM", actionFrames = 8,  thinkFrames = 12, noise = 0.8, mistake = 0.08,
               lineWeight = 1.0, lookahead = false, hardDrop = true,  sendMul = 1, recvMul = 1 },
    hard   = { name = "HARD",   actionFrames = 3,  thinkFrames = 4,  noise = 0.1, mistake = 0,
               lineWeight = 1.3, lookahead = true,  hardDrop = true,  sendMul = 1, recvMul = 1 },
    -- Unfair: instant, near-perfect play, sends double garbage and only
    -- takes half of what you send.
    unfair = { name = "UNFAIR", actionFrames = 1,  thinkFrames = 0,  noise = 0,   mistake = 0,
               lineWeight = 1.6, lookahead = true,  hardDrop = true,  sendMul = 2, recvMul = 0.5 },
}

----------------------------------------------------------------------------
-- Layout (1280x720 virtual space)
----------------------------------------------------------------------------
local CELL = Board.CELL
local COLS = 10
local ROWS = Board.VISIBLE_ROWS
local TOP  = Board.VISIBLE_TOP
local WELL_W = COLS * CELL           -- 320
local WELL_H = ROWS * CELL           -- 640
local WELL_Y = (720 - WELL_H) / 2    -- 40
local PLAYER_X = 150
local CPU_X    = 810
local PCELL = 20                     -- preview cell size

local function rowToY(gridY) return WELL_Y + (gridY - TOP) * CELL end

local function isConfirm(key) return key == "return" or key == "kpenter" end

----------------------------------------------------------------------------
-- Drawing helpers
----------------------------------------------------------------------------
local function drawBlock(px, py, img, alpha, size, shade)
    if not img then return end
    size = size or CELL
    love.graphics.setColor(shade or 1, shade or 1, shade or 1, alpha or 1)
    love.graphics.draw(img, px, py, 0, size / img:getWidth(), size / img:getHeight())
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawWellFrame(wx)
    local m = 16
    local x0, y0 = wx - m, WELL_Y - m
    local w, h = WELL_W + 2 * m, WELL_H + 2 * m
    local function ring(rx, ry, rw, rh, t)
        love.graphics.rectangle("fill", rx, ry, rw, t)
        love.graphics.rectangle("fill", rx, ry + rh - t, rw, t)
        love.graphics.rectangle("fill", rx, ry + t, t, rh - 2 * t)
        love.graphics.rectangle("fill", rx + rw - t, ry + t, t, rh - 2 * t)
    end
    love.graphics.setColor(0.55, 0.55, 0.58, 1)
    ring(x0, y0, w, h, 5)
    love.graphics.setColor(0.35, 0.35, 0.38, 1)
    ring(x0 + 5, y0 + 5, w - 10, h - 10, m - 5)
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawText(text, font, x, y, r, g, b, align)
    love.graphics.setFont(font)
    love.graphics.setColor(r, g, b, 1)
    love.graphics.drawText(text, x, y, 0, 1, 1, align or "left")
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw one side's well: stack, ghost, falling piece and incoming-garbage meter.
local function drawWell(side, wx, showGhost)
    drawWellFrame(wx)
    local board = side.board
    local lastRow = TOP + ROWS - 1

    local function filled(x, y)
        if x < 1 or x > COLS or y > lastRow then return true end
        local row = board.grid[y]
        return row ~= nil and row[x] ~= nil
    end

    for gy = TOP, lastRow do
        for gx = 1, COLS do
            local cell = board.grid[gy][gx]
            if cell then
                local px, py = wx + (gx - 1) * CELL, rowToY(gy)
                drawBlock(px, py, Assets.blocks[cell] or Assets.blocks.garbage, 1)
                love.graphics.setColor(1, 1, 1, 1)
                if not filled(gx, gy - 1) then love.graphics.rectangle("fill", px, py, CELL, 2) end
                if not filled(gx, gy + 1) then love.graphics.rectangle("fill", px, py + CELL - 2, CELL, 2) end
                if not filled(gx - 1, gy) then love.graphics.rectangle("fill", px, py, 2, CELL) end
                if not filled(gx + 1, gy) then love.graphics.rectangle("fill", px + CELL - 2, py, 2, CELL) end
            end
        end
    end

    local p = side.piece
    if p and not side.dead then
        local m = p:matrix()
        local img = Assets.blocks[p.type]
        local gyBase = showGhost and board:ghostY(p) or nil
        for dy = 0, 3 do
            for dx = 0, 3 do
                if m[dy + 1][dx + 1] == 1 then
                    local gx = p.x + dx
                    if gyBase then
                        local gy = gyBase + dy
                        if gy >= TOP and gy <= lastRow then
                            drawBlock(wx + (gx - 1) * CELL, rowToY(gy), img, 0.5, nil, 0.55)
                        end
                    end
                end
            end
        end
        for dy = 0, 3 do
            for dx = 0, 3 do
                if m[dy + 1][dx + 1] == 1 then
                    local gx, gy = p.x + dx, p.y + dy
                    if gy >= TOP and gy <= lastRow then
                        drawBlock(wx + (gx - 1) * CELL, rowToY(gy), img, 1)
                    end
                end
            end
        end
    end

    -- Incoming garbage meter (red bar growing up from the bottom, left of well).
    if side.pending > 0 then
        local h = math.min(WELL_H, side.pending * CELL)
        love.graphics.setColor(0.9, 0.15, 0.15, 1)
        love.graphics.rectangle("fill", wx - 30, WELL_Y + WELL_H - h, 8, h)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- Small NEXT preview column for one side.
local function drawNext(side, x)
    drawText("NEXT", Assets.fonts.small, x, 84, 0.85, 0.85, 0.85)
    local list = {}
    if side.nextType then list[1] = side.nextType end
    local more = side.bag:peek(2)
    for i = 1, #more do list[#list + 1] = more[i] end
    for i = 1, #list do
        local img = Assets.blocks[list[i]]
        local m = Piece.new(list[i], 0, 0, 1):matrix()
        local oy = 108 + (i - 1) * (PCELL * 2 + 14)
        for dy = 0, 1 do
            for dx = 0, 3 do
                if m[dy + 1][dx + 1] == 1 then
                    drawBlock(x + dx * PCELL, oy + dy * PCELL, img, 1, PCELL)
                end
            end
        end
    end
end

----------------------------------------------------------------------------
-- Side: one player's board + piece logic (used for both human and CPU)
----------------------------------------------------------------------------
local Side = {}
Side.__index = Side

function Side.new(isCpu, diff)
    local s = setmetatable({}, Side)
    s.isCpu = isCpu
    s.diff = diff or { sendMul = 1, recvMul = 1 }
    s.board = Board.new()
    s.bag = Bag.new()
    s.piece = nil
    s.nextType = nil
    s.lines = 0
    s.pending = 0          -- garbage rows waiting to land on this side
    s.sent = 0             -- garbage rows this side has sent out
    s.dead = false
    s.dropCounter = 0
    s.resting = false
    s.lockTimer = 0
    s.lockResets = 0
    s.soft = false
    s.opponent = nil
    s.plan = nil           -- CPU: { x =, rot = }
    s.cpuTimer = 0
    s.cpuStuck = 0
    return s
end

function Side:spawn()
    local kind = self.nextType or self.bag:next()
    self.nextType = self.bag:next()
    local p = Piece.new(kind, SPAWN_X, SPAWN_Y, 1)
    self.piece = p
    self.resting = false
    self.lockTimer = 0
    self.lockResets = 0
    self.dropCounter = 0
    self.plan = nil
    self.cpuTimer = -(self.diff.thinkFrames or 0)
    self.cpuStuck = 0
    if self.isCpu then self.soft = false end
    if not self.board:canPlace(p, p.x, p.y, p.rot) then
        self.dead = true
    end
end

-- Push the stack up one row and add a grey row with N random grey blocks.
function Side:insertGarbageRow()
    local g = self.board.grid
    local total = self.board.totalRows
    for y = 1, total - 1 do g[y] = g[y + 1] end
    local cols = {}
    for x = 1, COLS do cols[x] = x end
    for i = COLS, 2, -1 do
        local j = math.random(i)
        cols[i], cols[j] = cols[j], cols[i]
    end
    local row = {}
    for i = 1, math.min(GARBAGE_BLOCKS_PER_LINE, COLS) do
        row[cols[i]] = "garbage"
    end
    g[total] = row
end

function Side:lock()
    local p = self.piece
    if not p then return end
    self.board:lock(p)
    self.piece = nil
    if not self.isCpu then Assets.play("lock") end

    local cleared = self.board:clearLines()
    if cleared > 0 then
        if not self.isCpu then Assets.play("clear" .. math.min(cleared, 4)) end
        self.lines = self.lines + cleared
        -- Cancel garbage waiting on this side first, send the rest across.
        local out = cleared
        local cancel = math.min(self.pending, out)
        self.pending = self.pending - cancel
        out = out - cancel
        if out > 0 and self.opponent then
            local rows = math.floor(out * (self.diff.sendMul or 1)
                * (self.opponent.diff.recvMul or 1) + 0.5)
            if rows < 1 then rows = 1 end
            self.opponent.pending = self.opponent.pending + rows
            self.sent = self.sent + rows
        end
    else
        -- No clear: incoming garbage lands now.
        local n = math.min(self.pending, MAX_GARBAGE_PER_DROP)
        for _ = 1, n do self:insertGarbageRow() end
        self.pending = self.pending - n
    end

    self.resting = false
    self.lockTimer = 0
    self.lockResets = 0
    self.dropCounter = 0
    self:spawn()
end

function Side:resetLock()
    self.lockResets = self.lockResets + 1
    self.lockTimer = 0
    if self.lockResets >= LOCK_MAX_RESETS then
        self:lock()
        return true
    end
    return false
end

function Side:moveH(dir)
    local p = self.piece
    if not p or self.dead then return false end
    if self.board:canPlace(p, p.x + dir, p.y, p.rot) then
        p:move(dir, 0)
        if not self.isCpu then Assets.play("move") end
        if self.resting then
            self:resetLock()
        else
            self.dropCounter = 0
        end
        return true
    end
    return false
end

function Side:rotate(clockwise)
    local p = self.piece
    if not p or self.dead then return false end
    local startx, oldrot = p.x, p.rot
    if clockwise then p:rotateCW() else p:rotateCCW() end
    local ok = false
    for _, kick in ipairs({ 0, 1, -1 }) do
        p.x = startx + kick
        if self.board:canPlace(p, p.x, p.y, p.rot) then ok = true; break end
    end
    if not ok then
        p.x, p.rot = startx, oldrot
        return false
    end
    if not self.isCpu then Assets.play("rotate") end
    if self.resting then self:resetLock() end
    return true
end

function Side:hardDrop()
    local p = self.piece
    if not p or self.dead then return end
    p.y = self.board:restingY(p)
    self:lock()
end

function Side:tick(gravityFrames)
    local p = self.piece
    if self.dead or not p then return end

    if self.board:restingY(p) == p.y then
        if not self.resting then
            self.resting = true
            self.lockTimer = 0
            self.lockResets = 0
        end
        self.lockTimer = self.lockTimer + 1
        if self.lockTimer >= LOCK_FRAMES then self:lock() end
    else
        self.resting = false
        self.lockTimer = 0
        local rate = self.soft and 1 or gravityFrames
        self.dropCounter = self.dropCounter + 1 / rate
        if self.dropCounter >= 1 then
            self.dropCounter = self.dropCounter - 1
            p:move(0, 1)
        end
    end
end

----------------------------------------------------------------------------
-- Computer opponent
----------------------------------------------------------------------------
-- The AI works on a plain occupancy grid (occ[row][col] = true/false) so it can
-- try placements without touching the real board.

local matrixCache = {}
local function matrixFor(kind, rot)
    local key = kind .. rot
    local m = matrixCache[key]
    if not m then
        m = Piece.new(kind, 0, 0, rot):matrix()
        matrixCache[key] = m
    end
    return m
end

local function occFromBoard(board)
    local occ = {}
    for r = 1, board.totalRows do
        local row = {}
        for c = 1, COLS do row[c] = board.grid[r][c] ~= nil end
        occ[r] = row
    end
    return occ
end

local function fits(occ, total, m, x, y)
    for dy = 0, 3 do
        for dx = 0, 3 do
            if m[dy + 1][dx + 1] == 1 then
                local gx, gy = x + dx, y + dy
                if gx < 1 or gx > COLS or gy < 1 or gy > total or occ[gy][gx] then
                    return false
                end
            end
        end
    end
    return true
end

local function dropY(occ, total, m, x, y)
    while fits(occ, total, m, x, y + 1) do y = y + 1 end
    return y
end

-- Place a piece and remove full rows. Returns the new grid and lines cleared.
-- Rows the piece does not touch are shared with the old grid, not copied.
local function placeAndClear(occ, total, m, x, y)
    local rows = {}
    for r = 1, total do rows[r] = occ[r] end
    local copied = {}
    for dy = 0, 3 do
        for dx = 0, 3 do
            if m[dy + 1][dx + 1] == 1 then
                local gy = y + dy
                if not copied[gy] then
                    local nr = {}
                    local old = rows[gy]
                    for c = 1, COLS do nr[c] = old[c] end
                    rows[gy] = nr
                    copied[gy] = true
                end
                rows[gy][x + dx] = true
            end
        end
    end

    local kept, lines = {}, 0
    for r = 1, total do
        local row = rows[r]
        local full = true
        for c = 1, COLS do
            if not row[c] then full = false; break end
        end
        if full then lines = lines + 1 else kept[#kept + 1] = row end
    end
    if lines == 0 then return rows, 0 end

    local out = {}
    local empty = total - #kept
    for r = 1, empty do
        local e = {}
        for c = 1, COLS do e[c] = false end
        out[r] = e
    end
    for i = 1, #kept do out[empty + i] = kept[i] end
    return out, lines
end

-- Score a grid: reward cleared lines, punish height, holes and bumpiness.
local function heuristic(occ, total, lines, lineWeight)
    local heights, agg, holes, maxH = {}, 0, 0, 0
    for c = 1, COLS do
        local top = nil
        for r = 1, total do
            if occ[r][c] then
                if not top then top = r end
            elseif top then
                holes = holes + 1
            end
        end
        local h = top and (total - top + 1) or 0
        heights[c] = h
        agg = agg + h
        if h > maxH then maxH = h end
    end
    local bump = 0
    for c = 1, COLS - 1 do bump = bump + math.abs(heights[c] - heights[c + 1]) end

    local score = -0.51 * agg + lineWeight * lines - 0.36 * holes - 0.18 * bump
    if maxH > 15 then score = score - (maxH - 15) * 2 end   -- panic when stacked high
    return score
end

-- Pick a landing spot (x, rot) for `kind`, following the difficulty settings.
local function choosePlacement(occ, total, kind, nextKind, diff)
    local cands = {}
    for rot = 1, 4 do
        local m = matrixFor(kind, rot)
        for x = -2, COLS do
            if fits(occ, total, m, x, SPAWN_Y) then
                local y = dropY(occ, total, m, x, SPAWN_Y)
                local nocc, lines = placeAndClear(occ, total, m, x, y)
                cands[#cands + 1] = {
                    x = x, rot = rot, occ = nocc,
                    score = heuristic(nocc, total, lines, diff.lineWeight),
                }
            end
        end
    end
    if #cands == 0 then return nil end

    -- Sometimes just blunder (mostly on Easy).
    if diff.mistake > 0 and math.random() < diff.mistake then
        return cands[math.random(#cands)]
    end

    local limit = #cands
    if diff.lookahead and nextKind then
        -- Re-score the best few candidates by also placing the NEXT piece.
        table.sort(cands, function(a, b) return a.score > b.score end)
        limit = math.min(6, #cands)
        for i = 1, limit do
            local cand = cands[i]
            local bestNext = nil
            for rot = 1, 4 do
                local m = matrixFor(nextKind, rot)
                for x = -2, COLS do
                    if fits(cand.occ, total, m, x, SPAWN_Y) then
                        local y = dropY(cand.occ, total, m, x, SPAWN_Y)
                        local o2, l2 = placeAndClear(cand.occ, total, m, x, y)
                        local s = heuristic(o2, total, l2, diff.lineWeight)
                        if not bestNext or s > bestNext then bestNext = s end
                    end
                end
            end
            cand.score = cand.score + (bestNext or -50)
        end
    end

    local best, bestScore
    for i = 1, limit do
        local s = cands[i].score + math.random() * diff.noise
        if not bestScore or s > bestScore then
            bestScore = s
            best = cands[i]
        end
    end
    return best
end

function Side:planCpu()
    local p = self.piece
    local occ = occFromBoard(self.board)
    local pick = choosePlacement(occ, self.board.totalRows, p.type, self.nextType, self.diff)
    self.plan = pick and { x = pick.x, rot = pick.rot } or { x = p.x, rot = p.rot }
end

function Side:cpuUpdate()
    local p = self.piece
    if self.dead or not p then return end
    local d = self.diff

    self.cpuTimer = self.cpuTimer + 1
    if self.cpuTimer < d.actionFrames then return end
    self.cpuTimer = 0

    if not self.plan then self:planCpu() end
    local plan = self.plan

    local rotDiff = (plan.rot - p.rot) % 4
    local acted
    if rotDiff ~= 0 then
        acted = self:rotate(rotDiff ~= 3)
    elseif p.x < plan.x then
        acted = self:moveH(1)
    elseif p.x > plan.x then
        acted = self:moveH(-1)
    else
        -- In position: slam it down, or (easier CPUs) just soft-drop it.
        if d.hardDrop then self:hardDrop() else self.soft = true end
        return
    end
    if acted == false then
        self.cpuStuck = self.cpuStuck + 1
        if self.cpuStuck > 6 then self:hardDrop() end
    end
end

----------------------------------------------------------------------------
-- Scene
----------------------------------------------------------------------------
local function register(SceneManager)
    local versus = {
        player = nil, cpu = nil,
        time = 0,
        _acc = 0,
        _over = false,
        _result = nil,        -- "win" | "lose" | "draw"
        _video = nil,
        -- player input (DAS)
        _dir = 0, _dasTimer = 0, _arrTimer = 0, _runningDAS = false,
        -- pause menu
        _menu = false,
        _menuIndex = 1,
    }

    local PAUSE_ITEMS = { "Resume", "Restart", "Quit" }

    local function fitVideoRect(sw, sh)
        local scale = math.min(1280 / sw, 720 / sh)
        local w, h = sw * scale, sh * scale
        return (1280 - w) / 2, (720 - h) / 2, w, h
    end

    local function gravityFrames(t)
        local f = GRAVITY_START_FRAMES - math.floor(t / GRAVITY_STEP_SECONDS) * GRAVITY_STEP_FRAMES
        return math.max(GRAVITY_MIN_FRAMES, f)
    end

    function versus:_start()
        self.player = Side.new(false)
        self.cpu = Side.new(true, DIFFICULTIES[self._difficulty] or DIFFICULTIES.medium)
        self.player.opponent = self.cpu
        self.cpu.opponent = self.player
        self.time = 0
        self._acc = 0
        self._over = false
        self._result = nil
        self._dir, self._dasTimer, self._arrTimer, self._runningDAS = 0, 0, 0, false
        self._menu = false
        self._menuIndex = 1

        self._video = Assets.pickRandomVideo()
        if self._video then self._video:play() end
        Assets.playRandomMusic()

        self.player:spawn()
        self.cpu:spawn()
    end

    function versus:enter(data)
        self._mode = (data and data.mode) or "comp"
        self._difficulty = (data and data.difficulty) or "medium"
        self:_start()
    end

    function versus:exit()
        if self._video then
            self._video:pause()
            self._video:rewind()
        end
        Assets.stopMusic()
    end

    function versus:_pauseAll()
        if self._video then self._video:pause() end
        Assets.pauseMusic()
    end

    function versus:_resumeAll()
        if self._video and not self._video:isPlaying() then self._video:play() end
        Assets.resumeMusic()
    end

    function versus:_updateDAS()
        local p = self.player
        if self._dir == 0 or not p.piece then return end
        if not self._runningDAS then
            self._dasTimer = self._dasTimer + 1
            if self._dasTimer >= DAS_FRAMES then
                self._dasTimer = 0
                self._runningDAS = true
                p:moveH(self._dir)
            end
        else
            self._arrTimer = self._arrTimer + 1
            if self._arrTimer >= ARR_FRAMES then
                self._arrTimer = 0
                p:moveH(self._dir)
            end
        end
    end

    function versus:_checkEnd()
        local pd, cd = self.player.dead, self.cpu.dead
        if not (pd or cd) then return end
        self._over = true
        if pd and cd then self._result = "draw"
        elseif pd then self._result = "lose"
        else self._result = "win" end
        Assets.play("gameover")
    end

    function versus:_tick()
        local g = gravityFrames(self.time)
        self.player:tick(g)
        if self.player.dead then return end
        self:_updateDAS()
        self.cpu:cpuUpdate()
        self.cpu:tick(g)
    end

    function versus:update(dt)
        if not self._menu and not self._over then
            Assets.updateMusic()
        end
        if self._video and not self._menu and not self._video:isPlaying() then
            self._video:rewind()
            self._video:play()
        end
        if self._menu or self._over then return end

        self.time = self.time + dt
        self._acc = self._acc + dt
        while self._acc >= STEP do
            self:_tick()
            self._acc = self._acc - STEP
            self:_checkEnd()
            if self._over then break end
        end
    end

    function versus:draw()
        if self._video then
            local sw, sh = self._video:getWidth(), self._video:getHeight()
            local dx, dy, dw, dh = fitVideoRect(sw, sh)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(self._video, dx, dy, 0, dw / sw, dh / sh)
            love.graphics.setColor(0, 0, 0, 0.4)
            love.graphics.rectangle("fill", 0, 0, 1280, 720)
        else
            love.graphics.setColor(0.04, 0.05, 0.14, 1)
            love.graphics.rectangle("fill", 0, 0, 1280, 720)
        end
        love.graphics.setColor(1, 1, 1, 1)

        local showGhost = not self._menu and not self._over
        drawWell(self.player, PLAYER_X, showGhost)
        drawWell(self.cpu, CPU_X, false)

        -- Middle column: labels, previews, stats.
        local f = Assets.fonts
        local lx, rx = 490, 690
        drawText("YOU", f.medium, lx, 40, 1, 0.85, 0.2)
        drawText("CPU", f.medium, rx, 40, 0.6, 0.8, 1)
        drawText(self.cpu.diff.name or "", f.small, rx, 68, 0.6, 0.8, 1)
        drawNext(self.player, lx)
        drawNext(self.cpu, rx)

        drawText("LINES", f.small, lx, 340, 0.85, 0.85, 0.85)
        drawText(tostring(self.player.lines), f.medium, lx, 362, 1, 1, 1)
        drawText("LINES", f.small, rx, 340, 0.85, 0.85, 0.85)
        drawText(tostring(self.cpu.lines), f.medium, rx, 362, 1, 1, 1)

        drawText("SENT", f.small, lx, 420, 0.85, 0.85, 0.85)
        drawText(tostring(self.player.sent), f.medium, lx, 442, 1, 1, 1)
        drawText("SENT", f.small, rx, 420, 0.85, 0.85, 0.85)
        drawText(tostring(self.cpu.sent), f.medium, rx, 442, 1, 1, 1)

        drawText("VS", f.large, 640, 520, 0.9, 0.9, 0.9, "center")

        local t = math.floor(self.time)
        drawText(string.format("%02d:%02d", math.floor(t / 60), t % 60),
            f.medium, 640, 640, 0.9, 0.9, 0.9, "center")

        -- Game-over overlay.
        if self._over then
            love.graphics.setColor(0, 0, 0, 0.65)
            love.graphics.rectangle("fill", 0, 0, 1280, 720)
            local msg = (self._result == "win") and "YOU WIN!"
                or (self._result == "lose") and "YOU LOSE" or "DRAW"
            drawText(msg, f.large, 640, 260, 1, 1, 1, "center")
            drawText("ENTER - REMATCH     ESC - TITLE", f.medium, 640, 380, 0.8, 0.8, 0.85, "center")
        elseif self._menu then
            love.graphics.setColor(0, 0, 0, 0.65)
            love.graphics.rectangle("fill", 0, 0, 1280, 720)
            drawText("PAUSED", f.large, 640, 180, 1, 1, 1, "center")
            for i = 1, #PAUSE_ITEMS do
                local sel = (i == self._menuIndex)
                local y = 270 + (i - 1) * 64
                if sel then
                    drawText("> " .. PAUSE_ITEMS[i], f.medium, 640, y, 1, 0.85, 0.2, "center")
                else
                    drawText("  " .. PAUSE_ITEMS[i], f.medium, 640, y, 0.8, 0.8, 0.85, "center")
                end
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
    end

    function versus:_menuKey(key)
        if key == "up" then
            self._menuIndex = math.max(1, self._menuIndex - 1)
        elseif key == "down" then
            self._menuIndex = math.min(#PAUSE_ITEMS, self._menuIndex + 1)
        elseif key == "escape" then
            self._menu = false
            self:_resumeAll()
        elseif isConfirm(key) then
            local item = PAUSE_ITEMS[self._menuIndex]
            if item == "Resume" then
                self._menu = false
                self:_resumeAll()
            elseif item == "Restart" then
                self:_start()
            elseif item == "Quit" then
                SceneManager.switch("title")
            end
        end
    end

    function versus:keypressed(key)
        if self._over then
            if isConfirm(key) then
                self:_start()
            elseif key == "escape" then
                SceneManager.switch("title")
            end
            return
        end
        if self._menu then
            self:_menuKey(key)
            return
        end
        if key == "escape" then
            self._menu = true
            self._menuIndex = 1
            self:_pauseAll()
            return
        end

        local p = self.player
        if p.dead or not p.piece then return end

        if key == "left" then
            self._dir, self._dasTimer, self._runningDAS, self._arrTimer = -1, 0, false, 0
            p:moveH(-1)
        elseif key == "right" then
            self._dir, self._dasTimer, self._runningDAS, self._arrTimer = 1, 0, false, 0
            p:moveH(1)
        elseif key == "down" then
            p.soft = true
        elseif key == "up" then
            p:hardDrop()
        elseif key == "z" then
            p:rotate(false)
        elseif key == "x" then
            p:rotate(true)
        end
    end

    function versus:keyreleased(key)
        if key == "left" and self._dir == -1 then self._dir = 0 end
        if key == "right" and self._dir == 1 then self._dir = 0 end
        if key == "down" and self.player then self.player.soft = false end
    end

    SceneManager.register("versus", versus)
end

return register
