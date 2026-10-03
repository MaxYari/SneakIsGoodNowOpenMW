local mp = "scripts/MaxYari/SneakIsGoodNow/"

local camera = require("openmw.camera")
local core = require("openmw.core")
local input = require("openmw.input")
local nearby = require("openmw.nearby")
local storage = require("openmw.storage")
local types = require("openmw.types")
local util = require("openmw.util")
local omwself = require("openmw.self")
local I = require("openmw.interfaces")

local DEFS = require(mp .. 'utils/sneak_defs')
local leanSettings = require(mp .. 'settings').leanSettings

-- Leaning around corners. Only the camera moves, sideways and tilted: the body and its collider stay
-- where they are, and detection rays go to the body, so leaning shows more of the world but no more of you.
--
-- The built-in camera script zeroes the first person offset and the extra roll on every update before this
-- script's update runs, so they are added onto, which keeps head bobbing and Dynamic Camera's offsets. With
-- Dynamic Camera installed the roll goes through its interface instead, since it writes the summed roll of
-- every mod itself.

local LEAN_TIME = 0.3                       -- seconds from upright to a full lean
local ROLL_PER_UNIT = math.rad(12) / 40     -- 12 degrees per 40 units, 7.5 at the default 25
local MAX_ROLL = math.rad(25)
local DIP = 0.15                            -- the head drops a little as it leans out
local WALL_MARGIN = 16                      -- keeps the camera this far from walls, so it never sees through them
local STICK_DEADZONE = 0.15
local FOCAL_TRANSITION_SPEED = 4            -- third person: about half a second to a full lean (built-in default: 1)
local FOCAL_MIN_CHANGE = 2                  -- third person: smaller lean changes aren't written

local LEAN = DEFS.lean
local MODE = camera.MODE
local omwControls = storage.playerSection('SettingsOMWControls')

local target = 0            -- this frame's wanted lean, from input
local lean = 0              -- -1 full left .. 1 full right
local lastAlwaysRun = nil
local rollRegistered = false
local lastFocal = nil       -- third person: the focal offset last written here, and the lean part of it
local lastFocalLean = 0
local savedTransitionSpeed = nil
local focalSettleTime = 0

local function canLean()
    return not (core.isWorldPaused() or I.UI.getMode() or types.Actor.isDead(omwself)
        or not types.Player.getControlSwitch(omwself, types.Player.CONTROL_SWITCH.Controls))
end

-- A lean key as the settings store it (SuperKeybind2): a keyboard key's code, a mouse button's negated, or 1000
-- plus a controller button's
local function isBoundPressed(code)
    if type(code) ~= 'number' then return false end
    if code >= 1000 then return input.isControllerButtonPressed(code - 1000) end
    if code < 0 then return input.isMouseButtonPressed(-code) end
    return input.isKeyPressed(code)
end

local function leanButtonHeld()
    if leanSettings.LeanControllerButton == "Jump" then
        return input.isActionPressed(input.ACTION.Jump)
    end
    return input.isActionPressed(input.ACTION.Run) or input.isActionPressed(input.ACTION.AlwaysRun)
end

