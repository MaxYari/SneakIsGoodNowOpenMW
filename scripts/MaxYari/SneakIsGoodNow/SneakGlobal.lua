local mp = "scripts/MaxYari/SneakIsGoodNow/"

local I = require('openmw.interfaces')

local DEFS = require(mp .. 'utils/sneak_defs')

-- NPC scripts can only read global storage, so their settings are registered here, from a global script,
-- onto the page the player script registers.
I.Settings.registerGroup {
    key = DEFS.NPC_SETTINGS_KEY,
    page = 'SneakIsGoodNowPage',
    l10n = 'SneakIsGoodNow',
    name = 'NPC behaviour',
    description = "For NPCs wandering around a small area indoors (a room, a cave), not those walking around towns.",
    permanentStorage = true,
    order = 3,
    settings = {
        {
            key = "MaxWanderTime",
            renderer = "number",
            default = 6,
            argument = {
                min = 0,
                max = 120
            },
            name = "Max wander time",
            description = "Seconds an NPC keeps walking before it stops to idle. 0 disables this."
        },
        {
            key = "IdleTimeMin",
            renderer = "number",
            default = 3,
            argument = {
                min = 0,
                max = 300
            },
            name = "Idle time min",
            description = "Shortest time in seconds an NPC stays idle once stopped."
        },
        {
            key = "IdleTimeMax",
            renderer = "number",
            default = 10,
            argument = {
                min = 0,
                max = 300
            },
            name = "Idle time max",
            description = "Longest time in seconds an NPC stays idle once stopped."
        }
    },
}

return {}
