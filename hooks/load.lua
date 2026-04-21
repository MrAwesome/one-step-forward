-- Defer talent registration until ToME's data/talents.lua has patched
-- ActorTalents.newTalent to set t.display_entity (icon resolution). If we
-- registered the talent at hook-load time, the engine's bare newTalent would
-- run first and t.display_entity would be nil, crashing the hotbar drag UI in
-- HotkeysIconsDisplay.lua at t.display_entity:getEntityFinalSurface().
class:bindHook("ToME:load", function(self, data)
	local ActorTalents = require "engine.interface.ActorTalents"
	if ActorTalents.talents_def.T_ONE_STEP_FORWARD then return end
	ActorTalents:loadDefinition("/data-one_step_forward/talents.lua")
end)

-- ============================================================================
-- Settings + in-game options page
-- ============================================================================

local Dialog = require "engine.ui.Dialog"
local Textzone = require "engine.ui.Textzone"

-- Storage key: config.settings.tome.one_step_forward.{...}.
-- Saved in a single tome.one_step_forward serialized blob via saveSettings,
-- mirroring how ToME persists tome.fonts / tome.gfx (one nested table per call).
local OSF_DEFAULTS = {
	enemy_pick_mode = "closest",
	adjacent_enemy_pick_mode = "lowest_hp_remaining_absolute",
	move_around_weaker = false,
	block_step_on_empty_ammo = false,
	confirm_before_stepping = false,
}

local function ensure_settings()
	config.settings.tome = config.settings.tome or {}
	local s = config.settings.tome.one_step_forward
	if type(s) ~= "table" then
		s = {}
		config.settings.tome.one_step_forward = s
	end
	for k, v in pairs(OSF_DEFAULTS) do
		if s[k] == nil then s[k] = v end
	end
	return s
end

-- Serialize the whole nested table on every change (same approach as tome.fonts).
-- Strings are %q-quoted; booleans/nil pass through tostring. Keep this tight:
-- only the three keys we own, so an upgrade that adds a key never silently
-- writes a stale subset.
local function save_settings()
	local s = ensure_settings()
	local body = ("tome.one_step_forward = { enemy_pick_mode = %q, adjacent_enemy_pick_mode = %q, move_around_weaker = %s, block_step_on_empty_ammo = %s, confirm_before_stepping = %s }\n"):format(
		tostring(s.enemy_pick_mode),
		tostring(s.adjacent_enemy_pick_mode),
		tostring(s.move_around_weaker and true or false),
		tostring(s.block_step_on_empty_ammo and true or false),
		tostring(s.confirm_before_stepping and true or false)
	)
	game:saveSettings("tome.one_step_forward", body)
end

-- Initialize defaults at hook-load time so they exist before the player ever
-- opens the options dialog (and so api.lua sees them on the very first step).
ensure_settings()

local ENEMY_PICK_VALUES = {
	{ name = "Closest visible enemy", optval = "closest" },
	{ name = "Highest-rank visible enemy (ties: closest)", optval = "highest_rank" },
}

local ADJ_PICK_VALUES = {
	{ name = "Lowest remaining life (absolute)", optval = "lowest_hp_remaining_absolute" },
	{ name = "Lowest remaining life (fraction of max)", optval = "lowest_hp_remaining_percent" },
	{ name = "Highest rank", optval = "highest_rank" },
	{ name = "Lowest rank", optval = "lowest_rank" },
}

local function display_name(values, optval)
	for _, v in ipairs(values) do
		if v.optval == optval then return v.name end
	end
	return tostring(optval)
end

-- Add the [One Step Forward] tab. Guard with self.osf_tab_added so a re-open
-- of the GameOptions dialog (which re-fires this hook) doesn't add duplicates.
class:bindHook("GameOptions:tabs", function(self, data)
	if self.osf_tab_added then return end
	self.osf_tab_added = true
	data.tab("[One Step Forward]", function() self.list = { osf_options = true } end)
end)

