-- scenes/game.lua
-- Core gameplay scene.
--
-- Handles the 7-bag randomizer, the board, scoring, piece movement (with DAS),
-- gravity, lock delay / wall kicks, ghost piece, ARE (spawn delay), hard drop
-- and game-over. Logic runs on a fixed 60 Hz timestep while the on-screen timer
-- uses real elapsed time.
--
-- Controls:
--   Left / Right : move (DAS)
--   Down         : soft drop
--   Up           : hard drop
--   Z            : rotate counter-clockwise
--   X            : rotate clockwise
--   Escape       : pause
--   Enter        : start (handled before entering the scene)

local Assets = require("src.assets")
local HighScores = require("src.highscores")
local Board  = require("src.board")
local Piece  = require("src.piece")
local Bag    = require("src.bag")
local Scoring = require("src.scoring")
local UI     = require("src.ui")

-- Fixed logic step (seconds).
local STEP = 1 / 60
-- Spawn ARE (frames).
local ARE_FRAMES = 12
-- Lock delay (frames) and max resets.
local LOCK_FRAMES = 30
local LOCK_MAX_RESETS = 15
-- DAS (frames) and ARR (frames).
local DAS_FRAMES = 16
local ARR_FRAMES = 4
-- Gravity range, in frames per row (60 frames = 1 second). Tune these numbers
-- to change how fast the game starts and how fast it tops out.
local GRAVITY_START_FRAMES  = 60   -- level 0:   one row per second
local GRAVITY_END_FRAMES    = 1    -- max speed: one row per frame (1G)
local GRAVITY_MAX_LEVEL     = 500  -- level at which max speed (GRAVITY_END_FRAMES) is reached; held from here to level 999
-- Spawn grid position for new pieces.
local SPAWN_X = 4
local SPAWN_Y = Board.SPAWN_ROW

