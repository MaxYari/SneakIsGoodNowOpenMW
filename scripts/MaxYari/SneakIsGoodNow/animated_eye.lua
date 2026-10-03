local mp = "scripts/MaxYari/SneakIsGoodNow/"

local ui = require("openmw.ui")
local util = require("openmw.util")
local core = require("openmw.core")
local async = require("openmw.async")
local storage = require("openmw.storage")
local I = require("openmw.interfaces")

local DetectionMarker = require(mp .. "Sneak_ui_elements")
local s = require(mp .. "settings")
local DEFS = require(mp .. "utils/sneak_defs")
local hud = require(mp .. "utils/hud")
local PRESET = DEFS.eyePreset
local PRESET_VALUES = DEFS.eyePresetValues

-- The animated eye detection indicator: an eye that opens with the detection progress of the most alert NPC around,
-- in its original colors or, with the "EyeColored" setting, colored like that NPC's marker. The eye is the crosshair
-- of Stealth Overhaul 2 by Storm Atronach (https://www.nexusmods.com/morrowind/mods/57321), used with permission: its
-- 21 frames, put into atlases by tools/gen_detection_ui_textures.py (as they are, and white for tinting), closed (0)
-- to open (20). Each eye size has atlases of its own, scaled down from the original 128 px frames, since the game
-- shrinking them itself looks jagged. At "Eye size multiplier" 1 they're drawn 1:1 (at UI scale 1).

local FRAMES = 21
local COLUMNS = 8
local SIZES = { Big = 96, Medium = 72, Small = 48 }
local FOLLOW_SPEED = 8      -- how quickly the eye follows the detection progress
local NOTICED = 0.1         -- with "EyeOnlyWhenNoticed", the detection progress the eye shows from
local FADE_SPEED = 10
local WHITE = util.color.rgb(1, 1, 1)

-- The open eye's edges in its frame, as fractions of the frame: x 5 to 123, y 30 to 98 of the original 128 px.
-- It closes towards the middle.
local EYE_LEFT = 5 / 128
local EYE_BOTTOM = 98 / 128

-- Where the presets put the eye, in UI units like everything else here, worked out from the eye's size. "bars": the
-- vanilla HUD (openmw_hud.layout) has the health, magicka and fatigue bars 13 units from the left edge, and the enemy
-- health bar above them, its top 69 units above the bottom edge.
local GAP = 4
local BARS_LEFT = 13
local BARS_TOP = 69

-- Changing where the eye goes or how big it is shows it fully open for PREVIEW_HOLD seconds, then fades it out over
-- PREVIEW_FADE, in real time since the settings menu pauses the game. It's drawn over the menus while it shows.
local PREVIEW_HOLD = 1.5
local PREVIEW_FADE = 0.5
local PREVIEW_LAYER = 'Notification'
local PREVIEW_KEYS = { EyePreset = true, EyeX = true, EyeY = true, EyeSize = true, EyeSizeMult = true }

-- Dynamic Reticle's crosshair fades out as the eye fades in, with the "EyeHidesDynamicReticle" setting
local DR_SOURCE = DEFS.mod_name

local function atlasFrames(path, cell)
    local frames = {}
    for i = 0, FRAMES - 1 do
        frames[i] = ui.texture {
            path = path,
            offset = util.vector2((i % COLUMNS) * cell, math.floor(i / COLUMNS) * cell),
            size = util.vector2(cell, cell),
        }
    end
    return frames
end
-- By eye size: the frames as they are, and white for tinting
local atlases = {}
for name, cell in pairs(SIZES) do
    local path = mp .. "textures/animated_eye_atlas_" .. cell
    atlases[name] = {
        cell = cell,
        original = atlasFrames(path .. ".png", cell),
        tintable = atlasFrames(path .. "_white.png", cell),
    }
end

local function currentAtlas()
    return atlases[s.eyeSettings.EyeSize] or atlases.Big
end

-- The eye's size on screen, in UI units
local function eyeSize()
    return currentAtlas().cell * math.max(s.eyeSettings.EyeSizeMult or 1, 0)
end

local element = nil
local elementLayer = nil
local shownProgress = 0
local shownFraction = 0     -- 0 hidden .. 1 fully shown, the opacity setting not counted
local preview = 0           -- 1 while previewing a placement, fading to 0 after
local previewUntil = -math.huge
local lastFrameTime = nil
local drAlpha = 1
-- What the element shows now, so it's only updated when something changes
local shown = {}
-- The latest state from update(), drawn again by onFrame while the game is paused
local state = { progress = 0, isAggressive = true }

local function smooth(from, to, speed, dt)
    return from + (to - from) * (1 - math.exp(-speed * dt))
end

-- Where the eye's middle goes, in UI units, for a preset and the eye's size. Custom: the position sliders.
local function placement(preset, size)
    local hudSize = hud.size()
    local values = PRESET_VALUES[preset]
    if values and values.position == "bars" then
        local x = BARS_LEFT + (0.5 - EYE_LEFT) * size
        return util.vector2(x, hudSize.y - BARS_TOP - GAP - (EYE_BOTTOM - 0.5) * size)
    elseif values then
        return hudSize * 0.5
    end
    return util.vector2(hudSize.x * s.eyeSettings.EyeX, hudSize.y * s.eyeSettings.EyeY)
end

-- Presets are starting points. Picking one sets its settings, and the position sliders show where it puts the eye
-- (worked out anew whenever its size or the HUD's changes). Changing any of those settings by hand switches to Custom,
-- from where the eye was. Written from onFrame, outside the storage callback, and flagged so they don't count as the
-- player's.
local eyeSection = storage.playerSection('SettingsSneakIsGoodNowEye')
local synced = {}        -- the slider values last written here; anything else came from the player
local syncedHud = nil    -- the HUD size they were worked out for
local syncing = false
local needsApply = true  -- on load too, so the settings are the preset's from the start
local toCustom = false

local function applyPreset(hudSize)
    local values = PRESET_VALUES[eyeSection:get('EyePreset')]
    syncing = true
    if needsApply then
        for key, value in pairs(values) do
            if key ~= "position" and eyeSection:get(key) ~= value then eyeSection:set(key, value) end
        end
    end
    needsApply = false
    syncedHud = hudSize
    local pos = placement(eyeSection:get('EyePreset'), eyeSize())
    synced.EyeX, synced.EyeY = pos.x / hudSize.x, pos.y / hudSize.y
    eyeSection:set('EyeX', synced.EyeX)
    eyeSection:set('EyeY', synced.EyeY)
    syncing = false
end

eyeSection:subscribe(async:callback(function(_, key)
    if syncing then return end
    if key == nil or PREVIEW_KEYS[key] then previewUntil = core.getRealTime() + PREVIEW_HOLD end
    local values = PRESET_VALUES[eyeSection:get('EyePreset')]
    if not values then return end
    if key == nil or key == 'EyePreset' then
        needsApply = true
    elseif key == 'EyeX' or key == 'EyeY' then
        -- A slider set to the value it already had (clicking into its text box does that) changes nothing
        if eyeSection:get(key) ~= synced[key] then toCustom = true end
    elseif values[key] ~= nil and eyeSection:get(key) ~= values[key] then
        toCustom = true
    end
end))

local function setDynamicReticleAlpha(alpha)
    if alpha == drAlpha then return end
    local dr = I.DynamicReticle
    if not (dr and type(dr.setAlphaMultiplier) == "function") then return end
    if pcall(dr.setAlphaMultiplier, DR_SOURCE, alpha) then drAlpha = alpha end
end

local function draw()
    local layer = preview > 0 and PREVIEW_LAYER or 'HUD'
    local alpha = shownFraction * s.eyeSettings.EyeAlpha
    alpha = alpha + (1 - alpha) * preview
    local progress = math.max(shownProgress, preview)

    if element and (elementLayer ~= layer or alpha == 0) then
        element:destroy()
        element = nil
        shown = {}
    end
    if not element then
        if alpha == 0 then return end
        element = ui.create {
            layer = layer,
            type = ui.TYPE.Image,
            props = { anchor = util.vector2(0.5, 0.5), alpha = 0 },
        }
        elementLayer = layer
    end

    local colored = s.eyeSettings.EyeColored
    local atlas = currentAtlas()
    local frame = math.floor(progress * (FRAMES - 1) + 0.5)
    local shownAlpha = math.floor(alpha * 50 + 0.5) / 50
    local colorStep = colored and math.floor(progress * 200 + 0.5) + (state.isAggressive and 1000 or 0) or -1
    local size = eyeSize()
    local pos = placement(s.eyeSettings.EyePreset, size)
    if frame == shown.frame and shownAlpha == shown.alpha and colorStep == shown.colorStep
        and pos == shown.pos and size == shown.size and atlas == shown.atlas then
        return
    end
    shown.frame, shown.alpha, shown.colorStep, shown.pos, shown.size, shown.atlas =
        frame, shownAlpha, colorStep, pos, size, atlas

    local props = element.layout.props
    props.resource = (colored and atlas.tintable or atlas.original)[frame]
    props.color = colored and DetectionMarker.detectionColor(progress, state.isAggressive) or WHITE
    props.alpha = shownAlpha
    props.visible = shownAlpha > 0
    props.position = pos
    props.size = util.vector2(size, size)
    element:update()
end

-- visible: whether the eye should be shown at all (sneaking, and enabled in the settings)
local function update(dt, visible, progress, isAggressive)
    if s.eyeSettings.EyeOnlyWhenNoticed and progress < NOTICED then visible = false end
    state.progress, state.isAggressive = progress, isAggressive
    shownFraction = smooth(shownFraction, visible and 1 or 0, FADE_SPEED, dt)
    if not visible and shownFraction < 0.01 then shownFraction = 0 end
    local targetProgress = visible and progress or 0
    shownProgress = smooth(shownProgress, targetProgress, FOLLOW_SPEED, dt)
    if math.abs(shownProgress - targetProgress) < 0.005 then shownProgress = targetProgress end

    -- Dynamic Reticle's crosshair takes the eye's place whenever the eye is hidden, unnoticed included
    local hideDr = s.eyeSettings.EyeHidesDynamicReticle and s.eyeSettings.EyeAlpha > 0
    setDynamicReticleAlpha(hideDr and math.floor((1 - shownFraction) * 50 + 0.5) / 50 or 1)

    draw()
end

-- Every frame, paused or not: the preset's settings and the placement preview
local function onFrame()
    local now = core.getRealTime()
    local dt = now - (lastFrameTime or now)
    lastFrameTime = now
    if toCustom then
        toCustom = false
        eyeSection:set('EyePreset', PRESET.custom)
    end
    if PRESET_VALUES[eyeSection:get('EyePreset')] then
        local hudSize = hud.size()
        if needsApply or hudSize ~= syncedHud then applyPreset(hudSize) end
    end

    local wasPreviewing = preview > 0
    if now < previewUntil then
        preview = 1
    elseif preview > 0 then
        preview = math.max(0, preview - dt / PREVIEW_FADE)
    end
    if preview > 0 or wasPreviewing then draw() end
end

return {
    update = update,
    onFrame = onFrame,
}
