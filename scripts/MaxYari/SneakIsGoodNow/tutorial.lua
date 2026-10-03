local mp = "scripts/MaxYari/SneakIsGoodNow/"

local ui = require("openmw.ui")
local util = require("openmw.util")
local core = require("openmw.core")
local async = require("openmw.async")
local input = require("openmw.input")
local types = require("openmw.types")
local omwself = require("openmw.self")
local I = require("openmw.interfaces")
local mwuiConstants = require("scripts.omw.mwui.constants")

local DEFS = require(mp .. "utils/sneak_defs")
local leanSettings = require(mp .. "settings").leanSettings

-- A tutorial window, shown after sneaking for a couple of seconds: what sneaking does, and how to lean around corners
-- with the lean controls as they're set now. Shown once per character: that it was is kept in the save.

local SNEAK_TIME = 2         -- seconds of sneaking before it shows
local WIDTH = 360            -- of the text
local MARGIN = 16

local shown = false
local sneakTime = 0
local element = nil

local controllerButtonNames = {}
for name, id in pairs(input.CONTROLLER_BUTTON) do controllerButtonNames[id] = name end

-- A lean key as SuperKeybind2 stores it: a keyboard key's code, a mouse button's negated, 1000 plus a controller button's
local function keyName(code)
    if type(code) ~= 'number' then return "?" end
    if code >= 1000 then return "controller " .. (controllerButtonNames[code - 1000] or tostring(code - 1000)) end
    if code < 0 then return "mouse button " .. -code end
    local name = input.getKeyName(code)
    return (name and name ~= "") and name or ("key " .. code)
end

local function leanText()
    if leanSettings.LeanInputMode == DEFS.lean.keyboardMode then
        return ("hold %s or %s to lean left or right"):format(keyName(leanSettings.LeanKeyLeft), keyName(leanSettings.LeanKeyRight))
    end
    return ("hold %s and move left or right to lean"):format(leanSettings.LeanControllerButton == "Jump" and "Jump" or "Run")
end

local function spacer(size)
    return { props = { size = util.vector2(size, size) } }
end

local function paragraph(text)
    return {
        template = I.MWUI.templates.textParagraph,
        props = { text = text, size = util.vector2(WIDTH, 0) },
    }
end

local function sneakSkillRow()
    local record = core.stats.Skill.records.sneak
    local skill = types.NPC.stats.skills.sneak(omwself).modified
    return {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                props = { resource = ui.texture { path = record.icon }, size = util.vector2(32, 32) },
            },
            spacer(8),
            { template = I.MWUI.templates.textHeader, props = { text = ("%s %d"):format(record.name, skill) } },
        },
    }
end

local function close()
    if not element then return end
    element:destroy()
    element = nil
    if I.UI.getMode() == 'Interface' then I.UI.removeMode('Interface') end
end

local function okButton()
    return {
        template = I.MWUI.templates.box,
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = core.l10n('Interface')('OK'),
                            -- A fixed size, so the button is wider than its text: one line of the menu font tall
                            size = util.vector2(80, mwuiConstants.textNormalSize),
                            autoSize = false,
                            textAlignH = ui.ALIGNMENT.Center,
                            textAlignV = ui.ALIGNMENT.Center,
                        },
                    },
                },
            },
        },
        events = { mouseClick = async:callback(close) },
    }
end

local function show()
    shown = true
    local skillName = core.stats.Skill.records.sneak.name
    local body = {
        type = ui.TYPE.Flex,
        props = { arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            spacer(MARGIN),
            { template = I.MWUI.templates.textHeader, props = { text = "Remaining Undetected" } },
            spacer(MARGIN),
            paragraph(("While sneaking you can move around unnoticed. How well that goes depends mostly on your %s skill.")
                :format(skillName)),
            spacer(8),
            sneakSkillRow(),
            spacer(8),
            paragraph(("You can safely peek from behind corners without a risk of being noticed: %s. Only your view " ..
                "leans out, your body stays where it is."):format(leanText())),
            spacer(8),
            paragraph("Lean controls are in Options > Scripts > Sneak!"),
            spacer(MARGIN),
            okButton(),
            spacer(MARGIN),
        },
    }
    element = ui.create {
        layer = 'Modal',
        props = { relativeSize = util.vector2(1, 1) },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                props = { resource = ui.texture { path = 'black' }, relativeSize = util.vector2(1, 1), alpha = 0.5 },
            },
            {
                template = I.MWUI.templates.boxSolidThick,
                props = { anchor = util.vector2(0.5, 0.5), relativePosition = util.vector2(0.5, 0.5) },
                content = ui.content {
                    {
                        type = ui.TYPE.Flex,
                        props = { horizontal = true },
                        content = ui.content { spacer(MARGIN), body, spacer(MARGIN) },
                    },
                },
            },
        },
    }
    -- The cursor, and the game paused like in any menu (unless a mod like Unpause keeps menus running), without any
    -- of the game's own windows
    I.UI.addMode('Interface', { windows = {} })
end

-- Every update the game isn't paused
local function update(dt, isSneaking)
    if element or shown then return end
    if isSneaking and not I.UI.getMode() then
        sneakTime = sneakTime + dt
        if sneakTime >= SNEAK_TIME then show() end
    else
        sneakTime = 0
    end
end

-- The window goes with the mode it opened, closed by OK or by Escape alike
local function onUiModeChanged(data)
    if element and data.newMode ~= 'Interface' then
        element:destroy()
        element = nil
    end
end

return {
    update = update,
    onUiModeChanged = onUiModeChanged,
    -- For the player script's onSave / onLoad
    isShown = function() return shown end,
    setShown = function(value) shown = value == true end,
}
