-- Core logic for One Step Forward. Kept separate from talent definitions so
-- future "conditional step" talents can reuse the same primitives.

local Astar = require "engine.Astar"

local M = {}

--- How to pick the hostile used for approach movement when several are visible.
--- "closest"     — minimum grid distance (same notion as core.fov.distance).
--- "highest_rank" — highest actor.rank, ties broken by distance.
M.enemy_pick_mode = "closest"

--- When #true# together with #YELLOW#enemy_pick_mode = "highest_rank"#LAST#:
--- * Among several shortest A* paths to your priority target, prefer a first step
---   that keeps more distance from visible weaker hostiles (same path length only).
--- * If there is no walkable A* route at all, try a single diagonal step onto an
---   empty tile that still reduces distance to the priority target (a trivial
---   sidestep). If none, fall back to a direct bump toward the target as before.
M.move_around_weaker = false

--- @param actor mod.class.Player
--- @return table[] list of { x, y, actor, dist }
function M.visible_hostiles(actor)
	local list = actor:spotHostiles(true)
	for _, e in ipairs(list) do
		e.dist = core.fov.distance(actor.x, actor.y, e.x, e.y)
	end
	return list
end

--- Visible hostiles strictly weaker than primary (by rank), excluding primary.
local function visible_weaker_than(actor, primary)
	local pr = primary.rank or 2
	local out = {}
	for _, e in ipairs(M.visible_hostiles(actor)) do
		local a = e.actor
		if a ~= primary and (a.rank or 2) < pr then
			out[#out + 1] = e
		end
	end
	return out
end

--- True if (x2,y2) is a passable neighbor of (x1,y1) on the current map topology (square or hex).
local function cells_are_adjacent(x1, y1, x2, y2)
	if x1 == x2 and y1 == y2 then return false end
	for _, c in pairs(util.adjacentCoords(x1, y1)) do
		if c[1] == x2 and c[2] == y2 then return true end
	end
	return false
end

local function pick_hostile(actor, cfg)
	local mode = (cfg and cfg.enemy_pick_mode) or M.enemy_pick_mode
	local list = M.visible_hostiles(actor)
	if #list == 0 then return nil end
	if mode == "highest_rank" then
		table.sort(list, function(a, b)
			local ra, rb = (a.actor.rank or 2), (b.actor.rank or 2)
			if ra ~= rb then return ra > rb end
			return a.dist < b.dist
		end)
	else
		table.sort(list, function(a, b) return a.dist < b.dist end)
	end
	return list[1]
end

--- Goals = empty, standable tiles adjacent to (tx, ty) (typically a hostile), excluding the actor's tile.
local function standing_goals_adjacent(actor, tx, ty)
	local goals = {}
	for _, c in pairs(util.adjacentCoords(tx, ty)) do
		local gx, gy = c[1], c[2]
		if game.level.map:isBound(gx, gy) and not (gx == actor.x and gy == actor.y) and actor:canMove(gx, gy) then
			goals[#goals + 1] = { gx, gy }
		end
	end
	return goals
end

--- First step on a shortest A* path (engine.Astar, same rules as AI / escort pathing) toward any goal.
--- @param primary Actor|nil optional priority foe for tie-breaking when opts.avoid_weaker is set
--- @param opts { avoid_weaker: boolean }
--- @return number|nil, number|nil
function M.astar_first_step_to_adjacent(actor, tx, ty, primary, opts)
	opts = opts or {}
	local goals = standing_goals_adjacent(actor, tx, ty)
	if #goals == 0 then return nil, nil end

	local forbid_diag = actor:attr("forbid_diagonals")
	local ast = Astar.new(game.level.map, actor)
	local add_check = function(x, y) return actor:canMove(x, y) end

	local best_len = math.huge
	local best_paths = {}
	for _, g in ipairs(goals) do
		local path = ast:calc(actor.x, actor.y, g[1], g[2], nil, nil, add_check, forbid_diag)
		if path and #path >= 1 then
			local len = #path
			if len < best_len then
				best_len = len
				best_paths = { path }
			elseif len == best_len then
				best_paths[#best_paths + 1] = path
			end
		end
	end

	if #best_paths == 0 then return nil, nil end

	if opts.avoid_weaker and primary and #best_paths > 1 then
		local weakers = visible_weaker_than(actor, primary)
		if #weakers > 0 then
			local best_sc, best_px, best_py = -1, nil, nil
			for _, p in ipairs(best_paths) do
				local nx, ny = p[1].x, p[1].y
				local mind = 999
				for _, w in ipairs(weakers) do
					mind = math.min(mind, core.fov.distance(nx, ny, w.x, w.y))
				end
				if mind > best_sc then
					best_sc, best_px, best_py = mind, nx, ny
				end
			end
			if best_px then return best_px, best_py end
		end
	end

	local p = best_paths[1]
	return p[1].x, p[1].y
end

--- One diagonal step onto an empty tile that still reduces distance to primary.
--- Only used when A* finds no route and move_around + highest_rank are active.
local function trivial_diagonal_closer(actor, primary)
	local d0 = core.fov.distance(actor.x, actor.y, primary.x, primary.y)
	local bestx, besty, bestd1 = nil, nil, math.huge
	local coords = util.isHex() == 0 and util.adjacentCoords(actor.x, actor.y, false, true) or util.adjacentCoords(actor.x, actor.y)
	for _, c in pairs(coords) do
		local ox, oy = c[1], c[2]
		if game.level.map:isBound(ox, oy) and actor:canMove(ox, oy) then
			local d1 = core.fov.distance(ox, oy, primary.x, primary.y)
			if d1 < d0 and d1 < bestd1 then
				bestd1, bestx, besty = d1, ox, oy
			end
		end
	end
	return bestx, besty
end

local function step_toward_hostile(actor, foe_entry, cfg)
	local primary = foe_entry.actor
	local tx, ty = primary.x, primary.y

	-- Already beside this foe: bump-attack them, do not pathfind to another flank tile (avoids orbiting).
	if cells_are_adjacent(actor.x, actor.y, tx, ty) then
		local dir = util.getDir(tx, ty, actor.x, actor.y)
		if dir then actor:attackOrMoveDir(dir) end
		return true
	end

	local pick_mode = (cfg and cfg.enemy_pick_mode) or M.enemy_pick_mode
	local maw = cfg and cfg.move_around_weaker
	if maw == nil then maw = M.move_around_weaker end
	local avoid = maw and (pick_mode == "highest_rank")

	local nx, ny = M.astar_first_step_to_adjacent(actor, tx, ty, primary, { avoid_weaker = avoid })
	if nx and ny then
		actor:move(nx, ny)
		return true
	end

	if avoid then
		local dx, dy = trivial_diagonal_closer(actor, primary)
		if dx then
			actor:move(dx, dy)
			return true
		end
	end

	local dir = util.getDir(tx, ty, actor.x, actor.y)
	if dir then actor:attackOrMoveDir(dir) end
	return true
end

--- Next tile auto-explore would enter, without starting a run or showing dialogs.
--- Relies on Player:autoExplore updating an existing self.running.explore path.
--- @return number|nil, number|nil
function M.autoexplore_next_tile(actor)
	local saved = actor.running
	local saved_prev = actor.running_prev
	local base = saved or {}
	actor.running = {
		explore = "unseen",
		path = { { x = actor.x, y = actor.y } },
		cnt = 1,
		levelstring = tostring(game.level),
		target = { x = actor.x, y = actor.y },
		ave_x = base.ave_x or actor.x,
		ave_y = base.ave_y or actor.y,
		ave_N = base.ave_N or 2,
	}
	local ok = actor:autoExplore()
	local nx, ny
	if ok and actor.running and actor.running.path and actor.running.path[1] then
		nx, ny = actor.running.path[1].x, actor.running.path[1].y
	end
	actor.running = saved
	actor.running_prev = saved_prev
	return nx, ny
end

--- One unconditional step: hostile approach if any visible hostiles, else auto-explore tile.
--- @param cfg table|nil optional {
---   enemy_pick_mode = "closest"|"highest_rank",
---   move_around_weaker = boolean|nil (nil = use module default M.move_around_weaker)
--- }
--- @return boolean true if a move (or bump-attack) was attempted
function M.unconditional_step(actor, cfg)
	cfg = cfg or {}
	if not game.level or not actor.x or not actor.y then return false end

	local foe = pick_hostile(actor, cfg)
	if foe then
		return step_toward_hostile(actor, foe, cfg)
	end

	local nx, ny = M.autoexplore_next_tile(actor)
	if nx and ny then
		actor:move(nx, ny)
		return true
	end
	return false
end

--- Learn the addon talent tree and level-1 talent if missing (idempotent).
function M.grant_talent_if_missing(actor)
	if not actor or not actor.player then return end
	local tid = actor.T_ONE_STEP_FORWARD or "T_ONE_STEP_FORWARD"
	if actor:knowTalent(tid) then return end
	actor:learnTalentType("other/one-step-forward", true)
	actor:learnTalent(tid, true, 1, { no_unlearn = true })
end

return M
