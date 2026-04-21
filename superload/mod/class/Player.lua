local _M = loadPrevious(...)

-- Transient runtime state we never want to serialize:
--   osf_melee_focus_uid  — last bump-attack target (uid; resolved via __uids).
--                          Cleared on load anyway, but keeping it out of the
--                          savefile means we can't accidentally restore a stale
--                          uid that now belongs to a different actor.
--   __osf_attack_depth   — non-nil only mid-useTalent; saves cannot happen while
--                          that coroutine is running, but we exclude defensively.
_M._no_save_fields = table.clone(_M._no_save_fields or {}, true)
_M._no_save_fields.osf_melee_focus_uid = true
_M._no_save_fields.__osf_attack_depth = true

local base_onBirth = _M.onBirth
function _M:onBirth(birther)
	base_onBirth(self, birther)
	local OSF = require "data-one_step_forward.api"
	OSF.grant_talent_if_missing(self)
end

return _M
