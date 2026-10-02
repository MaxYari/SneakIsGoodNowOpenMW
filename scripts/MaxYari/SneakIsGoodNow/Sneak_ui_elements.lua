local mp = "scripts/MaxYari/SneakIsGoodNow/"

local ui = require("openmw.ui")
local util = require("openmw.util")
local camera = require("openmw.camera")
local I = require("openmw.interfaces")

local gutils = require(mp .. 'utils/gutils')
local Tweener = require(mp .. 'utils/tweener')
local s = require(mp .. "settings")

-- DetectionMarker class
local DetectionMarker = {}
DetectionMarker.__index = DetectionMarker

-- Config
local markerBgColor = util.color.hex("0f0f1f")
local markerFillColor = util.color.hex("efc36b")
local markerFillDangerColor = util.color.hex("c01c28") -- Saturated red for danger
local markerGrayColor = util.color.hex("808080") -- Gray for non-aggressive

local disappearAnimScale = 1.5 -- How much a marker grows when its NPC spots the player

-- Arrow beside an off-screen marker, pointing where to turn (sizes at "Marker size" 1). Image widgets can't rotate, so the atlas made by
-- tools/gen_detection_ui_textures.py holds 32 rotations, clockwise from pointing right
local arrowSize = util.vector2(20, 20)
local arrowGap = 4
local ARROW_DIRECTIONS = 32
local arrowTextures = {}
for i = 0, ARROW_DIRECTIONS - 1 do
    arrowTextures[i] = ui.texture {
        path = mp .. "textures/marker_arrow_atlas.png",
        offset = util.vector2((i % 8) * 32, math.floor(i / 8) * 32),
        size = util.vector2(32, 32),
    }
end

-- Detection color: gray for an NPC that won't attack, otherwise yellow, turning red from 66% on
local function detectionColor(progress, isAggressive)
    if not isAggressive then return markerGrayColor end
    if progress < 0.66 then return markerFillColor end
    local lerpT = util.clamp(util.remap(progress, 0.66, 1.0, 0, 1), 0, 1)
    return gutils.lerpColor(markerFillColor, markerFillDangerColor, lerpT)
end
DetectionMarker.detectionColor = detectionColor

local whiteTexture = ui.texture { path = 'white' }

-- Marker styles: their size at "Marker size" 1, what's inside the marker, how it shows progress, and how it's
-- resized (the disappear animation grows the marker of an NPC that spotted the player)
local styles = {}

-- A crescent filling up from the bottom, with a glow
styles.crescent = {
    size = util.vector2(50, 50),
    content = function(size)
        return ui.content {
            {
                name = "detectionMarkerBg",
                type = ui.TYPE.Image,
                props = {
                    relativeSize = util.vector2(1, 1),
                    color = markerBgColor,
                    alpha = 0.5,
                    resource = ui.texture { path = mp .. "textures/detection_marker_bg.png" }
                }
            },
            {
                name = "detectionMarkerGlow",
                type = ui.TYPE.Image,
                props = {
                    relativeSize = util.vector2(1, 1),
                    color = markerFillColor,
                    alpha = 0.5,
                    resource = ui.texture { path = mp .. "textures/detection_marker_glow.png" }
                }
            },
            {
                name = "detectionFillWrapper",
                type = ui.TYPE.Widget,
                props = {
                    relativeSize = util.vector2(1, 0), -- Will be updated by setProgress
                    relativePosition = util.vector2(0.5, 1), -- Anchored at bottom center
                    anchor = util.vector2(0.5, 1), -- Anchor at bottom center
                    alpha = 1.0,
                },
                content = ui.content {
                    {
                        name = "detectionFill",
                        type = ui.TYPE.Image,
                        props = {
                            alpha = 0.8,
                            size = size, -- Same as parent to fill when relativeSize is 1,1
                            color = markerFillColor,
                            relativePosition = util.vector2(0.5, 1),
                            anchor = util.vector2(0.5, 1),
                            resource = ui.texture { path = mp .. "textures/detection_marker_fill.png" }
                        }
                    }
                }
            }
        }
    end,
    setProgress = function(element, progress, color)
        -- Reveal more of the fill image by growing the height of its wrapper
        local wrapper = element.layout.content["detectionFillWrapper"]
        wrapper.props.relativeSize = util.vector2(1, util.remap(progress, 0, 1, 0.2, 0.8))
        wrapper.content["detectionFill"].props.alpha = gutils.lerp(0.33, 0.8, progress)
        wrapper.content["detectionFill"].props.color = color
        element.layout.content["detectionMarkerGlow"].props.alpha = gutils.lerp(0.1, 1, progress)
        element.layout.content["detectionMarkerGlow"].props.color = color
    end,
    setSize = function(element, size)
        element.layout.props.size = size
        element.layout.content["detectionFillWrapper"].content["detectionFill"].props.size = size
    end,
}

