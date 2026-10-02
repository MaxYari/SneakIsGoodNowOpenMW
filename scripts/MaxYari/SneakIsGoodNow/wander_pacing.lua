local mp = "scripts/MaxYari/SneakIsGoodNow/"

local async = require("openmw.async")
local core = require("openmw.core")
local storage = require("openmw.storage")
local types = require("openmw.types")
local omwself = require("openmw.self")
local I = require("openmw.interfaces")

local DEFS = require(mp .. 'utils/sneak_defs')

-- Vanilla AiWander has no pause between walks: an NPC stops only for as long as a random idle animation
-- plays, and about half the time it plays none and walks straight on. In a small area that is fast pacing
-- back and forth. Here an NPC that has walked for too long stops: its wander package is swapped for a
-- stationary one (distance 0, its own idles) for a while, then the original is started again.
--
-- A wander package takes its home from where the actor stands on its first update, and Lua can't give it
-- one. So on resume a Travel package is put on top of the new wander: the NPC walks home first, and the
-- wander takes its home there.

local TICK = 1.0
local MAX_RADIUS = 512      -- wander radius up to this: a room or a cave chamber, not a town
local HOME_TOLERANCE = 64   -- closer than this to home, resume wandering where the NPC stands

local settings = storage.globalSection(DEFS.NPC_SETTINGS_KEY)

local isNPC = types.NPC.objectIsInstance(omwself)

local walkTime = 0
local stillTicks = 0
local pauseUntil = nil  -- simulation time the pause ends, nil when not paused
local wander = nil      -- the original wander package's settings, kept while paused
local home = nil
local started = false

local function isSmallIndoorWander(pkg)
    if not pkg or pkg.type ~= "Wander" or not pkg.distance or pkg.distance <= 0 or pkg.distance > MAX_RADIUS then
        return false
    end
    local cell = omwself.cell
    return cell and not cell.isExterior and not cell:hasTag("QuasiExterior")
end

-- Only NPCs whose whole AI is this one wander, so a scripted NPC's package chain is never touched
local function isOnlyPackage()
    local count = 0
    I.AI.forEachPackage(function() count = count + 1 end)
    return count == 1
end

local function captureHome(pkg)
    -- Where the NPC was placed, unless it has been moved since: then where it is now
    local start = omwself.startingPosition
    if (omwself.position - start):length() <= pkg.distance + HOME_TOLERANCE then
        home = start
    else
        home = omwself.position
    end
end

local function pause(pkg)
    wander = { distance = pkg.distance, duration = pkg.duration, idle = pkg.idle, isRepeat = pkg.isRepeat }

    -- Replacing the package doesn't clear the walk input the old one left, without this the NPC keeps walking
    omwself.controls.movement = 0
    omwself.controls.sideMovement = 0
    I.AI.startPackage({ type = "Wander", distance = 0, idle = wander.idle })

    local min, max = settings:get("IdleTimeMin"), settings:get("IdleTimeMax")
    if min > max then min, max = max, min end
    pauseUntil = core.getSimulationTime() + min + math.random() * (max - min)
    walkTime = 0
end

local function resume()
    I.AI.startPackage({
        type = "Wander",
        distance = wander.distance,
        duration = (wander.duration or 0) * 3600,
        idle = wander.idle,
        isRepeat = wander.isRepeat,
    })
    -- Travel goes on top, and the wander under it takes its home once the travel is done
    if home and (omwself.position - home):length() > HOME_TOLERANCE then
        I.AI.startPackage({ type = "Travel", destPosition = home, cancelOther = false })
    end
    pauseUntil = nil
    wander = nil
    walkTime = 0
end

local function update()
    if types.Actor.isDead(omwself) or not types.Actor.isInActorsProcessingRange(omwself) then return end

    local pkg = I.AI.getActivePackage()

    if pauseUntil then
        if not pkg or pkg.type ~= "Wander" then return end -- in combat or the like, wait it out
        if pkg.distance ~= 0 then
            -- Something else gave the NPC a new wander, leave it be
            pauseUntil = nil
            wander = nil
        elseif core.getSimulationTime() >= pauseUntil then
            resume()
        end
        return
    end

    local maxWanderTime = settings:get("MaxWanderTime")
    if maxWanderTime <= 0 or not isSmallIndoorWander(pkg) then
        walkTime = 0
        return
    end
    if not home then captureHome(pkg) end

    if types.Actor.getCurrentSpeed(omwself) > 0 then
        stillTicks = 0
        walkTime = walkTime + TICK
        if walkTime >= maxWanderTime and isOnlyPackage() then
            pause(pkg)
        end
    else
        -- Standing at two ticks in a row is an idle, not the short stop between two walks
        stillTicks = stillTicks + 1
        if stillTicks >= 2 then walkTime = 0 end
    end
end

local function tick()
    async:newUnsavableSimulationTimer(TICK, tick)
    update()
end

local function onActive()
    if not isNPC or started then return end
    started = true
    -- A random first delay spreads the NPCs' checks over the second
    async:newUnsavableSimulationTimer(math.random() * TICK, tick)
end

local function onSave()
    return { pauseUntil = pauseUntil, wander = wander, home = home }
end

local function onLoad(data)
    if not data then return end
    pauseUntil = data.pauseUntil
    wander = data.wander
    home = data.home
end

return {
    onActive = onActive,
    onSave = onSave,
    onLoad = onLoad,
}
