local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local input = require('openmw.input')
local ambient = require('openmw.ambient')
local storage = require('openmw.storage')
local I = require('openmw.interfaces')

-- Example:
-- {
-- 	key = "TAKE_ALL_KEY",
-- 	name = "Take All Key",
-- 	description = "",
-- 	renderer = "SuperKeybind2",
-- 	default = input.KEY.F,
-- 	argument = { -- NOTE: required, {} is enough, used to identify the setting between renders
-- 		default = input.KEY.F, -- default: nil
-- 		showResetButton = false, -- default: true
-- 		allowClear = false, -- default: true, Delete or Backspace unbinds
-- 		allowMouse = false, -- default: true, mouse buttons bind as negative numbers (left MB excluded)
-- 		allowController = false, -- default: true, gamepad buttons bind as 1000 + button id
-- 		width = 90, -- default: 100
-- 		textSize = 16, -- default: 16
-- 		disabled = false, -- default: false
-- 	},
-- },
--
-- stored values:
-- keyboard: positive keycode (1 to 999)
-- mouse: negative keycode (-1 to -inf)
-- gamepad: 1000 + button id (1000 and above)


-- ------------------------------ Renderer ------------------------------
local KEYBIND_RENDERER_ID = "SuperKeybind2"

-- session only install flags for other mods, "SuperKeybind2" = true, "SuperKeybind" = 2
local installedRenderers = storage.playerSection("InstalledSettingsRenderers")
installedRenderers:setLifeTime(storage.LIFE_TIME.GameSession)
installedRenderers:set(KEYBIND_RENDERER_ID, true)
local familyKey, familyVersion = KEYBIND_RENDERER_ID:match("^(.-)(%d+)$")
if (installedRenderers:get(familyKey) or 0) < tonumber(familyVersion) then
	installedRenderers:set(familyKey, tonumber(familyVersion))
end

local interfaceL10n = core.l10n('Interface')
local TextDefault = I.MWUI.templates.textNormal.props.textColor
local TextHighlight = I.MWUI.templates.textHeader.props.textColor

local mouseButtonNames = {
	[2] = "Middle",
	[3] = "Right",
}

local controllerButtonNames = {
	[input.CONTROLLER_BUTTON.A] = "Pad A",
	[input.CONTROLLER_BUTTON.B] = "Pad B",
	[input.CONTROLLER_BUTTON.X] = "Pad X",
	[input.CONTROLLER_BUTTON.Y] = "Pad Y",
	[input.CONTROLLER_BUTTON.Back] = "Pad Back",
	[input.CONTROLLER_BUTTON.Guide] = "Pad Guide",
	[input.CONTROLLER_BUTTON.Start] = "Pad Start",
	[input.CONTROLLER_BUTTON.LeftStick] = "Left Stick",
	[input.CONTROLLER_BUTTON.RightStick] = "Right Stick",
	[input.CONTROLLER_BUTTON.LeftShoulder] = "Pad LB",
	[input.CONTROLLER_BUTTON.RightShoulder] = "Pad RB",
	[input.CONTROLLER_BUTTON.DPadUp] = "D-pad Up",
	[input.CONTROLLER_BUTTON.DPadDown] = "D-pad Down",
	[input.CONTROLLER_BUTTON.DPadLeft] = "D-pad Left",
	[input.CONTROLLER_BUTTON.DPadRight] = "D-pad Right",
}

local listening = nil
local lastClearedTime = 0

local defaultArgument = {
	disabled = false,
	showResetButton = true,
	allowClear = true,
	allowMouse = true,
	allowController = true,
	width = 100,
	textSize = 16,
}

I.Settings.registerRenderer(KEYBIND_RENDERER_ID, function(value, set, argument)
	if not argument then
		error(KEYBIND_RENDERER_ID .. ": argument table is required")
	end
	value = tonumber(value)
	
	local opts = {}
	for k, v in pairs(defaultArgument) do
		opts[k] = v
	end
	for k, v in pairs(argument) do
		opts[k] = v
	end
	
	local isListening = listening ~= nil and listening.argument == argument
	
	local displayText
	if isListening then
		displayText = "press a key"
	elseif not value then
		displayText = interfaceL10n('None')
	elseif value >= 1000 then
		displayText = controllerButtonNames[value - 1000] or ("Pad " .. (value - 1000))
	elseif value < 0 then
		displayText = "Mouse " .. (mouseButtonNames[-value] or -value)
	else
		local keyName = input.getKeyName(value)
		if keyName == nil or keyName == "" then
			displayText = "Key " .. value
		else
			displayText = keyName
		end
	end
	
	local content = {}
	-- key display box
	table.insert(content, {
		template = I.MWUI.templates.box,
		content = ui.content {
			{
				template = I.MWUI.templates.textNormal,
				props = {
					text = displayText,
					textColor = isListening and TextHighlight or TextDefault,
					textSize = opts.textSize,
					textAlignH = ui.ALIGNMENT.Center,
					textAlignV = ui.ALIGNMENT.Center,
					autoSize = false,
					size = util.vector2(opts.width, opts.textSize + 4),
				},
			},
		},
		events = {
			mouseClick = async:callback(function()
				if lastClearedTime > core.getRealTime()-0.2 then return end
				if opts.disabled then return end
				ambient.playSound("menu click")
				listening = {
					argument = argument,
					set = set,
					value = value,
				}
				set(value) -- force re-render
			end),
		},
	})
	if opts.showResetButton then
		table.insert(content, { props = { size = util.vector2(4, 0) } })
		table.insert(content, {
			template = I.MWUI.templates.box,
			content = ui.content {
				{
					template = I.MWUI.templates.textNormal,
					props = {
						text = interfaceL10n('Reset'),
						textSize = opts.textSize,
						textAlignH = ui.ALIGNMENT.Center,
						textAlignV = ui.ALIGNMENT.Center,
						autoSize = false,
						size = util.vector2(opts.textSize * 3, opts.textSize + 4),
					},
				},
			},
			events = {
				mouseClick = async:callback(function()
					if opts.disabled then return end
					ambient.playSound("menu click")
					set(opts.default)
				end),
			},
		})
	end
	
	local layout = {
		type = ui.TYPE.Flex,
		props = {
			horizontal = true,
			arrange = ui.ALIGNMENT.Center,
		},
		content = ui.content(content),
	}
	if opts.disabled then
		return {
			template = I.MWUI.templates.disabled,
			content = ui.content { layout },
		}
	end
	return layout
end)

-- ------------------------------ Engine Handlers ------------------------------

local function onKeyPress(key)
	if not listening then return end
	local active = listening
	listening = nil
	if key.code == input.KEY.Escape then
		active.set(active.value)
		return
	end
	if active.argument.allowClear ~= false and (key.code == input.KEY.Backspace or key.code == input.KEY.Delete) then
		active.set(nil)
		return
	end
	active.set(key.code)
end

local function onMouseButtonPress(button)
	if not listening then return end
	if button == 1 then
		local active = listening
		listening = nil
		active.set(active.value)
		lastClearedTime = core.getRealTime()
		return
	end
	if listening.argument.allowMouse ~= false then
		local active = listening
		listening = nil
		active.set(-button)
	end
end

local function onControllerButtonPress(id)
	if not listening or id < 0 then return end
	local active = listening
	listening = nil
	if active.argument.allowController ~= false then
		active.set(1000 + id)
	else
		active.set(active.value)
	end
end

return {
	engineHandlers = {
		onKeyPress = onKeyPress,
		onMouseButtonPress = onMouseButtonPress,
		onControllerButtonPress = onControllerButtonPress,
	},
}
