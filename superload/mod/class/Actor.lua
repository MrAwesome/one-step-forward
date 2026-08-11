local _M = loadPrevious(...)

-- One Step Forward is conceptually a movement command, not a talent cast. The
-- engine's "attacking or using any talent will break this effect" clause lives
-- in Actor.postUseTalent (game/modules/tome/class/Actor.lua ~line 6059) and is
-- gated on getCurrentTalentModeLast() ~= "forced". We run OSF's own
-- postUseTalent in forced mode so that break block is skipped for the step — a
-- movement-only OSF step no longer cancels Saw Wheels / Rocket Boots
-- / stealth-like effects.
--
-- This cannot be done by pushing "forced" around the useTalent call itself:
-- with "Confirm before stepping" enabled the engine's useTalent coroutine
-- yields for targeting and resumes asynchronously after confirmation, so a
-- mode push/pop paired with the useTalent call does not survive to
-- postUseTalent time. Pushing inside postUseTalent is synchronous and always
-- follows the eventual action.
--
-- The bump-attack OSF dispatches runs as its own useTalent(T_ATTACK)
-- (interface/Combat.lua bumpInto -> useTalent); its postUseTalent has
-- ab.id == T_ATTACK and therefore still runs the normal break block, so an
-- OSF bump-attack keeps breaking those sustains exactly like a real bump.
local base_postUseTalent = _M.postUseTalent
function _M:postUseTalent(ab, ret, silent)
	if ab and tostring(ab.id) == "T_ONE_STEP_FORWARD" then
		self:setCurrentTalentMode("forced", ab.id)
		local ok, data = xpcall(function()
			return {base_postUseTalent(self, ab, ret, silent)}
		end, debug.traceback)
		self:setCurrentTalentMode(nil)
		if not ok then error(data) end
		return data[1]
	end
	return base_postUseTalent(self, ab, ret, silent)
end

return _M