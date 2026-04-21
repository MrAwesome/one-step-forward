local _M = loadPrevious(...)

-- ToME 1.7.x uses Lua 5.1: no table.pack / table.unpack.
local function pack(...)
	local n = select("#", ...)
	local t = {}
	for i = 1, n do
		t[i] = select(i, ...)
	end
	t.n = n
	return t
end
local unpackn = unpack or table.unpack

-- Track "we are currently inside a non-silent T_ATTACK" as a depth counter on the
-- player. Counter > 0 across the full T_ATTACK action, including any alternate
-- attack it dispatches via forceUseTalent (Double Strike, warden-swap variants),
-- so the Combat superload can attribute the eventual attackTarget back to the
-- Attack the user pressed even when the talent that actually called attackTarget
-- is the alternate. Silent Attacks (autoattack, internal forceUseTalent uses)
-- never bump the counter, so they never set focus.
local base_useTalent = _M.useTalent
function _M:useTalent(id, who, force_level, ignore_cd, force_target, silent, no_confirm)
	local idv = type(id) == "table" and id.id or id
	local pushed = false
	if self.player and idv == self.T_ATTACK and not silent then
		self.__osf_attack_depth = (self.__osf_attack_depth or 0) + 1
		pushed = true
	end
	local res = pack(xpcall(function()
		return base_useTalent(self, id, who, force_level, ignore_cd, force_target, silent, no_confirm)
	end, debug.traceback))
	if pushed then
		self.__osf_attack_depth = self.__osf_attack_depth - 1
		if self.__osf_attack_depth <= 0 then self.__osf_attack_depth = nil end
	end
	if not res[1] then error(res[2]) end
	return unpackn(res, 2, res.n)
end

return _M
