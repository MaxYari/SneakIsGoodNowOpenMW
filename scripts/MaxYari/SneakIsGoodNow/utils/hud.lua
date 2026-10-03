local ui = require("openmw.ui")

-- The HUD's size in UI units, which Lua UI positions and sizes are in: screen pixels divided by the UI scale.
-- ui.screenSize() and camera.worldToViewportVector() are in screen pixels instead.
local function size()
    local ok, hudSize = pcall(function() return ui.layers[ui.layers.indexOf('HUD')].size end)
    if ok and hudSize and hudSize.x > 0 and hudSize.y > 0 then return hudSize end
    return ui.screenSize()
end

return {
    size = size,
}
