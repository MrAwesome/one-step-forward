-- hide=true on the talent type keeps the category out of LevelupDialog (it
-- iterates talents_types_def filtered by `not tt.hide`); hide on the talent
-- itself is the secondary guard for that same dialog. Use Talents ('m') and
-- the hotbar both ignore these flags for activated talents, which is exactly
-- the visibility we want.
newTalentType{
	type = "other/one-step-forward",
	name = "One Step Forward",
	description = "Single-step movement helpers.",
	generic = true,
	hide = true,
}

newTalent{
	short_name = "ONE_STEP_FORWARD",
	name = "One Step Forward",
	image = "one_step_forward+talents/one_step_forward.png",
	type = { "other/one-step-forward", 1 },
	points = 1,
	cooldown = 0,
	no_npc_use = true,
	no_energy = true,
	hide = true,
	on_pre_use = function(self, t, silent, fake)
		-- Mirror the conditions Actor:move and the action-loop check before any move:
		--   * Hard "cannot move" attrs (Actor.lua:1392, 1396, 1410): sleep (without
		--     lucid_dreamer), encased_in_ice / encased, never_move.
		--   * Hard "cannot act" attrs (Actor.lua act(): paralyzed, dont_act, time_prison).
		-- Anything we miss here is still caught later by canMove/bumpInto and the
		-- talent simply logs "There is nowhere to step." — but giving an explicit
		-- pre-use message keeps no_energy/cooldown=0 talents from being a silent no-op.
		local cant_move =
			self:attr("never_move")
			or self:attr("encased_in_ice")
			or self:attr("encased")
			or (self:attr("sleep") and not self:attr("lucid_dreamer"))
		local cant_act =
			self:attr("paralyzed")
			or self:attr("dont_act")
			or self:attr("time_prison")
		if cant_move or cant_act then
			if not silent then game.logPlayer(self, "You cannot use %s now.", t.name) end
			return false
		end
		return true
	end,
	action = function(self, t)
		local OSF = require "data-one_step_forward.api"
		if OSF.unconditional_step(self) then
			return true
		end
		game.logPlayer(self, "There is nowhere to step.")
		return false
	end,
	info = function(self, t)
		return _t[[Take one step.

With a visible hostile: step toward it (or bump-attack if adjacent).
Otherwise: step along the auto-explore path.

Configure under #YELLOW#Game Options → [One Step Forward]#LAST#.]]
	end,
}