-- A vanilla-looking box: the thin menu border around a dark background, with a rectangle growing from the center
-- that fills it at full detection
styles.box = {
    size = util.vector2(25, 25),
    template = function() return I.MWUI.templates.borders end,
    content = function()
        return ui.content {
            {
                name = "background",
                type = ui.TYPE.Image,
                props = {
                    relativeSize = util.vector2(1, 1),
                    resource = whiteTexture,
                    color = util.color.rgb(0, 0, 0),
                    alpha = 0.6,
                }
            },
            {
                name = "fill",
                type = ui.TYPE.Image,
                props = {
                    relativeSize = util.vector2(0, 0),
                    relativePosition = util.vector2(0.5, 0.5),
                    anchor = util.vector2(0.5, 0.5),
                    resource = whiteTexture,
                    color = markerFillColor,
                    alpha = 0.85,
                }
            }
        }
    end,
    setProgress = function(element, progress, color)
        local fill = element.layout.content["fill"]
        fill.props.relativeSize = util.vector2(progress, progress)
        fill.props.color = color
    end,
    setSize = function(element, size)
        element.layout.props.size = size
    end,
}

local styleBySetting = {
    ["Crescent"] = styles.crescent,
    ["Vanilla box"] = styles.box,
}

-- Constructor that creates a new UI element upon instantiation
function DetectionMarker:new()
    local instance = setmetatable({}, DetectionMarker)

    -- Initialize tweeners dictionary
    instance.tweeners = {}

    -- Initialize aggressive state
    instance.isAggressive = false

    instance.style = styleBySetting[s.uiSettings.MarkerStyle] or styles.crescent
    instance.scale = s.uiSettings.MarkerScale or 1
    instance.size = instance.style.size * instance.scale
    instance.element = ui.create({
        layer = 'HUD',
        type = ui.TYPE.Widget,
        template = instance.style.template and instance.style.template() or nil,
        name = "detectionMarkerWrapper",
        props = {
            size = instance.size,
            alpha = 0, -- Start with alpha 0 for appear animation
            position = util.vector2(0, 0), -- Will be set by setWorldPos
            anchor = util.vector2(0.5, 1),
        },
        content = instance.style.content(instance.size),
    })

    instance.color = markerFillColor
    instance.arrow = ui.create({
        layer = 'HUD',
        type = ui.TYPE.Image,
        props = {
            size = arrowSize * instance.scale,
            anchor = util.vector2(0.5, 0.5),
            visible = false,
            alpha = 0,
            color = markerFillColor,
            resource = arrowTextures[0],
        }
    })

    -- Automatically trigger appear animation upon instantiation
    instance:appear()

    return instance
end

-- Method to set the detection progress
function DetectionMarker:setProgress(progress)
    -- Clamp progress between 0 and 1
    progress = util.clamp(progress, 0, 1)
    self.color = detectionColor(progress, self.isAggressive)
    self.style.setProgress(self.element, progress, self.color)
    self.element:update()
end

function DetectionMarker:setWorldPos(worldPos)
    local screenSize = ui.screenSize()
    local center = util.vector2(screenSize.x * 0.5, screenSize.y * 0.5)

    -- Projected screen position (for on-screen case)
    local proj = camera.worldToViewportVector(worldPos)
    local screenPos = util.vector2(proj.x, proj.y)

    -- Get camera-space coordinates
    local camSpace = camera.getViewTransform():apply(worldPos)
    local xCam, yCam, zCam = camSpace.x, camSpace.y, camSpace.z
    local screenSideFlipper = zCam/math.abs(zCam)

    -- Check if target is visible on-screen (in front and within screen bounds)
    local isVisible =
        zCam < 0 and
        screenPos.x >= 0 and screenPos.x <= screenSize.x and
        screenPos.y >= 0 and screenPos.y <= screenSize.y

    if isVisible then
        -- On-screen: use projection directly
        local relScreenPos = util.vector2(screenPos.x/screenSize.x, screenPos.y/screenSize.y)
        self.element.layout.props.relativePosition = relScreenPos
        self.element:update()
        if self.arrow.layout.props.visible then
            self.arrow.layout.props.visible = false
            self.arrow:update()
        end
        return
    end

    -- Off-screen or behind camera: compute stable 2D direction from camera space
    local dir = util.vector2(xCam, yCam)

    -- If target is directly on the camera forward axis, pick default direction
    if dir.x == 0 and dir.y == 0 then
        dir = util.vector2(0, 1)
    end

    -- Normalize direction
    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
    dir = util.vector2(screenSideFlipper * dir.x / len, -screenSideFlipper * dir.y / len)

    -- If target is behind the camera, invert direction
    if zCam < 0 then
        dir = -dir
    end

    -- Pinned to the edges of a centered area narrower than the screen, so it isn't lost in the periphery. The
    -- area is inset by the marker and the arrow beside it, so both stay inside it
    local halfWidth = screenSize.x * util.clamp(s.uiSettings.MarkerPinWidth or 0.75, 0.2, 1) * 0.5
    local halfHeight = screenSize.y * 0.5
    local arrowDistance = self.size.x * 0.5 + (arrowGap + arrowSize.x * 0.5) * self.scale
    local inset = arrowDistance + arrowSize.x * 0.5 * self.scale
    local scaleX = math.abs(dir.x) > 0 and (math.max(0, halfWidth - inset) / math.abs(dir.x)) or math.huge
    local scaleY = math.abs(dir.y) > 0 and (math.max(0, halfHeight - inset) / math.abs(dir.y)) or math.huge
    local markerCenter = center + dir * math.min(scaleX, scaleY)

    -- The marker's anchor is its bottom center
    local markerPos = markerCenter + util.vector2(0, self.size.y * 0.5)
    self.element.layout.props.relativePosition = util.vector2(markerPos.x / screenSize.x, markerPos.y / screenSize.y)
    self.element:update()

    local arrowPos = markerCenter + dir * arrowDistance
    local direction = math.floor(math.atan2(dir.y, dir.x) / (2 * math.pi) * ARROW_DIRECTIONS + 0.5) % ARROW_DIRECTIONS
    local arrowProps = self.arrow.layout.props
    arrowProps.relativePosition = util.vector2(arrowPos.x / screenSize.x, arrowPos.y / screenSize.y)
    arrowProps.resource = arrowTextures[direction]
    arrowProps.color = self.color
    arrowProps.alpha = self.element.layout.props.alpha
    arrowProps.visible = true
    self.arrow:update()
