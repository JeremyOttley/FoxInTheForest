-- game/prng.lua
-- Deterministic, portable combined Linear Congruential / Multiple Recursive PRNG
-- Compatible with Lua 5.1, LuaJIT, and Lua 5.3/5.4/5.5 using exact < 2^47 integer arithmetic.
-- Zero calls to math.random or os.time.

local floor = math.floor

local PRNG = {}
PRNG.__index = PRNG

local M1 = 2147483563
local A1 = 40014
local M2 = 2147483399
local A2 = 40692
local NORM = 1.0 / M1

local function sanitize_seed(seed)
    local n = tonumber(seed) or 1
    n = floor(math.abs(n))
    if n == 0 then
        n = 1
    end
    return n
end

function PRNG.new(seed)
    local s = sanitize_seed(seed)
    local s1 = (s % (M1 - 1)) + 1
    local s2 = (floor(s / 7) + 1234567) % (M2 - 1) + 1
    local self = setmetatable({
        seed = s,
        s1 = s1,
        s2 = s2,
        steps = 0,
    }, PRNG)
    -- Warm up internal state
    for _ = 1, 8 do
        self:next_u31()
    end
    self.steps = 0
    return self
end

function PRNG:next_u31()
    local s1 = (self.s1 * A1) % M1
    local s2 = (self.s2 * A2) % M2
    self.s1 = s1
    self.s2 = s2
    self.steps = self.steps + 1
    local z = s1 - s2
    if z < 1 then
        z = z + (M1 - 1)
    end
    return z
end

function PRNG:next_float()
    return self:next_u31() * NORM
end

function PRNG:next_int(min_val, max_val)
    if max_val == nil then
        max_val = min_val
        min_val = 1
    end
    if min_val >= max_val then
        return min_val
    end
    local span = (max_val - min_val) + 1
    local r = self:next_u31()
    return min_val + (r % span)
end

function PRNG:shuffle(list)
    local n = #list
    for i = n, 2, -1 do
        local j = self:next_int(1, i)
        if i ~= j then
            local tmp = list[i]
            list[i] = list[j]
            list[j] = tmp
        end
    end
    return list
end

function PRNG:clone()
    return setmetatable({
        seed = self.seed,
        s1 = self.s1,
        s2 = self.s2,
        steps = self.steps,
    }, PRNG)
end

function PRNG:serialize()
    return {
        seed = self.seed,
        s1 = self.s1,
        s2 = self.s2,
        steps = self.steps,
    }
end

function PRNG.deserialize(data)
    if type(data) ~= "table" then
        return PRNG.new(1)
    end
    return setmetatable({
        seed = tonumber(data.seed) or 1,
        s1 = tonumber(data.s1) or 1,
        s2 = tonumber(data.s2) or 1,
        steps = tonumber(data.steps) or 0,
    }, PRNG)
end

return PRNG
