local mp = "scripts/MaxYari/SneakIsGoodNow/"

local I = require('openmw.interfaces')
local core = require('openmw.core')
local input = require('openmw.input')

local SettingsHelper = require(mp .. "utils/settings_helper")
local DEFS = require(mp .. 'utils/sneak_defs')
local LEAN = DEFS.lean
local EYE_PRESET = DEFS.eyePreset

local hasDynamicReticle = core.contentFiles.has("DynamicReticle.omwscripts")

-- The eye's default preset: Reticle + Dynamic Reticle with Dynamic Reticle installed, Reticle without it
local EYE_DEFAULT_PRESET = hasDynamicReticle and EYE_PRESET.reticleDr or EYE_PRESET.reticle
local EYE_DEFAULTS = DEFS.eyePresetValues[EYE_DEFAULT_PRESET]

-- Some settings use ownlyme's Super Settings Renderers (https://www.nexusmods.com/morrowind/mods/59673), bundled in
-- SuperSettingsRenderers/ as menu scripts: SuperSlider6 for opacities and on-screen positions, SuperSelect3 for
-- picking from a list and SuperKeybind2 for the lean keys. Numbers that want precision (multipliers, sizes, times)
-- stay plain number fields, without an upper bound.

-- A SuperSlider6 argument. Every setting needs a table of its own, and the default again for the default mark.
local function slider(min, max, step, default, extra)
    local argument = { min = min, max = max, step = step, default = default, showDefaultMark = true, width = 150, thickness = 14 }
    for key, value in pairs(extra or {}) do argument[key] = value end
    return argument
end

-- Inline MyGUI color tags: the text after one is drawn in that color
local GREEN = "#7FC97F"
local YELLOW = "#E8C547"


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
            argument = { min = 0.1 },
            name = "Difficulty multiplier",
            description = "Multiplies enemy attentiveness. Higher values make enemies more attentive."
        },
        {
            key = "ScaleAwarenessWithLevel",
            renderer = "checkbox",
            default = true,
            name = "Scale minimum awareness value with NPC/Creature level",
            description = "In the original game most creatures have a very low attentiveness stat (very easy to sneak by). This setting ensures that higher level creatures and NPCs will become more attentive. It never reduces the attentiveness of NPCs that were already highly attentive in the original."
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
            argument = { min = 0 },
            name = "Weapon skill bonus while sneaking",
            description = "A percentile value (0.5 = 50%) that determines the bonus to weapon skill while sneaking."
        },
        {
            key = "SneakSkillGainMult",
            renderer = "number",
            default = 1,
            argument = { min = 0 },
            name = "Sneak skill gain multiplier",
            description = "Multiplies all sneak skill experience."
        }
    },
}

I.Settings.registerGroup {
    key = 'SettingsSneakIsGoodNowUI',
    page = 'SneakIsGoodNowPage',
    l10n = 'SneakIsGoodNow',
    name = 'Floating detection markers',
    permanentStorage = true,
    order = 2,
    settings = {
        {
            key = "ShowMarkers",
            renderer = "checkbox",
            default = true,
            name = "Floating markers",
            description = "A marker over every NPC that can see you, filling up as they notice you."
        },
        {
            key = "MarkerStyle",
            renderer = "SuperSelect3",
            default = "Crescent",
            -- In-game shots of each style, drawn 1:1 beside it and in its dropdown
            argument = {
                items = { "Crescent", "Vanilla bar" },
                width = 240,
                icon = {
                    ["Crescent"] = mp .. "textures/marker_style_crescent.png",
                    ["Vanilla bar"] = mp .. "textures/marker_style_vanilla_bar.png",
                },
                iconSize = 91,
            },
            name = "Marker style",
            description = "Crescent: an original Sneak! detection marker. Vanilla bar: a simplified detection bar"
        },
        {
            key = "MarkersAlpha",
            renderer = "SuperSlider6",
            default = 1,
            argument = slider(0, 1, 0.05, 1),
            name = "Marker opacity",
            description = "Opacity of the floating markers."
        },
        {
            key = "MarkerScale",
            renderer = "number",
            default = 1,
            argument = { min = 0.25 },
            name = "Marker size",
            description = "Scales the floating markers"
        },
        {
            key = "MarkerPinWidth",
            renderer = "SuperSlider6",
            default = 0.75,
            argument = slider(0.2, 1, 0.05, 0.75),
            name = "Off-screen marker area width",
            description = "Markers of NPCs outside your view are pinned to the edges of a centered area this wide, " ..
                "as a fraction of the screen width. 0.75 is roughly a 4:3 middle section on a 16:9 screen."
        }
    },
}