end

function DetectionMarker:setAggressive(aggressive)
    self.isAggressive = aggressive or false
    self.element:update()
end




-- Method to create appearance animation
function DetectionMarker:appear()
    -- Check if an appear animation is already running
    if self.tweeners["appear"] and self.tweeners["appear"].playing then
        return -- Animation already running, don't start another
    end

    -- Create a new tweener instance for this animation
    local tweener = Tweener:new()

    -- Add the alpha animation from 0 to 1 with callback
    tweener:add(
        0.3, -- Duration in seconds
        Tweener.easings.easeOutQuad, -- Easing function
        function(value)
            self.element.layout.props.alpha = value * s.uiSettings.MarkersAlpha
            self.element:update()
        end
    )

    -- Store the tweener directly
    self.tweeners["appear"] = tweener

    return "appear"
end

-- Method to create disappearance animation
function DetectionMarker:disappear(wasSuccessful, autoDestroy)
    if self.destroyed then
        return
    end

    if wasSuccessful == nil then
        wasSuccessful = false
    end
    if autoDestroy == nil then
        autoDestroy = true
    end

    -- Check if a disappear animation is already running
    if self.tweeners["disappear"] and self.tweeners["disappear"].playing then
        return -- Animation already running, don't start another
    end

    -- Stop and remove the appear animation if it's still running
    if self.tweeners["appear"] and self.tweeners["appear"].playing then
        self.tweeners["appear"] = nil
    end

    -- Create a new tweener instance for this animation
    local tweener = Tweener:new()

    -- Store initial values for the animation
    -- Use fixed alpha = 1 to ensure marker is visible during disappear animation
    local initialSize = self.element.layout.props.size
    local initialAlpha = s.uiSettings.MarkersAlpha    

    -- Add the size animation from current size to disappear size with cleanup callback
    tweener:add(
        0.5, -- Duration in seconds
        Tweener.easings.easeOutQuad, -- Easing function
        function(value)
            -- Interpolate between current size and disappear size using gutils.lerp
            if wasSuccessful == true then
                self.style.setSize(self.element, gutils.lerp(initialSize, self.size * disappearAnimScale, value))
            end

            -- Interpolate alpha from current alpha to 0 using gutils.lerp            
            local newAlpha = gutils.lerp(initialAlpha, 0, value)
            self.element.layout.props.alpha = newAlpha

            self.element:update()
        end,
        function(value)
            -- Callback to execute after animation completes
            if autoDestroy then
                self:destroy()
            end
        end
    )

    -- Store the tweener directly
    self.tweeners["disappear"] = tweener

    return "disappear"
end

function DetectionMarker:destroy()
    self.element:destroy()
    self.arrow:destroy()
    self.destroyed = true
end

-- Method to update all active tweeners
function DetectionMarker:updateTweeners(dt)
    for id, tweener in pairs(self.tweeners) do
        tweener:tick(dt)

        -- If the animation is complete, remove the tweener from the dictionary
        -- The callback is handled internally by the Tweener class
        if #tweener.animations == 0 and not tweener.playing then
            self.tweeners[id] = nil
        end
    end
end

return DetectionMarker
