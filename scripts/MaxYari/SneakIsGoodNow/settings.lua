local mp = "scripts/MaxYari/SneakIsGoodNow/"

local I = require('openmw.interfaces')
local input = require('openmw.input')

local SettingsHelper = require(mp .. "utils/settings_helper")


I.Settings.registerPage {
    key = 'SneakIsGoodNowPage',
    l10n = 'SneakIsGoodNow',
    name = 'Sneak! Sneak Is Good Now.',
    description = "The mod is active. Go sneak now.",
}
I.Settings.registerGroup {
    key = 'SneakIsGoodNowSettings',
    page = 'SneakIsGoodNowPage',
    l10n = 'SneakIsGoodNow',
    name = 'Settings',    
    permanentStorage = true,
    settings = {
        {
            key = "MarkersAlpha",
            renderer = "number",
            default = 1,
            argument = {
                min = 0,
                max = 1
            },
            name = "Detection marker opacity"
        }
    },
}

return {
    settings = SettingsHelper:new('SneakIsGoodNowSettings')
}


