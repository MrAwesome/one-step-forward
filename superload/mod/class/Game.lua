local _M = loadPrevious(...)

local base_loaded = _M.loaded
function _M:loaded()
	base_loaded(self)
	if self.player then
		local OSF = require "data-one_step_forward.api"
		OSF.grant_talent_if_missing(self.player)
	end
end

return _M
