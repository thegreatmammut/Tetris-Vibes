-- bag.lua
-- 7-bag randomizer.
--
-- The standard Tetris randomizer draws from a bag that is refilled with one of
-- each of the 7 pieces every time it empties, guaranteeing that every piece
-- appears once per 7-drop.
--
-- FIX: the queue is now always kept topped up with whole shuffled bags, so
-- peek() shows the pieces that will REALLY come next (the old preview rolled
-- throw-away bags that didn't match what next() later returned).

local Bag = {}
Bag.__index = Bag

-- The seven piece letters.
local TYPES = { "I", "O", "T", "S", "Z", "J", "L" }

local function newShuffledBag()
    local t = {}
    for i = 1, #TYPES do t[i] = TYPES[i] end
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- Make sure at least `n` pieces are queued.
function Bag:ensure(n)
    n = n or 14
    while #self.queue < n do
        local b = newShuffledBag()
        for i = 1, #b do
            self.queue[#self.queue + 1] = b[i]
        end
    end
end

-- Create a new bag.
function Bag.new()
    local self = setmetatable({}, Bag)
    self.queue = {}   -- pending pieces (front of the queue is queue[1])
    self:ensure()
    return self
end

--- Return and consume the next piece.
function Bag:next()
    self:ensure()
    local piece = table.remove(self.queue, 1)
    self:ensure()
    return piece
end

--- Peek at the next `n` pieces without consuming (default 5).
function Bag:peek(n)
    n = n or 5
    self:ensure(n)
    local out = {}
    for i = 1, n do
        out[i] = self.queue[i]
    end
    return out
end

return Bag
