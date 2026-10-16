-- conf.lua
-- Love2D 11.x configuration for the TGM-style Tetris game.
--
-- The window is fixed at 1280x720 but we render into a 1280x720 virtual
-- coordinate space and scale it to whatever the actual window is, so the
-- game always looks correct on any display resolution.

function love.conf(t)
    t.title      = "TETRIS VIBES"  -- window title
    t.version    = "11.4"                     -- target Love2D version
    t.window.width  = 1280                    -- initial window width
    t.window.height = 720                     -- initial window height
    t.window.resizable = false                -- fixed window size
    t.window.minwidth  = 1280
    t.window.minheight = 720
end