-- Runs after the built-in controls script has written this frame's movement, so strafing can be taken back
-- out of it. Lua can't stop a key from doing what it's bound to, only undo the parts that matter here: in
-- controller friendly mode the lean button is Run (does nothing while sneaking, a walk/run toggle is flipped
-- back) or Jump (can't jump while sneaking), and the strafe it's combined with is cancelled.
local function onFrame()
    target = 0
    local alwaysRun = omwControls:get('alwaysRun')
    if leanSettings.LeanInputMode == LEAN.keyboardMode then
        if canLean() then
            if isBoundPressed(leanSettings.LeanKeyLeft) then target = target - 1 end
            if isBoundPressed(leanSettings.LeanKeyRight) then target = target + 1 end
        end
    elseif omwself.controls.sneak and canLean() and leanButtonHeld() then
        local side = input.getRangeActionValue('MoveRight') - input.getRangeActionValue('MoveLeft')
        if math.abs(side) >= STICK_DEADZONE then target = util.clamp(side, -1, 1) end
        omwself.controls.sideMovement = 0
        if leanSettings.LeanControllerButton ~= "Jump" and lastAlwaysRun ~= nil and alwaysRun ~= lastAlwaysRun
            and input.isActionPressed(input.ACTION.AlwaysRun) then
            omwControls:set('alwaysRun', lastAlwaysRun)
            alwaysRun = lastAlwaysRun
        end
    end
    lastAlwaysRun = alwaysRun
end

-- How far the camera can move to the side (1 right, -1 left) before it gets too close to a wall
local function clearance(side, wanted)
    local from = camera.getTrackedPosition()
    local yaw = camera.getYaw()
    local right = util.vector3(math.cos(yaw), -math.sin(yaw), 0)
    local hit = nearby.castRay(from, from + right * (side * (wanted + WALL_MARGIN)), { ignore = omwself })
    if not hit.hit then return wanted end
    return math.max(0, (hit.hitPos - from):length() - WALL_MARGIN)
end

local function applyRoll(roll)
    local dynamicCamera = I.DynamicCamera
    if dynamicCamera and dynamicCamera.setExtraRoll then
        if roll ~= 0 then
            dynamicCamera.setExtraRoll(roll, DEFS.mod_name)
            rollRegistered = true
        elseif rollRegistered then
            dynamicCamera.setExtraRoll(nil, DEFS.mod_name)
            rollRegistered = false
        end
    elseif roll ~= 0 then
        camera.setExtraRoll(camera.getExtraRoll() + roll)
    end
end

-- The third person focal offset is only written by the built-in script when its shoulder state changes, so
-- the lean is taken back out of it before adding the new one, unless something else has written it since.
-- The engine eases the camera toward a new offset itself, but every write restarts that easing at a standstill
-- (camera.cpp, setFocalPointTargetOffset), so writing every frame leaves the camera crawling and jerking. Here the
-- whole lean is written only when it changes, with a quicker transition, like the built-in script's combat
-- offset; the speed is put back once the transition is done, unless something else has changed it meanwhile.
local function applyFocal(x, dt)
    if savedTransitionSpeed then
        focalSettleTime = focalSettleTime - dt
        if focalSettleTime <= 0 then
            if camera.getFocalTransitionSpeed() == FOCAL_TRANSITION_SPEED then
                camera.setFocalTransitionSpeed(savedTransitionSpeed)
            end
            savedTransitionSpeed = nil
        end
    end

    if x == lastFocalLean or (x ~= 0 and math.abs(x - lastFocalLean) < FOCAL_MIN_CHANGE) then return end
    local current = camera.getFocalPreferredOffset()
    local baseX = current.x
    if lastFocal and math.abs(current.x - lastFocal.x) < 1e-3 and math.abs(current.y - lastFocal.y) < 1e-3 then
        baseX = current.x - lastFocalLean
    end
    lastFocal = util.vector2(baseX + x, current.y)
    lastFocalLean = x
    camera.setFocalPreferredOffset(lastFocal)
    if not savedTransitionSpeed then savedTransitionSpeed = camera.getFocalTransitionSpeed() end
    camera.setFocalTransitionSpeed(FOCAL_TRANSITION_SPEED)
    focalSettleTime = 1
end

local function update(dt)
    if lean ~= target then
        local step = dt / LEAN_TIME
        lean = lean < target and math.min(target, lean + step) or math.max(target, lean - step)
    end

    local mode = camera.getMode()
    local side, offset = 0, 0
    if lean ~= 0 and (mode == MODE.FirstPerson or mode == MODE.ThirdPerson) then
        side = lean > 0 and 1 or -1
        local t = math.abs(lean)
        t = t * t * (3 - 2 * t)
        offset = clearance(side, (leanSettings.LeanAmount or 25) * t)
    end

    -- Negative roll tilts the view to the right
    applyRoll(-side * math.min(offset * ROLL_PER_UNIT, MAX_ROLL))
    if mode == MODE.FirstPerson and offset > 0 then
        camera.setFirstPersonOffset(camera.getFirstPersonOffset() + util.vector3(side * offset, 0, -offset * DIP))
    end

    -- Third person gets the whole lean the input asks for, the engine eases toward it
    local focalLean = 0
    if mode == MODE.ThirdPerson and target ~= 0 then
        local targetSide = target > 0 and 1 or -1
        focalLean = targetSide * clearance(targetSide, (leanSettings.LeanAmount or 25) * math.abs(target))
    end
    applyFocal(focalLean, dt)
end

return {
    onFrame = onFrame,
    update = update,
}
