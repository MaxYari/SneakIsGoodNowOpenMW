local mp = "scripts/MaxYari/SneakIsGoodNow/"

local I = require('openmw.interfaces')
local input = require('openmw.input')
local storage = require('openmw.storage')

local SettingsHelper = require(mp .. "utils/settings_helper")
local DEFS = require(mp .. 'utils/sneak_defs')
local LEAN = DEFS.lean

-- Keyboard friendly lean keys are input actions, so they can be rebound with the built-in key binding settings
local leanActions = {
    { key = LEAN.leftAction, name = "Lean left", description = "Keyboard friendly mode only. Hold to lean left." },
    { key = LEAN.rightAction, name = "Lean right", description = "Keyboard friendly mode only. Hold to lean right." },
}
for _, action in ipairs(leanActions) do
    input.registerAction {
        key = action.key,
        type = input.ACTION_TYPE.Boolean,
        l10n = 'SneakIsGoodNow',
        name = action.name,
        description = action.description,
        defaultValue = false,
    }
end

-- Default keys, set once: a binding the player cleared is kept cleared (it's stored without a key)
local bindingSection = storage.playerSection('OMWInputBindings')
local function setDefaultBinding(id, actionKey, keyCode)
    if bindingSection:get(id) == nil then
        bindingSection:set(id, { device = 'keyboard', button = keyCode, type = 'action', key = actionKey })
    end
end
setDefaultBinding(LEAN.leftBinding, LEAN.leftAction, input.KEY.Z)
setDefaultBinding(LEAN.rightBinding, LEAN.rightAction, input.KEY.C)


-- Settings that moved to another group keep the value the player had set in the old one
local function moveSetting(key, fromGroup, toGroup)
    local from, to = storage.playerSection(fromGroup), storage.playerSection(toGroup)
    if to:get(key) == nil and from:get(key) ~= nil then
        to:set(key, from:get(key))
    end
end
moveSetting("WeaponBonus", 'SettingsSneakIsGoodNow', 'SettingsSneakIsGoodNowSkills')
moveSetting("MarkersAlpha", 'SettingsSneakIsGoodNow', 'SettingsSneakIsGoodNowUI')


I.Settings.registerPage {
    key = 'SneakIsGoodNowPage',
    l10n = 'SneakIsGoodNow',
    name = 'Sneak! Sneak Is Good Now.',
    description = "The mod is active. Go sneak now.",
}
I.Settings.registerGroup {
    key = 'SettingsSneakIsGoodNow',
    page = 'SneakIsGoodNowPage',
    l10n = 'SneakIsGoodNow',
    name = 'Detection',
    description = "How hard it is to stay unnoticed.",
    permanentStorage = true,
    order = 0,
    settings = {
        {
            key = "DifficultyMultiplier",
            renderer = "number",
            default = 1.0,
            argument = {
                min = 0.1,
                max = 5.0
            },
            name = "Difficulty multiplier",
            description = "Multiplies enemy attentiveness. Higher values make enemies more attentive."
        },
        {
            key = "ScaleAwarenessWithLevel",
            renderer = "checkbox",
            default = true,
            name = "Scale minimum awareness value with NPC/Creature level",
            description = "Most creatures have the same sneak skill from a rat to a Golden Saint, and NPCs without Sneak in " ..
                "their class keep 5-8 for life. When on, higher level creatures and NPCs notice you better. Those with " ..
                "a higher sneak of their own keep it."
        },
        {
            key = "KnockoutLosesTrack",
            renderer = "checkbox",
            default = false,
            name = "Knocked out enemies lose track of you",
            description = "Any enemy knocked out by exhaustion (fatigue below zero) stops noticing you. When off, " ..
                "only deep knockouts do, like the ones from Gothic Style Knockout."
        }
    },
}

I.Settings.registerGroup {
    key = 'SettingsSneakIsGoodNowSkills',
    page = 'SneakIsGoodNowPage',
    l10n = 'SneakIsGoodNow',
    name = 'Skills',
    permanentStorage = true,
    order = 1,
    settings = {
        {
            key = "WeaponBonus",
            renderer = "number",
            default = 0.5,
            argument = {
                min = 0,
                max = 1
            },
            name = "Weapon skill bonus while sneaking",
            description = "A percentile value (0.5 = 50%) that determines the bonus to weapon skill while sneaking."
        },
        {
            key = "SneakSkillGainMult",
            renderer = "number",
            default = 1,
            argument = {
                min = 0,
                max = 10
            },
            name = "Sneak skill gain multiplier",
            description = "Multiplies all sneak skill experience. Sneaking only trains the skill while a hostile NPC " ..
                "is in sight."
        }
    },
}

I.Settings.registerGroup {
    key = 'SettingsSneakIsGoodNowUI',
    page = 'SneakIsGoodNowPage',
    l10n = 'SneakIsGoodNow',
    name = 'Detection indicators',
    description = "How you see who is noticing you while sneaking. Markers and the reticle can be used together or on their own.",
    permanentStorage = true,
    order = 2,
    settings = {
        {
            key = "MarkersAlpha",
            renderer = "number",
            default = 1,
            argument = {
                min = 0,
                max = 1
            },
            name = "Marker opacity",
            description = "Opacity of the floating markers."
        },
        {
            key = "ShowMarkers",
            renderer = "checkbox",
            default = true,
            name = "Floating markers",
            description = "A marker over every NPC that can see you, filling up as they notice you."
        },
        {
            key = "MarkerStyle",
            renderer = "select",
            default = "Crescent",
            argument = {
                l10n = 'SneakIsGoodNow',
                items = { "Crescent", "Vanilla box" }
            },
            name = "Marker style",
            description = "Crescent: a glowing crescent filling up from the bottom. Vanilla box: a box with the game's " ..
                "menu border, filled by a rectangle growing from its center."
        },
        {
            key = "MarkerScale",
            renderer = "number",
            default = 1,
            argument = {
                min = 0.25,
                max = 3
            },
            name = "Marker size",
            description = "Scales the floating markers of both styles, and the arrows of off-screen ones."
        },
        {
            key = "MarkerPinWidth",
            renderer = "number",
            default = 0.75,
            argument = {
                min = 0.2,
                max = 1
            },
            name = "Off-screen marker area width",
            description = "Markers of NPCs outside your view are pinned to the edges of a centered area this wide, " ..
                "as a fraction of the screen width, with an arrow pointing where to turn. 0.75 is 4:3 on a 16:9 screen."
        },
        {
            key = "ShowAnimatedReticle",
            renderer = "checkbox",
            default = false,
            name = "Animated stealth reticle",
            description = "An eye that opens as you're being noticed, showing the most alert NPC around. " ..
                "From Stealth Overhaul 2 by Storm Atronach."
        },
        {
            key = "ReticleScale",
            renderer = "number",
            default = 0.75,
            argument = {
                min = 0.25,
                max = 2
            },
            name = "Reticle size",
            description = "1 is the eye's original size."
        },
        {
            key = "ReticleAlpha",
            renderer = "number",
            default = 1,
            argument = {
                min = 0,
                max = 1
            },
            name = "Reticle opacity"
        },
        {
            key = "ReticleColored",
            renderer = "checkbox",
            default = false,
            name = "Color the reticle",
            description = "Colors the reticle like the markers: yellow, turning red as you're about to be spotted, " ..
                "gray for NPCs that won't attack. Off keeps its original colors."
        },
        {
            key = "ReticleX",
            renderer = "number",
            default = 0.5,
            argument = {
                min = 0,
                max = 1
            },
            name = "Reticle horizontal position",
            description = "0 is the left edge of the screen, 1 the right edge."
        },
        {
            key = "ReticleY",
            renderer = "number",
            default = 0.5,
            argument = {
                min = 0,
                max = 1
            },
            name = "Reticle vertical position",
            description = "0 is the top edge of the screen, 1 the bottom edge."
        }
    },
}

I.Settings.registerGroup {
    key = 'SettingsSneakIsGoodNowLean',
    page = 'SneakIsGoodNowPage',
    l10n = 'SneakIsGoodNow',
    name = 'Leaning',
    description = "Lean around corners. Only your view moves, your body stays where it is, so leaning never makes you easier to spot.",
    permanentStorage = true,
    order = 4,
    settings = {
        {
            key = "LeanInputMode",
            renderer = "select",
            default = LEAN.controllerMode,
            argument = {
                l10n = 'SneakIsGoodNow',
                items = { LEAN.controllerMode, LEAN.keyboardMode }
            },
            name = "Lean controls",
            description = "Controller friendly: only while sneaking, hold the lean button chosen below and push left or right " ..
                "(the stick, or your strafe keys) to lean. You don't strafe while the lean button is held. " ..
                "Keyboard friendly: hold the lean keys below, at any time."
        },
        {
            key = "LeanControllerButton",
            renderer = "select",
            default = "Run",
            argument = {
                l10n = 'SneakIsGoodNow',
                items = { "Run", "Jump" }
            },
            name = "Lean button",
            description = "Controller friendly mode only. Run is your run button or walk/run toggle: running does nothing " ..
                "while sneaking, and a toggle pressed to lean doesn't switch your walk/run mode. Jump can't jump while sneaking."
        },
        {
            key = "LeanLeftKey",
            renderer = "inputBinding",
            default = LEAN.leftBinding,
            name = "Lean left",
            argument = {
                type = "action",
                key = LEAN.leftAction
            }
        },
        {
            key = "LeanRightKey",
            renderer = "inputBinding",
            default = LEAN.rightBinding,
            name = "Lean right",
            argument = {
                type = "action",
                key = LEAN.rightAction
            }
        },
        {
            key = "LeanAmount",
            renderer = "number",
            default = 25,
            argument = {
                min = 0,
                max = 100
            },
            name = "Lean amount",
            description = "How far your view leans out, in game units (about 1.4 cm each). The tilt grows with it."
        }
    },
}

return {
    settings = SettingsHelper:new('SettingsSneakIsGoodNow'),
    skillSettings = SettingsHelper:new('SettingsSneakIsGoodNowSkills'),
    uiSettings = SettingsHelper:new('SettingsSneakIsGoodNowUI'),
    leanSettings = SettingsHelper:new('SettingsSneakIsGoodNowLean')
}


