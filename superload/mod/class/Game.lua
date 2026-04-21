local _M = loadPrevious(...)

local base_loaded = _M.loaded
function _M:loaded()
	base_loaded(self)
	if self.player then
		local OSF = require "data-one_step_forward.api"
		-- Player.lua superload now lists osf_melee_focus_uid in _no_save_fields,
		-- so new saves never store it. We still clear here so saves made before
		-- that change come back clean (a stale uid could otherwise resolve to a
		-- different actor via __uids on this load).
		OSF.clear_melee_focus(self.player)
		OSF.clear_sticky_target(self.player)
		OSF.grant_talent_if_missing(self.player)
	end
end

return _M
