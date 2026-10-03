-- Menu-side half of the settings: the animated eye's on/off toggle, drawn with the eye it turns on so it's clear
-- what that is. Custom setting renderers can only be registered from a menu script.

local ui = require('openmw.ui')
local util = require('openmw.util')
local core = require('openmw.core')
local async = require('openmw.async')
local I = require('openmw.interfaces')

local mp = "scripts/MaxYari/SneakIsGoodNow/"

-- The fully open eye, the last of the Big size's 96 px frames, cut down to the eye itself and drawn 1:1 (see
-- animated_eye.lua)
local EYE_SIZE = util.vector2(90, 52)
local EYE = ui.texture {
    path = mp .. "textures/animated_eye_atlas_96.png",
    offset = util.vector2(4 * 96 + 3, 2 * 96 + 22),
    size = EYE_SIZE,
}
local PADDING = 6

local l10n = core.l10n('Interface')

-- The built-in checkbox's look: Yes or No in a box, clicked to switch
local function toggle(value, set)
    return {
        template = I.MWUI.templates.box,
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = { text = l10n(value and 'Yes' or 'No') },
                    },
                },
            },
        },
        events = { mouseClick = async:callback(function() set(not value) end) },
    }
end

local function eyePreview()
    return {
        template = I.MWUI.templates.box,
        content = ui.content {
            {
                type = ui.TYPE.Widget,
                props = { size = EYE_SIZE + util.vector2(2, 2) * PADDING },
                content = ui.content {
                    {
                        type = ui.TYPE.Image,
                        props = {
                            relativeSize = util.vector2(1, 1),
                            resource = ui.texture { path = 'white' },
                            color = util.color.rgb(0, 0, 0),
                            alpha = 0.6,
                        },
                    },
                    {
                        type = ui.TYPE.Image,
                        props = { position = util.vector2(PADDING, PADDING), size = EYE_SIZE, resource = EYE },
                    },
                },
            },
        },
    }
end

I.Settings.registerRenderer('SneakIsGoodNow_eyeToggle', function(value, set)
    return {
        type = ui.TYPE.Flex,
        props = { arrange = ui.ALIGNMENT.End },
        content = ui.content {
            toggle(value, set),
            { template = I.MWUI.templates.interval },
            eyePreview(),
        },
    }
end)