class:bindHook("GameOptions:generateList", function(self, data)
	if not data.list.osf_options then return end
	local s = ensure_settings()
	local list = data.list

	local function add_enum(name, desc, settings_key, values)
		local zone = Textzone.new{ width = self.c_desc.w, height = self.c_desc.h, text = desc:toTString() }
		list[#list + 1] = {
			zone = zone,
			name = ("#GOLD##{bold}#%s#WHITE##{normal}#"):format(name):toTString(),
			status = function(item)
				return display_name(values, s[settings_key])
			end,
			fct = function(item)
				Dialog:listPopup(name, "Select value", values, 500, 200, function(sel)
					if not sel or not sel.optval then return end
					s[settings_key] = sel.optval
					save_settings()
					self.c_list:drawItem(item)
				end)
			end,
		}
	end

	local function add_bool(name, desc, settings_key)
		local zone = Textzone.new{ width = self.c_desc.w, height = self.c_desc.h, text = desc:toTString() }
		list[#list + 1] = {
			zone = zone,
			name = ("#GOLD##{bold}#%s#WHITE##{normal}#"):format(name):toTString(),
			status = function(item)
				return s[settings_key] and "enabled" or "disabled"
			end,
			fct = function(item)
				s[settings_key] = not s[settings_key]
				save_settings()
				self.c_list:drawItem(item)
			end,
		}
	end

	add_enum(
		"Approach target priority",
		"Which visible hostile the talent walks toward when several are in sight.\n\n"..
		"#YELLOW#Closest#LAST# — the nearest visible hostile (grid distance).\n"..
		"#YELLOW#Highest rank#LAST# — bosses/elites/rares first, ties broken by distance.",
		"enemy_pick_mode", ENEMY_PICK_VALUES)

	add_enum(
		"Adjacent bump tiebreak",
		"When you are already next to your approach target and several visible hostiles are adjacent, "..
		"and none of them is your last #YELLOW#Attack#LAST# target (melee focus), this picks which one you bump.\n\n"..
		"#YELLOW#Lowest remaining life (absolute)#LAST# — finish the weakest first; ties: higher rank, then closer.\n"..
		"#YELLOW#Lowest remaining life (fraction of max)#LAST# — finish the most-wounded first; same tie rules.\n"..
		"#YELLOW#Highest rank#LAST# — focus the strongest; ties: lower current life, then closer.\n"..
		"#YELLOW#Lowest rank#LAST# — clear trash first; ties: lower current life, then closer.",
		"adjacent_enemy_pick_mode", ADJ_PICK_VALUES)

	add_bool(
		"Avoid weaker hostiles when stepping",
		"Only takes effect when #YELLOW#Approach target priority#LAST# is set to #YELLOW#Highest rank#LAST#.\n\n"..
		"When enabled:\n"..
		"* Among several equally-short A* paths to your priority target, prefer a first step that keeps more distance from visible weaker hostiles.\n"..
		"* If no walkable A* route exists, try a single diagonal sidestep onto an empty tile that still reduces distance to the target.\n\n"..
		"When disabled, the talent always takes the first tile of any shortest path, and falls back to a direct bump if no path exists.",
		"move_around_weaker")

	add_bool(
		"Don't step with empty ammo",
		"When enabled, the talent refuses to take a step if the player has a ranged source equipped or learned and every such source is empty:\n\n"..
		"* #YELLOW#Archery weapon#LAST# (bow / sling / crossbow) — empty quiver, or quiver at 0 shots remaining (and no #YELLOW#infinite_ammo#LAST# attribute).\n"..
		"* #YELLOW#Throwing Knives talent#LAST# — no prepared knives.\n\n"..
		"Pure melee characters are never blocked. Use this if you don't want a missed step to silently rush you into melee when you meant to reload, swap weapons, or back off.",
		"block_step_on_empty_ammo")

	add_bool(
		"Confirm before stepping (targetable)",
		"When enabled, pressing the talent opens the standard targeting cursor on the tile it would step to (or the hostile it would bump) instead of moving immediately.\n\n"..
		"* #YELLOW#Enter#LAST# / #YELLOW#Space#LAST# / left-click: commit.\n"..
		"* #YELLOW#Esc#LAST# / right-click: cancel without spending a turn.\n"..
		"* Move the cursor to a different #YELLOW#adjacent#LAST# tile before confirming to redirect the step or bump.\n\n"..
		"Respects ToME's #YELLOW#Automatically accept target#LAST# option: with that enabled the first press commits immediately with no prompt, exactly like other targeted talents (Rush, Shoot, etc.).",
		"confirm_before_stepping")
end)
