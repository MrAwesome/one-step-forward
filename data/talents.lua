newTalentType{
	type = "other/one-step-forward",
	name = "One Step Forward",
	description = "Single-step movement helpers.",
	generic = true,
}

newTalent{
	short_name = "ONE_STEP_FORWARD",
	name = "One Step Forward",
	type = { "other/one-step-forward", 1 },
	points = 1,
	cooldown = 0,
	no_npc_use = true,
	no_energy = true,
	tactical = { CLOSEIN = 0.1, ESCAPE = 0.1 },
	on_pre_use = function(self, t, silent, fake)
		if self:attr("never_move") or self:attr("encased_in_ice") then
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
		local OSF = require "data-one_step_forward.api"
		local toward = OSF.enemy_pick_mode == "highest_rank" and _t"the highest-rank visible enemy" or _t"the closest visible enemy"
		return ([[Take exactly one step.

If you can see a hostile creature, you step along a shortest walkable path toward %s (grid pathfinding with the same movement checks as normal walking). If no route exists, you may try a trivial diagonal sidestep when that option is enabled, otherwise you bump straight toward the target.

Otherwise you step along the path auto-explore would use first—including unseen tiles, items, doors, and exits—without running ahead.

In #YELLOW#data/api.lua#LAST#: set #YELLOW#enemy_pick_mode#LAST# to #YELLOW#"highest_rank"#LAST# or #YELLOW#"closest"#LAST#. With #YELLOW#"highest_rank"#LAST#, set #YELLOW#move_around_weaker = true#LAST# to prefer sidesteps / equal-length paths that keep more distance from weaker visible enemies when possible.]]):tformat(toward)
	end,
}
