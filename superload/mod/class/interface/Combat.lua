local _M = loadPrevious(...)

-- Capture the player's "last melee target" only on real, user-visible Attack uses.
--
-- Premise: the engine.interface.ActorTalents superload increments
-- self.__osf_attack_depth on entry to a non-silent T_ATTACK useTalent call and
-- decrements it on exit. While that counter is > 0 we are somewhere inside an
-- Attack the user actually triggered (bump-to-attack, Attack hotkey, OSF step) —
-- including any alternate attack T_ATTACK dispatched via forceUseTalent
-- (T_DOUBLE_STRIKE, warden-swap blade/bow variants). We use depth rather than
-- inspecting __talent_running.id so that those alternates still attribute the
-- eventual attackTarget back to Attack instead of being silently ignored.
local base_attackTarget = _M.attackTarget
function _M:attackTarget(target, damtype, mult, noenergy, force_unarmed)
	if self.player and target and (self.__osf_attack_depth or 0) > 0
		and self:reactionToward(target) < 0 then
		local OSF = require "data-one_step_forward.api"
		OSF.set_melee_focus(self, target)
	end
	return base_attackTarget(self, target, damtype, mult, noenergy, force_unarmed)
end

return _M
