-- src/compat.lua
-- Build-compatibility shims.
--
-- The game is written against love.graphics.drawText with THIS project's
-- signature:
--     drawText(text, x, y, r, sx, sy, align)
-- Stock Love has no such function, and a build that did ship one might use a
-- different argument order, so we always install our own, backed by
-- love.graphics.print. `align` ("left" | "center" | "right") treats x as the
-- left edge / centre / right edge of the text.

local function register()
    local function alignOffset(align, text)
        local font = love.graphics.getFont()
        if align == "center" or align == "centre" then
            return font:getWidth(text) / 2
        elseif align == "right" then
            return font:getWidth(text)
        end
        return 0
    end

    -- Accept both calling conventions:
    --   * this project's: drawText(text, x, y, r, sx, sy, align)
    --   * align-first:    drawText(text, x, y, align, r, sx, sy)
    function love.graphics.drawText(text, x, y, a, b, c, d)
        text = tostring(text)
        local r, sx, sy, align
        if type(a) == "string" then
            align = a
            r, sx, sy = b or 0, c or 1, d or 1
        else
            r, sx, sy = a or 0, b or 1, c or 1
            align = d
        end
        local ox = alignOffset(align, text)
        return love.graphics.print(text, x, y, r, sx, sy, ox, 0)
    end

    -- quad is only needed for sprite batching; provide a no-op placeholder so
    -- any code that references it does not crash.
    if not love.graphics.quad then
        function love.graphics.quad(...)
            local q = { ... }
            q.getViewport = function() return 0, 0, 0, 0 end
            q.getImage    = function() return nil end
            return q
        end
    end
end

return register
