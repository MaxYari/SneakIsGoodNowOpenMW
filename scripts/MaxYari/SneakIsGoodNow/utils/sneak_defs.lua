local mod_name = "SneakIsGoodNow"
local prefix = mod_name .. "_"
local MtoGU = 69.99
local GUtoM = 1/MtoGU

local EYE_PRESET = {
    reticle = "Reticle",
    reticleDr = "Reticle + Dynamic Reticle",
    widget = "Widget above health bars",
    custom = "Custom",
}

return {
    MtoGU = MtoGU,
    GUtoM = GUtoM,
    mod_name = mod_name,
    KNOCKOUT_SPELL_ID = "detd_sleep",
    NPC_SETTINGS_KEY = "SettingsSneakIsGoodNowNPC",
    e = {
        ReportAttack = prefix.."ReportAttack"
    },
    -- The animated eye's presets, the items of its "EyePreset" setting, and what each one sets. position is where the
    -- eye goes ("center" or "bars", worked out by animated_eye.lua); the rest are settings of the eye's group
    eyePreset = EYE_PRESET,
    eyePresetValues = {
        [EYE_PRESET.reticle] = {
            position = "center", EyeSize = "Medium", EyeSizeMult = 1, EyeOnlyWhenNoticed = false, EyeHidesDynamicReticle = false,
        },
        [EYE_PRESET.reticleDr] = {
            position = "center", EyeSize = "Medium", EyeSizeMult = 1, EyeOnlyWhenNoticed = true, EyeHidesDynamicReticle = true,
        },
        [EYE_PRESET.widget] = {
            position = "bars", EyeSize = "Big", EyeSizeMult = 1, EyeOnlyWhenNoticed = true, EyeHidesDynamicReticle = false,
        },
    },
    lean = {
        controllerMode = "Controller friendly",
        keyboardMode = "Keyboard friendly",
    }
}