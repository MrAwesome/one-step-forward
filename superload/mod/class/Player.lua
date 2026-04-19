local _M = loadPrevious(...)

local base_onBirth = _M.onBirth
function _M:onBirth(birther)
	base_onBirth(self, birther)
	local OSF = require "data-one_step_forward.api"
	OSF.grant_talent_if_missing(self)
end

return _M
