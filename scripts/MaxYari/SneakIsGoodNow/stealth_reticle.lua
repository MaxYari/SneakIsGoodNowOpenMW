local mp = "scripts/MaxYari/SneakIsGoodNow/"

local ui = require("openmw.ui")
local util = require("openmw.util")

local DetectionMarker = require(mp .. "Sneak_ui_elements")
local s = require(mp .. "settings")

-- The stealth reticle: an eye that opens with the detection progress of the most alert NPC around, in its original
-- colors or, with the "ReticleColored" setting, colored like that NPC's marker. The eye is the crosshair of Stealth
-- Overhaul 2 by Storm Atronach (https://www.nexusmods.com/morrowind/mods/57321), used with permission: its 21
-- frames, put into atlases by tools/gen_detection_ui_textures.py (as they are, and white for tinting), closed (0)
-- to open (20).

local FRAMES = 21
local COLUMNS = 8
local CELL = 128
local SIZE = util.vector2(128, 128)   -- at "Reticle size" 1
local FOLLOW_SPEED = 8      -- how quickly the eye follows the detection progress
local FADE_SPEED = 10
local WHITE = util.color.rgb(1, 1, 1)

local function atlasFrames(path)
    local frames = {}
    for i = 0, FRAMES - 1 do
        frames[i] = ui.texture {
            path = path,
            offset = util.vector2((i % COLUMNS) * CELL, math.floor(i / COLUMNS) * CELL),
            size = util.vector2(CELL, CELL),
        }
    end
    return frames
end
local originalFrames = atlasFrames(mp .. "textures/stealth_reticle_atlas.png")
local tintableFrames = atlasFrames(mp .. "textures/stealth_reticle_atlas_white.png")

local element = nil
local shownProgress = 0
local alpha = 0
-- What the element shows now, so it's only updated when something changes
local shown = {}

local function smooth(from, to, speed, dt)
    return from + (to - from) * (1 - math.exp(-speed * dt))
end

-- visible: whether the reticle should be shown at all (sneaking, and enabled in the settings)
local function update(dt, visible, progress, isAggressive)
    local targetAlpha = visible and s.uiSettings.ReticleAlpha or 0
    alpha = smooth(alpha, targetAlpha, FADE_SPEED, dt)
    if targetAlpha == 0 and alpha < 0.01 then alpha = 0 end
    local targetProgress = visible and progress or 0
    shownProgress = smooth(shownProgress, targetProgress, FOLLOW_SPEED, dt)
    if math.abs(shownProgress - targetProgress) < 0.005 then shownProgress = targetProgress end

    if not element then
        if alpha == 0 then return end
        element = ui.create {
            layer = 'HUD',
            type = ui.TYPE.Image,
            props = { size = SIZE, anchor = util.vector2(0.5, 0.5), resource = originalFrames[0], alpha = 0 },
        }
    end

    local colored = s.uiSettings.ReticleColored
    local frame = math.floor(shownProgress * (FRAMES - 1) + 0.5)
    local shownAlpha = math.floor(alpha * 50 + 0.5) / 50
    local colorStep = colored and math.floor(shownProgress * 200 + 0.5) + (isAggressive and 1000 or 0) or -1
    local x, y, scale = s.uiSettings.ReticleX, s.uiSettings.ReticleY, s.uiSettings.ReticleScale
    if frame == shown.frame and shownAlpha == shown.alpha and colorStep == shown.colorStep
        and x == shown.x and y == shown.y and scale == shown.scale then
        return
    end
    shown.frame, shown.alpha, shown.colorStep, shown.x, shown.y, shown.scale = frame, shownAlpha, colorStep, x, y, scale

    local props = element.layout.props
    props.resource = (colored and tintableFrames or originalFrames)[frame]
    props.color = colored and DetectionMarker.detectionColor(shownProgress, isAggressive) or WHITE
    props.alpha = shownAlpha
    props.visible = shownAlpha > 0
    props.relativePosition = util.vector2(x, y)
    props.size = SIZE * scale
    element:update()
end

return {
    update = update,
}