I.Settings.registerGroup {
    key = 'SettingsSneakIsGoodNowEye',
    page = 'SneakIsGoodNowPage',
    l10n = 'SneakIsGoodNow',
    name = 'Animated eye detection indicator',
    permanentStorage = true,
    order = 3,
    settings = {
        {
            key = "ShowEye",
            renderer = "SneakIsGoodNow_eyeToggle",
            default = true,
            name = "Animated eye",
            description = "A pretty animated eye icon that opens as you're being noticed. " ..
                "From Stealth Overhaul 2 by Storm Atronach."
        },
        {
            key = "EyeAlpha",
            renderer = "SuperSlider6",
            default = 1,
            argument = slider(0, 1, 0.05, 1),
            name = "Eye opacity"
        },
        {
            key = "EyeColored",
            renderer = "checkbox",
            default = false,
            name = "Color the eye",
            description = "Colors the eye like the markers: yellow, turning red as you're about to be spotted, " ..
                "gray for NPCs that won't attack. Off keeps the same color."
        },
        {
            key = "EyePreset",
            renderer = "SuperSelect3",
            default = EYE_DEFAULT_PRESET,
            argument = { items = { EYE_PRESET.reticle, EYE_PRESET.reticleDr, EYE_PRESET.widget, EYE_PRESET.custom }, width = 250 },
            name = "Animated eye indicator preset",
            description = "Reticle: a medium eye in place of the crosshair.\n" ..
                "Reticle + Dynamic Reticle: the same, but Dynamic Reticle's crosshair shows until someone starts noticing you.\n" ..
                "Widget above health bars: a big eye over the vanilla health bars, shown once someone starts noticing you.\n" ..
                "Changing any setting below switches to Custom."
        },
        {
            key = "EyeOnlyWhenNoticed",
            renderer = "checkbox",
            default = EYE_DEFAULTS.EyeOnlyWhenNoticed,
            name = "Hide when unnoticed",
            description = "Fades the eye out while detection is below 10%."
        },
        {
            key = "EyeHidesDynamicReticle",
            renderer = "checkbox",
            default = EYE_DEFAULTS.EyeHidesDynamicReticle,
            name = "Hide Dynamic Reticle's crosshair while the eye is out",
            description = "Fades out Dynamic Reticle's crosshair and its sneak arrows while the eye is shown. Works only " ..
                "with the 'Dynamic Reticle' mod installed.\n" ..
                (hasDynamicReticle and GREEN .. "Dynamic Reticle is installed."
                    or YELLOW .. "Dynamic Reticle isn't installed, so this does nothing.")
        },
        {
            key = "EyeSize",
            renderer = "SuperSelect3",
            default = EYE_DEFAULTS.EyeSize,
            argument = { items = { "Big", "Medium", "Small" }, width = 140 },
            name = "Eye size"
        },
        {
            key = "EyeSizeMult",
            renderer = "number",
            default = EYE_DEFAULTS.EyeSizeMult,
            argument = { min = 0.1 },
            name = "Eye size multiplier"
        },
        {
            key = "EyeX",
            renderer = "SuperSlider6",
            default = 0.5,
            argument = slider(0, 1, 0.01, 0.5, { minLabel = "Left", maxLabel = "Right" }),
            name = "Eye horizontal position"
        },
        {
            key = "EyeY",
            renderer = "SuperSlider6",
            default = 0.5,
            argument = slider(0, 1, 0.01, 0.5, { minLabel = "Top", maxLabel = "Bottom" }),
            name = "Eye vertical position"
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
    order = 5,
    settings = {
        {
            key = "LeanInputMode",
            renderer = "SuperSelect3",
            default = LEAN.controllerMode,
            argument = { items = { LEAN.controllerMode, LEAN.keyboardMode }, width = 200 },
            name = "Lean controls",
            description = "Controller friendly: only while sneaking, hold the lean button chosen below and push left or right " ..
                "(the stick, or your strafe keys) to lean. You don't strafe while the lean button is held. " ..
                "Keyboard friendly: assign and use dedicated lean keys."
        },
        {
            key = "LeanControllerButton",
            renderer = "SuperSelect3",
            default = "Run",
            argument = { items = { "Run", "Jump" }, width = 120 },
            name = "Lean button",
            description = "Controller friendly mode only. Run is your run button or walk/run toggle. Jump is your jump button, duh."
        },
        {
            key = "LeanKeyLeft",
            renderer = "SuperKeybind2",
            default = input.KEY.Z,
            argument = { default = input.KEY.Z, allowClear = false },
            name = "Lean left",
            description = "Keyboard friendly mode only. Hold to lean left."
        },
        {
            key = "LeanKeyRight",
            renderer = "SuperKeybind2",
            default = input.KEY.C,
            argument = { default = input.KEY.C, allowClear = false },
            name = "Lean right",
            description = "Keyboard friendly mode only. Hold to lean right."
        },
        {
            key = "LeanAmount",
            renderer = "number",
            default = 25,
            argument = { min = 0 },
            name = "Lean amount",
            description = "How far your view leans out, in game units (about 1.4 cm each). The tilt grows with it."
        }
    },
}

return {
    settings = SettingsHelper:new('SettingsSneakIsGoodNow'),
    skillSettings = SettingsHelper:new('SettingsSneakIsGoodNowSkills'),
    uiSettings = SettingsHelper:new('SettingsSneakIsGoodNowUI'),
    eyeSettings = SettingsHelper:new('SettingsSneakIsGoodNowEye'),
    leanSettings = SettingsHelper:new('SettingsSneakIsGoodNowLean')
}


