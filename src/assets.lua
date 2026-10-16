-- assets.lua
-- Central, safe asset loader.
--
-- All graphics, sounds and music are loaded here. If a file is missing the
-- loader uses a fallback instead of crashing:
--   * block images -> generated procedurally (bevelled coloured squares)
--   * videos       -> nil (scenes draw a plain background instead)
--   * sounds       -> the play() helper silently no-ops
--
-- Background videos and music are DISCOVERED, not hard-coded:
--   * every  assets/video/*.ogv  is a candidate background video
--   * every  assets/music/*.ogg  is a candidate song
-- Videos and songs are loaded lazily (the first time they are picked) and
-- cached, so each file is only ever opened once.
--
-- Usage:
--   local Assets = require("src.assets")
--   Assets.init()
--   Assets.play("lock")             -- restart & play a sfx
--   Assets.pickRandomVideo()        -- random background video (or nil)
--   Assets.playRandomMusic()        -- start a random song
--   Assets.playMusic(index)         -- start song #index from the beginning
--   Assets.setVolume(0..100)        -- master volume (music + sfx)

local Assets = {}

local LOVE = love

-- Base directory for all asset files.
local ASSETS = "assets"

-- Height of a single playfield cell in pixels (used when generating block art).
local CELL = 32

-- File (in the Love save folder) where the volume setting is remembered.
local SETTINGS_FILE = "settings.txt"

-----------------------------------------------------------------------------
-- Small helpers
-----------------------------------------------------------------------------

--- Return true if a file exists in the app directory.
local function fileExists(path)
    local info = LOVE.filesystem.getInfo(path)
    return info ~= nil and info.type == "file"
end

--- Load an image, generating a coloured placeholder if it is missing.
--- `colour` is an {r,g,b,a} table (0..1).
local function loadImage(path, colour)
    if fileExists(path) then
        local ok, img = pcall(LOVE.graphics.newImage, path)
        if ok and img then
            img:setFilter("nearest", "nearest")
            return img
        end
    end
    -- Fallback: a solid filled square of the given colour.
    local data = LOVE.image.newImageData(CELL, CELL)
    local r, g, b, a = colour.r, colour.g, colour.b, colour.a
    for y = 0, CELL - 1 do
        for x = 0, CELL - 1 do
            data:setPixel(x, y, r, g, b, a)
        end
    end
    local tex = LOVE.graphics.newImage(data)
    tex:setFilter("nearest", "nearest")
    return tex
end

--- Play a loaded sfx source from the start (restart-and-play semantics).
local function playSource(src)
    if src and src.play then
        pcall(function()
            src:stop()
            src:play()
        end)
    end
end

-- Colour palette for each tetromino (TGM-ish bright colours).
local BLOCK_COLOURS = {
    I = { r = 0.10, g = 0.80, b = 0.85, a = 1.0 },
    O = { r = 0.95, g = 0.85, b = 0.20, a = 1.0 },
    T = { r = 0.75, g = 0.25, b = 0.90, a = 1.0 },
    S = { r = 0.25, g = 0.85, b = 0.30, a = 1.0 },
    Z = { r = 0.90, g = 0.25, b = 0.30, a = 1.0 },
    J = { r = 0.20, g = 0.35, b = 0.95, a = 1.0 },
    L = { r = 0.95, g = 0.55, b = 0.15, a = 1.0 },
}

--- Generate a block image procedurally with a bevelled look.
-- Builds the pixels directly into an ImageData (no Canvas), so it works on
-- every Love version.
local function genBlock(colour)
    local img = LOVE.image.newImageData(CELL, CELL)
    local r, g, b, a = colour.r, colour.g, colour.b, colour.a
    local w, h = CELL, CELL
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local cr, cg, cb
            if y < 3 or x < 3 then
                -- Highlight (top/left): mix toward white.
                cr, cg, cb = r + (1 - r) * 0.45, g + (1 - g) * 0.45, b + (1 - b) * 0.45
            elseif y >= h - 3 or x >= w - 3 then
                -- Shadow (bottom/right): darken.
                cr, cg, cb = r * 0.55, g * 0.55, b * 0.55
            else
                cr, cg, cb = r, g, b
            end
            img:setPixel(x, y, cr, cg, cb, a)
        end
    end
    local image = LOVE.graphics.newImage(img)
    image:setFilter("nearest", "nearest")
    return image
end

--- Load a video, returning nil (no crash) if the file is missing.
local function LOAD_VIDEO(path)
    if not fileExists(path) then return nil end
    local ok, v = pcall(LOVE.graphics.newVideo, path)
    if ok and v then return v end
    return nil
end

--- Load an audio source, returning nil (no crash) if the file is missing.
local function LOAD_AUDIO(path)
    if not fileExists(path) then return nil end
    local ok, s = pcall(LOVE.audio.newSource, path, "static")
    if ok and s then return s end
    return nil
end

--- Load a streaming audio source (for music), nil if missing.
local function LOAD_AUDIO_STREAM(path)
    if not fileExists(path) then return nil end
    local ok, s = pcall(LOVE.audio.newSource, path, "stream")
    if ok and s then return s end
    -- Fall back to a static source if streaming is unavailable.
    return LOAD_AUDIO(path)
end

--- List the files in `dir` whose name ends with `ext` (case-insensitive),
--- sorted alphabetically. Returns an empty list if the folder is missing.
local function listFiles(dir, ext)
    local out = {}
    local info = LOVE.filesystem.getInfo(dir)
    if not info or info.type ~= "directory" then return out end
    for _, f in ipairs(LOVE.filesystem.getDirectoryItems(dir)) do
        if f:lower():sub(-#ext) == ext and fileExists(dir .. "/" .. f) then
            out[#out + 1] = f
        end
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

-----------------------------------------------------------------------------
-- Volume (0..100, applies to music and sound effects)
-----------------------------------------------------------------------------

Assets.volume = 100

--- Set the master volume (0 = silent, 100 = full). Not saved until
--- Assets.saveSettings() is called.
function Assets.setVolume(v)
    v = math.floor((tonumber(v) or 100) + 0.5)
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    Assets.volume = v
    LOVE.audio.setVolume(v / 100)
end

--- Remember the volume for the next launch (stored in Love's save folder).
function Assets.saveSettings()
    pcall(function()
        LOVE.filesystem.write(SETTINGS_FILE, tostring(Assets.volume))
    end)
end

local function loadSettings()
    local ok, contents = pcall(LOVE.filesystem.read, SETTINGS_FILE)
    if ok and contents then
        local v = tonumber(contents)
        if v then Assets.setVolume(v) end
    end
end

-----------------------------------------------------------------------------
-- Background videos (random)
-----------------------------------------------------------------------------

Assets.videoFiles = {}      -- list of paths: assets/video/*.ogv
Assets.currentVideo = nil   -- the video the game scene is showing right now
local videoCache = {}       -- path -> Video, or false if it failed to load
local lastVideoPath = nil

--- Pick a random background video (avoids repeating the previous one when
--- there is more than one) and make it Assets.currentVideo. Returns the
--- Video, or nil if there are no usable files.
function Assets.pickRandomVideo()
    Assets.currentVideo = nil
    local n = #Assets.videoFiles
    if n == 0 then return nil end

    local start = math.random(n)
    if n > 1 and Assets.videoFiles[start] == lastVideoPath then
        start = start % n + 1
    end

    -- Try the chosen file first, then the others in order, so one broken
    -- file never leaves the game without a background.
    for k = 0, n - 1 do
        local path = Assets.videoFiles[(start - 1 + k) % n + 1]
        local v = videoCache[path]
        if v == nil then
            v = LOAD_VIDEO(path) or false
            videoCache[path] = v
        end
        if v then
            lastVideoPath = path
            Assets.currentVideo = v
            return v
        end
    end
    return nil
end

-----------------------------------------------------------------------------
-- Music (random, selectable)
-----------------------------------------------------------------------------

-- List of songs: { name = "display name", file = "x.ogg", path = "assets/music/x.ogg" }
Assets.songs = {}
Assets.musicIndex = nil        -- index into Assets.songs of the song playing now
Assets.musicSource = nil       -- the Source playing now
Assets._musicPaused = false    -- true while the ESC pause menu has the music paused
local musicLoop = false        -- true if the current song repeats forever
local lastMusicIndex = nil
local musicCache = {}          -- path -> Source, or false if it failed to load

local function getMusicSource(i)
    local song = Assets.songs[i]
    if not song then return nil end
    local src = musicCache[song.path]
    if src == nil then
        src = LOAD_AUDIO_STREAM(song.path) or false
        musicCache[song.path] = src
    end
    return src or nil
end

--- Stop whatever song is playing.
function Assets.stopMusic()
    if Assets.musicSource then
        pcall(function() Assets.musicSource:stop() end)
    end
    if Assets.musicIndex then lastMusicIndex = Assets.musicIndex end
    Assets.musicSource = nil
    Assets.musicIndex = nil
    musicLoop = false
end

--- Pause the current song WITHOUT resetting it. Unlike stopMusic(), this keeps
--- the current song and index, and records the play position so resumeMusic()
--- can restore it (no restart from the top).
function Assets.pauseMusic()
    if Assets.musicSource then
        pcall(function()
            Assets._musicPos = Assets.musicSource:getPosition()
            Assets.musicSource:pause()
        end)
    end
    Assets._musicPaused = true
end

--- Resume a song paused with pauseMusic(). Restores the recorded position and
--- starts playback, so the SAME track continues from where it was paused.
--- Uses setPosition()+play() rather than resume() because streaming sources
--- don't reliably resume in place; no-op if the track is already playing.
function Assets.resumeMusic()
    if Assets.musicSource then
        pcall(function()
            local src = Assets.musicSource
            if src:isPlaying() then return end
            if Assets._musicPos ~= nil then
                src:setPosition(Assets._musicPos)
            end
            src:play()
        end)
    end
    Assets._musicPaused = false
end

--- Start song #i from the very beginning. If `loop` is true it repeats
--- forever, otherwise Assets.updateMusic() moves on to a random song when it
--- ends. Returns true if it started.
function Assets.playMusic(i, loop)
    Assets.stopMusic()
    local src = getMusicSource(i)
    if not src then return false end
    local ok, started = pcall(function()
        src:setLooping(loop and true or false)
        src:stop()               -- stop() rewinds, so it always starts at 0:00
        return src:play()
    end)
    if not ok or started == false then return false end
    Assets.musicSource = src
    Assets.musicIndex = i
    lastMusicIndex = i
    musicLoop = loop and true or false
    return true
end

--- Start a random song (not the one that played last, if there is a choice).
function Assets.playRandomMusic()
    local n = #Assets.songs
    if n == 0 then return false end
    local i = math.random(n)
    if n > 1 and i == (Assets.musicIndex or lastMusicIndex) then
        i = i % n + 1
    end
    return Assets.playMusic(i, false)
end

--- Find a song by display name (case-insensitive); returns its index or nil.
function Assets.findSong(name)
    name = name:lower()
    for i, s in ipairs(Assets.songs) do
        if s.name:lower() == name then return i end
    end
    return nil
end

--- Call every frame: when a (non-looping) song finishes, start another one.
--- Skipped while paused so a paused track is never mistaken for a finished one.
function Assets.updateMusic()
    if Assets._musicPaused then return end
    if Assets.musicSource and not musicLoop and not Assets.musicSource:isPlaying() then
        Assets.playRandomMusic()
    end
end

-----------------------------------------------------------------------------
-- Loading
-----------------------------------------------------------------------------

--- Load every asset. Safe: never throws on a missing file.
function Assets.init()
    -- Block images (generated if PNGs are absent).
    Assets.blocks = {}
    for letter, colour in pairs(BLOCK_COLOURS) do
        local path = ASSETS .. "/blocks/" .. letter .. ".png"
        if fileExists(path) then
            Assets.blocks[letter] = loadImage(path, colour)
        else
            Assets.blocks[letter] = genBlock(colour)
        end
    end
    -- Ghost block (semi-transparent grey).
    Assets.blocks.ghost = loadImage(ASSETS .. "/blocks/ghost.png", { r = 0.7, g = 0.7, b = 0.7, a = 0.45 })
    -- Garbage block (the grey broken piece).
    Assets.blocks.garbage = loadImage(ASSETS .. "/blocks/garbage.png", { r = 0.4, g = 0.4, b = 0.4, a = 1.0 })

    -- Background pictures (nil if the file is missing).
    Assets.pictures = {}
    local menuPath = ASSETS .. "/pictures/mainmenu.png"
    if fileExists(menuPath) then
        local ok, img = pcall(LOVE.graphics.newImage, menuPath)
        if ok and img then
            img:setFilter("linear", "linear")
            Assets.pictures.mainmenu = img
        end
    end

    -- Discover background videos: every assets/video/*.ogv
    Assets.videoFiles = {}
    for _, f in ipairs(listFiles(ASSETS .. "/video", ".ogv")) do
        Assets.videoFiles[#Assets.videoFiles + 1] = ASSETS .. "/video/" .. f
    end

    -- Discover songs: every assets/music/*.ogg
    Assets.songs = {}
    for _, f in ipairs(listFiles(ASSETS .. "/music", ".ogg")) do
        Assets.songs[#Assets.songs + 1] = {
            name = f:sub(1, -5),                -- file name without ".ogg"
            file = f,
            path = ASSETS .. "/music/" .. f,
        }
    end

    -- Sound effects.
    Assets.sfx = {}
    local SFX = {
        move     = ASSETS .. "/sfx/move.ogg",
        rotate   = ASSETS .. "/sfx/rotate.ogg",
        lock     = ASSETS .. "/sfx/lock.ogg",
        clear1   = ASSETS .. "/sfx/clear1.ogg",
        clear2   = ASSETS .. "/sfx/clear2.ogg",
        clear3   = ASSETS .. "/sfx/clear3.ogg",
        clear4   = ASSETS .. "/sfx/clear4.ogg",
        levelup  = ASSETS .. "/sfx/levelup.ogg",
        gameover = ASSETS .. "/sfx/gameover.ogg",
        coin     = ASSETS .. "/sfx/coin.ogg",
    }
    for name, path in pairs(SFX) do
        Assets.sfx[name] = LOAD_AUDIO(path)
    end

    -- Fonts.
    Assets.fonts = {}
    local fontPath = ASSETS .. "/fonts/pixel.ttf"
    local function makeFont(size)
        if fileExists(fontPath) then
            local ok, f = pcall(LOVE.graphics.newFont, fontPath, size)
            if ok and f then return f end
        end
        return LOVE.graphics.newFont(size)
    end
    Assets.fonts.small  = makeFont(14)
    Assets.fonts.medium = makeFont(24)
    Assets.fonts.large  = makeFont(48)

    -- Remembered volume from the last session (defaults to 100).
    Assets.setVolume(100)
    loadSettings()

    return Assets
end

--- Play a sfx by name (restart-and-play).
function Assets.play(name)
    playSource(Assets.sfx and Assets.sfx[name])
end

return Assets