local function register(SceneManager)
    local game = {
        -- runtime state
        board     = nil,
        bag       = nil,
        scoring   = nil,
        piece     = nil,
        _nextType = nil,
        time      = 0,
        _over     = false,

        -- fixed-timestep accumulator
        _acc = 0,
        -- spawn ARE counter
        _are = 0,
        -- gravity accumulator
        _dropCounter = 0,
        -- lock delay
        _resting   = false,
        _lockTimer = 0,
        _lockResets = 0,
        -- soft drop
        softDropping = false,
        _soft = 0,          -- soft-drop frame count for the current piece
        _manualLock = false, -- true when the piece was locked by a hard drop
        -- DAS
        _dir       = 0,
        _dasTimer  = 0,
        _arrTimer  = 0,
        _runningDAS = false,
        -- effects
        _flash = 0,

        _video = nil,

        -- Pause-menu state machine. _menu is nil while playing, "main" for the
        -- central pause menu, "options" for the volume/song sub-menu.
        _menu       = nil,
        _menuIndex  = 1,     -- selected item in the main pause menu
        -- Options sub-menu:
        _optFocus   = 1,     -- 1 = volume slider, 2 = song dropdown
        _dropOpen   = false, -- song dropdown expanded
        _dropFocus  = 1,     -- selected row inside the open dropdown
        _forcedSong = nil,   -- 1-based index into Assets.songs if user picked one
        _sliderDrag = false, -- true while the volume slider is being dragged
    }

    -- Frames-per-row for gravity at a given level (may be fractional).
    -- Speeds up smoothly and evenly (same percentage faster per level) from
    -- GRAVITY_START_FRAMES at level 0 to GRAVITY_END_FRAMES at GRAVITY_MAX_LEVEL,
    -- then holds max speed from GRAVITY_MAX_LEVEL up to level 999.
    function game:gravityFrames(level)
        level = level or self.scoring.level
        local t = math.min(level, GRAVITY_MAX_LEVEL) / GRAVITY_MAX_LEVEL   -- 0..1, clamps at max level
        return GRAVITY_START_FRAMES * (GRAVITY_END_FRAMES / GRAVITY_START_FRAMES) ^ t
    end

    ----------------------------------------------------------------------------
    -- Background video
    ----------------------------------------------------------------------------

    -- Fit a source rect (sw x sh) inside the 1280x720 screen while preserving
    -- its aspect ratio, centred. Returns the destination x, y, w, h. Areas
    -- outside the video (letter/pillar bars) show whatever is drawn behind it.
    local function fitVideoRect(sw, sh)
        local scale = math.min(1280 / sw, 720 / sh)
        local w, h = sw * scale, sh * scale
        return (1280 - w) / 2, (720 - h) / 2, w, h
    end

    ----------------------------------------------------------------------------
    -- Pause menu
    ----------------------------------------------------------------------------

    -- Central pause-menu items.
    local MAIN_ITEMS = { "Options", "Restart", "Quit" }

    -- Layout, in the 1280x720 virtual space.
    local MENU_TITLE_Y = 180
    local MENU_ITEM_Y0 = 270
    local MENU_ITEM_GAP = 64
    local SLIDER_Y = 250
    local SLIDER_X0 = 440
    local SLIDER_W = 400
    local SONG_ROW_Y = 350
    local DROP_ROW_H = 44
    local DROP_LIST_Y0 = SONG_ROW_Y + 64

    -- FIX: Love2D names the Enter key "return" (numpad: "kpenter"), never
    -- "enter". The old menu code compared against "enter", so confirming a
    -- menu item with Enter never fired.
    local function isConfirm(key)
        return key == "return" or key == "kpenter"
    end

    -- Start a fresh game (used by enter() and the Restart menu option).
    function game:_startNewGame()
        self.board   = Board.new()
        self.bag     = Bag.new()
        self.scoring = Scoring.new()
        self._nextType = nil
        self.time = 0
        self._over = false
        self.piece = nil
        self._acc = 0
        self._are = ARE_FRAMES
        self._flash = 0
        self.softDropping = false
        self._dir = 0
        self._dasTimer = 0
        self._arrTimer = 0
        self._runningDAS = false
        self._resting = false
        self._lockTimer = 0
        self._lockResets = 0
        self._dropCounter = 0

        -- Fresh background video + random music.
        self._video = Assets.pickRandomVideo()
        if self._video then self._video:play() end
        self._forcedSong = nil
        Assets.playRandomMusic()

        self._menu = nil
        self:spawnPiece()
    end

    -- Convert a Love mouse coordinate into the game's 1280x720 virtual space.
    -- The app is not HiDPI-aware, so Windows scales the mouse position by the
    -- system DPI factor; dividing by love.window.getDPIScale() recovers the
    -- virtual coordinates that every layout constant below is written against.
    -- No-op on a normal (1x) display.
    local function toVirtual(x, y)
        local ok, s = pcall(function() return love.window.getDPIScale() end)
        if not ok or not s or s <= 0 then return x, y end
        return x / s, y / s
    end

    -- Freeze the game: pause the video and pause (not reset) the music.
    function game:_pauseAll()
        if self._video then self._video:pause() end
        Assets.pauseMusic()
    end

    -- Unfreeze: resume the video and resume the music from where it paused.
    function game:_resumeAll()
        if self._video and not self._video:isPlaying() then self._video:play() end
        Assets.resumeMusic()
    end

    function game:_setVolume(v)
        v = math.max(0, math.min(100, math.floor(v + 0.5)))
        Assets.setVolume(v)
    end

    function game:_setVolumeFromX(x)
        local t = (x - SLIDER_X0) / SLIDER_W
        self:_setVolume(math.max(0, math.min(1, t)) * 100)
    end

    function game:_currentSongIndex()
        return self._forcedSong or Assets.musicIndex or 1
    end

    function game:_selectMain(i)
        local item = MAIN_ITEMS[i]
        if item == "Options" then
            self._menu = "options"
            self._optFocus = 1
            self._dropOpen = false
        elseif item == "Restart" then
            self:_startNewGame()
        elseif item == "Quit" then
            SceneManager.switch("title")
        end
    end

    function game:_selectSong(i)
        i = math.max(1, math.min(#Assets.songs, i))
        self._forcedSong = i
        Assets.playMusic(i, true)   -- start from the top, looping
        self._dropOpen = false
    end

    function game:_menuKey(key)
        if self._menu == "main" then
            if key == "up" then
                self._menuIndex = math.max(1, self._menuIndex - 1)
            elseif key == "down" then
                self._menuIndex = math.min(#MAIN_ITEMS, self._menuIndex + 1)
            elseif key == "escape" then
                self._menu = nil
                self:_resumeAll()
            elseif isConfirm(key) then
                self:_selectMain(self._menuIndex)
            end
        elseif self._menu == "options" then
            if self._dropOpen then
                if key == "up" then
                    self._dropFocus = math.max(1, self._dropFocus - 1)
                elseif key == "down" then
                    self._dropFocus = math.min(#Assets.songs, self._dropFocus + 1)
                elseif isConfirm(key) then
                    self:_selectSong(self._dropFocus)
                elseif key == "escape" then
                    self._dropOpen = false
                end
            else
                if key == "up" then
                    self._optFocus = 1
                elseif key == "down" then
                    self._optFocus = 2
                elseif key == "escape" then
                    self._menu = "main"
                elseif key == "left" then
                    self:_setVolume(Assets.volume - 5)
                elseif key == "right" then
                    self:_setVolume(Assets.volume + 5)
                elseif isConfirm(key) then
                    self._dropOpen = true
                    self._dropFocus = self:_currentSongIndex()
                end
            end
        end
    end

    function game:_dropdownRowAt(x, y)
        if not self._dropOpen then return nil end
        for i = 1, #Assets.songs do
            local ry = DROP_LIST_Y0 + (i - 1) * DROP_ROW_H
            if x >= SLIDER_X0 and x <= SLIDER_X0 + SLIDER_W
            and y >= ry and y <= ry + DROP_ROW_H then
                return i
            end
        end
        return nil
    end

    -- Central pause menu overlay.
    function game:_drawMainMenu()
        love.graphics.setFont(Assets.fonts.large)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.drawText("PAUSED", 640, MENU_TITLE_Y, 0, 1, 1, "center")
        love.graphics.setFont(Assets.fonts.medium)
        for i = 1, #MAIN_ITEMS do
            local y = MENU_ITEM_Y0 + (i - 1) * MENU_ITEM_GAP
            local sel = (i == self._menuIndex)
            love.graphics.setColor(sel and { 1, 0.85, 0.2, 1 } or { 0.8, 0.8, 0.85, 1 })
            love.graphics.drawText((sel and "> " or "  ") .. MAIN_ITEMS[i],
                640, y, 0, 1, 1, "center")
        end
        love.graphics.setFont(Assets.fonts.small)
        love.graphics.setColor(0.6, 0.6, 0.65, 1)
        love.graphics.drawText("Arrows to move - Enter to pick - Esc to resume",
            640, 520, 0, 1, 1, "center")
    end

    -- Options sub-menu overlay (volume slider + song dropdown).
    function game:_drawOptions()
        love.graphics.setFont(Assets.fonts.large)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.drawText("OPTIONS", 640, 140, 0, 1, 1, "center")

        -- Volume label + slider.
        love.graphics.setFont(Assets.fonts.medium)
        love.graphics.setColor(0.8, 0.8, 0.85, 1)
        love.graphics.drawText("MUSIC VOLUME", SLIDER_X0, SLIDER_Y - 30, 0, 1, 1, "left")

        local hx = SLIDER_X0 + (Assets.volume / 100) * SLIDER_W
        love.graphics.setColor(0.3, 0.3, 0.35, 1)
        love.graphics.rectangle("fill", SLIDER_X0, SLIDER_Y, SLIDER_W, 8)
        love.graphics.setColor(0.7, 0.75, 0.85, 1)
        love.graphics.rectangle("fill", SLIDER_X0, SLIDER_Y, hx - SLIDER_X0, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", hx - 10, SLIDER_Y - 12, 20, 32)

        love.graphics.setFont(Assets.fonts.small)
        love.graphics.setColor(0.7, 0.7, 0.75, 1)
        love.graphics.drawText(Assets.volume .. " / 100", SLIDER_X0 + SLIDER_W + 20, SLIDER_Y - 8, 0, 1, 1, "left")

        -- Song row.
        local songFocus = (self._optFocus == 2) and (not self._dropOpen)
        love.graphics.setFont(Assets.fonts.medium)
        love.graphics.setColor(songFocus and { 1, 0.85, 0.2, 1 } or { 0.8, 0.8, 0.85, 1 })
        local curName = Assets.songs[self:_currentSongIndex()]
        if curName then curName = curName.name else curName = "-" end
        love.graphics.drawText((songFocus and "> " or "  ") .. curName,
            SLIDER_X0, SONG_ROW_Y, 0, 1, 1, "left")

        -- Expanded dropdown list.
        if self._dropOpen then
            for i = 1, #Assets.songs do
                local ry = DROP_LIST_Y0 + (i - 1) * DROP_ROW_H
                local sel = (i == self._dropFocus)
                love.graphics.setColor(sel and { 1, 0.85, 0.2, 1 } or { 0.18, 0.18, 0.24, 1 })
                love.graphics.rectangle("fill", SLIDER_X0, ry, SLIDER_W, DROP_ROW_H)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setFont(Assets.fonts.medium)
                love.graphics.drawText((sel and "> " or "  ") .. Assets.songs[i].name,
                    SLIDER_X0 + 20, ry + 12, 0, 1, 1, "left")
            end
        end

        love.graphics.setFont(Assets.fonts.small)
        love.graphics.setColor(0.6, 0.6, 0.65, 1)
        if self._dropOpen then
            love.graphics.drawText("Arrows to pick - Enter to start - Esc to close",
                640, 560, 0, 1, 1, "center")
        else
            love.graphics.drawText("Left/Right: volume - Enter: choose song - Esc to back",
                640, 560, 0, 1, 1, "center")
        end
    end

    function game:mousepressed(x, y, button)
        -- FIX: Love2D reports the left mouse button as 1 (number), not "l".
        if (button ~= 1 and button ~= "l") or not self._menu then return end
        x, y = toVirtual(x, y)
        if self._menu == "main" then
            for i = 1, #MAIN_ITEMS do
                local my = MENU_ITEM_Y0 + (i - 1) * MENU_ITEM_GAP
                if y >= my - 24 and y <= my + 24 then
                    self._menuIndex = i
                    self:_selectMain(i)
                    return
                end
            end
        elseif self._menu == "options" then
            if not self._dropOpen then
                if x >= SLIDER_X0 and x <= SLIDER_X0 + SLIDER_W
                and math.abs(y - SLIDER_Y) < 20 then
                    self._sliderDrag = true
                    self:_setVolumeFromX(x)
                elseif math.abs(y - SONG_ROW_Y) < 24 then
                    self._dropOpen = true
                    self._dropFocus = self:_dropdownRowAt(x, y) or self:_currentSongIndex()
                end
            else
                local idx = self:_dropdownRowAt(x, y)
                if idx then self:_selectSong(idx) end
            end
        end
    end

    function game:mousemoved(x, y, dx, dy)
        if self._menu == "options" and self._sliderDrag then
            x = toVirtual(x, y)
            self:_setVolumeFromX(x)
        end
    end

    function game:mousereleased(x, y, button)
        if button == 1 or button == "l" then self._sliderDrag = false end
    end

    function game:wheelmoved(dx, dy)
        if self._menu ~= "options" then return end
        if self._dropOpen then
            self._dropFocus = math.max(1, math.min(#Assets.songs,
                self._dropFocus + (dy > 0 and 1 or -1)))
        elseif self._optFocus == 1 then
            self:_setVolume(Assets.volume + (dy > 0 and 5 or -5))
        end
    end

    -- Spawn the next piece from the bag.
    function game:spawnPiece()
        local kind = self._nextType or self.bag:next()
        self._nextType = self.bag:next()

        local p = Piece.new(kind, SPAWN_X, SPAWN_Y, 1)
        self.piece = p
        self._resting = false
        self._lockTimer = 0
        self._lockResets = 0
        self._dropCounter = 0
        self._are = ARE_FRAMES
        self._soft = 0          -- fresh soft-drop counter for this piece
        self._manualLock = false

        -- Game over if the spawned piece cannot be placed.
        if not self.board:canPlace(p, p.x, p.y, p.rot) then
            self:triggerGameOver()
        end
    end

    -- Reset the lock delay after a successful move/rotate while resting.
    -- Counts toward the "max 15 resets" cap; once reached the piece locks
    -- immediately. Returns true if the piece locked (caller may return).
    function game:resetLockDelay()
        self._lockResets = self._lockResets + 1
        self._lockTimer = 0
        if self._lockResets >= LOCK_MAX_RESETS then
            self:lockPiece()
            return true
        end
        return false
    end

    -- Move the piece horizontally (blocked moves simply do nothing).
    -- FIX: the old code "bounced" a blocked piece by moving it the OPPOSITE
    -- way, which shoved the piece away from the wall on every blocked press.
    function game:moveHorizontal(dir)
        if not self.piece then return end
        local p = self.piece
        if self.board:canPlace(p, p.x + dir, p.y, p.rot) then
            p:move(dir, 0)
            Assets.play("move")
            if self._resting then
                if self:resetLockDelay() then return end
            else
                self._dropCounter = 0        -- reset gravity
            end
        end
    end

    -- Rotate with a simple wall kick (tries in place, then +1, then -1).
    -- FIX: the old kick list skipped the in-place try, so every rotation
    -- nudged the piece sideways by one cell.
    function game:rotate(clockwise)
        if not self.piece then return end
        local p = self.piece
        local startx = p.x
        local oldrot = p.rot
        if clockwise then p:rotateCW() else p:rotateCCW() end

        local kicked = false
        for _, kick in ipairs({ 0, 1, -1 }) do
            p.x = startx + kick
            if self.board:canPlace(p, p.x, p.y, p.rot) then
                kicked = true
                break
            end
        end
        if not kicked then
            p.x = startx
            p.rot = oldrot
            return
        end
        Assets.play("rotate")
        if self._resting then
            self:resetLockDelay()
        end
    end

    -- Instant hard drop -> lock.
    function game:hardDrop()
        if not self.piece then return end
        self._manualLock = true -- a hard drop is a manual lock (+1 soft)
        self.piece.y = self.board:restingY(self.piece)
        self:lockPiece()
    end

    -- Lock the current piece, clear lines, spawn the next one.
    function game:lockPiece()
        Assets.play("lock")
        self.board:lock(self.piece)

        -- Level at the moment of the clear (used by the score formula).
        local levelBefore = self.scoring.level
        local prevLevel = levelBefore

        -- A piece that lands raises the level by one (blocked across 100-level
        -- boundaries; only a line clear may cross those).
        self.scoring:levelUpFromPiece()

        local cleared = self.board:clearLines()
        if cleared > 0 then
            local map = { [1] = "clear1", [2] = "clear2", [3] = "clear3", [4] = "clear4" }
            Assets.play(map[cleared])
        end

        -- Soft-drop frames for this piece; a manual (hard) lock adds 1.
        local soft = self._soft
        if self._manualLock then soft = soft + 1 end

        -- TGM+ scoring: combo, points, line-based level, grade, Bravo on PC.
        self.scoring:scoreClear(levelBefore, cleared, soft, self.board:isEmpty())

        -- Record the elapsed time at which GM-milestone levels (300/500/999) are
        -- first reached, used for the GM grade time checkpoints.
        self.scoring:checkLevelCheckpoints(self.time)

        if self.scoring.level > prevLevel then
            Assets.play("levelup")
            self._flash = 1
        end

        self.piece = nil
        self._manualLock = false
        self._resting = false
        self._lockTimer = 0
        self._lockResets = 0
        self._dropCounter = 0
        self:spawnPiece()
    end

    -- Run one fixed 60 Hz logic step.
    function game:tick()
        if self._over or not self.piece then return end

        -- Count soft-drop frames while the piece is active and Down is held.
        if self.softDropping then
            self._soft = self._soft + 1
        end

        -- Spawn ARE countdown.
        if self._are > 0 then self._are = self._are - 1 end

        local restingY = self.board:restingY(self.piece)
        local nowResting = (restingY == self.piece.y)

        if nowResting then
            if not self._resting then
                self._resting = true
                self._lockTimer = 0
                self._lockResets = 0
            end
            -- Lock delay only begins after spawn ARE finishes.
            if self._are <= 0 then
                self._lockTimer = self._lockTimer + 1
                if self._lockTimer >= LOCK_FRAMES or self._lockResets >= LOCK_MAX_RESETS then
                    self:lockPiece()
                    return
                end
            end
        else
            self._resting = false
            self._lockTimer = 0
            -- Gravity.
            -- Fractional gravity accumulator: each frame adds 1/framesPerRow
            -- rows, so speed increases smoothly instead of in whole frames.
            local rate = self.softDropping and 1 or self:gravityFrames()
            self._dropCounter = self._dropCounter + 1 / rate
            if self._dropCounter >= 1 then
                self._dropCounter = self._dropCounter - 1
                self.piece:move(0, 1)
            end
        end

        self:updateDAS()
    end

    -- Delayed auto-shift for held movement keys.
    function game:updateDAS()
        if self._dir == 0 or not self.piece then return end
        if not self._runningDAS then
            self._dasTimer = self._dasTimer + 1
            if self._dasTimer >= DAS_FRAMES then
                self._dasTimer = 0
                self._runningDAS = true
                self:moveHorizontal(self._dir)
            end
        else
            self._arrTimer = self._arrTimer + 1
            if self._arrTimer >= ARR_FRAMES then
                self._arrTimer = 0
                self:moveHorizontal(self._dir)
            end
        end
    end

    function game:triggerGameOver()
        if self._over then return end
        self._over = true
        -- Record this run in the persistent top-10 high score table.
        HighScores:add({
            score  = self.scoring.points,
            grade  = self.scoring.grade,
            level  = self.scoring.level,
            time   = self.time,
        })
        Assets.play("gameover")
        Assets.stopMusic()
        SceneManager.switch("gameover", {
            points = self.scoring.points,
            grade  = self.scoring.grade,
            time   = self.time,
            level  = self.scoring.level,
        })
    end

    ----------------------------------------------------------------------------
    -- Scene lifecycle
    ----------------------------------------------------------------------------

    function game:enter(data)
        -- Initialise a fresh game: board/bag/scoring, a random background
        -- video (sets Assets.currentVideo, reused by the game-over scene),
        -- and random background music. _menu stays nil (playing).
        --
        -- _startNewGame reuses the exact same setup, so the Restart menu
        -- option can reset the game without duplicating this logic.
        self:_startNewGame()
    end

    function game:exit()
        -- On game over the game-over scene keeps using this SAME video
        -- object. Pausing/rewinding it here and replaying it a moment later in
        -- the same frame is risky for the native video decoder, so on game
        -- over we leave it running and let the game-over scene take over.
        if self._video and not self._over then
            self._video:pause()
            self._video:rewind()
        end
        Assets.stopMusic()
    end

    function game:update(dt)
        -- Level-up flash decay (real time).
        if self._flash > 0 then
            self._flash = math.max(0, self._flash - dt * 3)
        end

        -- Advance background music when a (non-looping) song finishes. Skip
        -- while paused: a paused source reports isPlaying()==false, so calling
        -- this here would mistake the paused track for a finished one and
        -- restart it from the top on every frame the menu is open.
        if not self._menu and not self._over then
            Assets.updateMusic()
        end

        -- Keep the background video looping, but only while actually playing.
        if self._video and self._menu == nil and not self._video:isPlaying() then
            self._video:rewind()
            self._video:play()
        end

        -- Freeze all game logic while a pause menu is open.
        if self._menu or self._over then return end

        -- Advance the real-time timer.
        self.time = self.time + dt

        -- Fixed timestep.
        self._acc = self._acc + dt
        while self._acc >= STEP do
            self:tick()
            self._acc = self._acc - STEP
            if self._over then break end
        end
    end

    function game:draw()
        -- Background: video with a dark overlay, or a plain dark colour.
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

        -- NEXT window: the already-chosen next piece first, then the bag peek.
        local nextPieces = {}
        if self._nextType then nextPieces[1] = self._nextType end
        local more = self.bag:peek(4)
        for i = 1, #more do nextPieces[#nextPieces + 1] = more[i] end

        local hud = {
            board      = self.board,
            scoring    = self.scoring,
            nextPieces = nextPieces,
            time       = self.time,
            paused     = self._menu ~= nil,
            piece      = self.piece,
            pieceGhost = (self._menu == nil) and (not self._over),
            ghostY     = self.piece and self.board:ghostY(self.piece),
        }
        UI.draw(hud)

        -- Level-up flash.
        if self._flash > 0 then
            love.graphics.setColor(1, 1, 1, self._flash * 0.3)
            love.graphics.rectangle("fill", 0, 0, 1280, 720)
            love.graphics.setColor(1, 1, 1, 1)
        end

        -- Pause overlay + menu. The frozen game stays dimmed behind it.
        if self._menu then
            love.graphics.setColor(0, 0, 0, 0.65)
            love.graphics.rectangle("fill", 0, 0, 1280, 720)
            if self._menu == "main" then
                self:_drawMainMenu()
            elseif self._menu == "options" then
                self:_drawOptions()
            end
        end
    end

    function game:keypressed(key, scancode, isrepeat)
        -- The pause menu owns all input while it is open.
        if self._menu then
            self:_menuKey(key)
            return
        end
        if self._over then return end
        if key == "escape" then
            -- Pause the game, the video and the music, then open the menu.
            self._menu = "main"
            self._menuIndex = 1
            self:_pauseAll()
            return
        end
        if not self.piece then return end

        if key == "left" then
            self._dir = -1
            self._dasTimer = 0
            self._runningDAS = false
            self._arrTimer = 0
            self:moveHorizontal(-1)
        elseif key == "right" then
            self._dir = 1
            self._dasTimer = 0
            self._runningDAS = false
            self._arrTimer = 0
            self:moveHorizontal(1)
        elseif key == "down" then
            self.softDropping = true
        elseif key == "up" then
            self:hardDrop()
        elseif key == "z" then
            self:rotate(false)
        elseif key == "x" then
            self:rotate(true)
        end
    end

    function game:keyreleased(key, scancode, isrepeat)
        if key == "left" and self._dir == -1 then self._dir = 0 end
        if key == "right" and self._dir == 1  then self._dir = 0 end
        if key == "down" then self.softDropping = false end
    end

    SceneManager.register("game", game)
end

return register
