-- Core logic for One Step Forward. Kept separate from talent definitions so
-- future "conditional step" talents can reuse the same primitives.

local Astar = require "engine.Astar"
local Dialog = require "engine.ui.Dialog"
local Map = require "engine.Map"

local M = {}

--- Hard-coded fallback defaults. The live values read from
--- config.settings.tome.one_step_forward (populated by mod/settings.lua and the
--- in-game options page added by hooks/load.lua); these are only used when the
--- settings table is missing (e.g. very early load, or a user wiping config).
M.defaults = {
	--- How to pick the hostile used for approach movement when several are visible.
	--- "closest"      — minimum grid distance (same notion as core.fov.distance).
	--- "highest_rank" — highest actor.rank, ties broken by distance.
	enemy_pick_mode = "closest",

	--- When more than one visible hostile is adjacent, which tile the bump-attack uses.
	--- "lowest_hp_remaining_absolute" | "lowest_hp_remaining_percent" | "highest_rank" | "lowest_rank".
	--- Tie-breaks: HP modes use higher rank then distance; rank modes use lower life then distance.
	adjacent_enemy_pick_mode = "lowest_hp_remaining_absolute",

	--- When true together with enemy_pick_mode = "highest_rank":
	--- * Among several shortest A* paths to your priority target, prefer a first step
	---   that keeps more distance from visible weaker hostiles (same path length only).
	--- * If there is no walkable A* route at all, try a single diagonal step onto an
	---   empty tile that still reduces distance to the priority target (a trivial
	---   sidestep). If none, fall back to a direct bump toward the target as before.
	move_around_weaker = false,

	--- Refuse to step when the player has a ranged source (archery weapon equipped or
	--- the Throwing Knives talent learned) and every such source is empty. Stops you
	--- from auto-bumping into melee when you really wanted to reload, swap weapons, or
	--- back off. Pure melee characters are never blocked.
	block_step_on_empty_ammo = false,

	--- When true, the first press of the talent only *highlights* the tile the talent
	--- would step to (or the hostile it would bump); a second press on the same turn
	--- commits. Any other action (which consumes a turn) silently drops the pending
	--- highlight, so the next press recomputes and highlights afresh.
	confirm_before_stepping = false,
}

--- Live settings view. Reads config.settings.tome.one_step_forward and falls
--- back to M.defaults per key. cfg (optional) overrides per-call. Boolean keys
--- need explicit nil checks since `false` is a valid stored value.
--- @param cfg table|nil
--- @param key string
--- @return any
function M.opt(cfg, key)
	if cfg ~= nil and cfg[key] ~= nil then return cfg[key] end
	local s = config and config.settings and config.settings.tome and config.settings.tome.one_step_forward
	if s ~= nil and s[key] ~= nil then return s[key] end
	return M.defaults[key]
end

--- Last hostile you attacked with the default Attack talent (bump-to-attack, Attack hotkey, OSF step),
--- including alternate attacks T_ATTACK dispatches (Double Strike, warden weapon-swap variants).
--- Internal forceUseTalent(..., silent=true) Attack uses do not count. Stored as osf_melee_focus_uid
--- (resolved via engine global __uids). Cleared when invalid or on game load.

--- @param actor mod.class.Player
function M.clear_melee_focus(actor)
	if actor and actor.player then actor.osf_melee_focus_uid = nil end
end

--- @param actor mod.class.Player
--- @param target Actor
function M.set_melee_focus(actor, target)
	if not actor or not target or target.dead or not actor.player then return end
	if actor:reactionToward(target) >= 0 then return end
	actor.osf_melee_focus_uid = target.uid
end

--- @param actor mod.class.Player
--- @return Actor|nil
function M.melee_focus_target(actor)
	if not actor or not actor.osf_melee_focus_uid or not game.level then return nil end
	local t = __uids[actor.osf_melee_focus_uid]
	if not t or t.dead or not game.level:hasEntity(t) then
		M.clear_melee_focus(actor)
		return nil
	end
	if actor:reactionToward(t) >= 0 then
		M.clear_melee_focus(actor)
		return nil
	end
	return t
end

--- @param actor mod.class.Player
--- @return table[] list of { x, y, actor, dist } (own tables; we never mutate spotHostiles' entries)
function M.visible_hostiles(actor)
	local raw = actor:spotHostiles(true)
	local out = {}
	for _, e in ipairs(raw) do
		out[#out + 1] = {
			x = e.x, y = e.y, actor = e.actor,
			dist = core.fov.distance(actor.x, actor.y, e.x, e.y),
		}
	end
	return out
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

local function actor_max_life(a)
	local m = a.max_life or a.maxLife or a.mhp
	if m and m > 0 then return m end
	local l = a.life or 0
	return math.max(l, 1)
end

--- @param entries table[] same shape as visible_hostiles entries
--- @return table|nil first entry after sorting by adjacent_enemy_pick_mode
local function pick_adjacent_hostile_entry(entries, cfg)
	if #entries == 0 then return nil end
	if #entries == 1 then return entries[1] end

	local mode = M.opt(cfg, "adjacent_enemy_pick_mode")

	local function rank_of(e)
		return e.actor.rank or 2
	end
	local function life_of(e)
		return e.actor.life or 0
	end

	if mode == "lowest_hp_remaining_absolute" then
		table.sort(entries, function(a, b)
			local la, lb = life_of(a), life_of(b)
			if la ~= lb then return la < lb end
			local ra, rb = rank_of(a), rank_of(b)
			if ra ~= rb then return ra > rb end
			return a.dist < b.dist
		end)
	elseif mode == "lowest_hp_remaining_percent" then
		table.sort(entries, function(a, b)
			local aa, ab = a.actor, b.actor
			local pa = life_of(a) / actor_max_life(aa)
			local pb = life_of(b) / actor_max_life(ab)
			if pa ~= pb then return pa < pb end
			local ra, rb = rank_of(a), rank_of(b)
			if ra ~= rb then return ra > rb end
			return a.dist < b.dist
		end)
	elseif mode == "lowest_rank" then
		table.sort(entries, function(a, b)
			local ra, rb = rank_of(a), rank_of(b)
			if ra ~= rb then return ra < rb end
			local la, lb = life_of(a), life_of(b)
			if la ~= lb then return la < lb end
			return a.dist < b.dist
		end)
	else
		-- "highest_rank" and unknown values: treat as highest_rank
		table.sort(entries, function(a, b)
			local ra, rb = rank_of(a), rank_of(b)
			if ra ~= rb then return ra > rb end
			local la, lb = life_of(a), life_of(b)
			if la ~= lb then return la < lb end
			return a.dist < b.dist
		end)
	end
	return entries[1]
end

--- Visible hostiles in a tile adjacent to the actor (for bump targeting).
--- @param actor mod.class.Player
--- @return table[] list of { x, y, actor, dist } (same as spotHostiles entries + dist)
local function adjacent_hostile_entries(actor)
	local out = {}
	for _, e in ipairs(M.visible_hostiles(actor)) do
		if cells_are_adjacent(actor.x, actor.y, e.x, e.y) then
			out[#out + 1] = e
		end
	end
	return out
end

local function pick_hostile(actor, cfg)
	local mode = M.opt(cfg, "enemy_pick_mode")
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

--- One sidestep onto an empty neighbor tile that still reduces distance to primary.
--- On square maps we restrict to diagonals (cardinals would just retread the failed A* approach).
--- On hex maps "diagonals" are not a meaningful concept, so we consider all hex neighbors.
--- Only used when A* finds no route and move_around_weaker + highest_rank are active.
local function trivial_diagonal_closer(actor, primary)
	local d0 = core.fov.distance(actor.x, actor.y, primary.x, primary.y)
	local bestx, besty, bestd1 = nil, nil, math.huge
	-- NOTE: util.isHex() returns a boolean. Earlier code compared it to 0, which is always
	-- false; on square maps that silently iterated over all 8 neighbors instead of diagonals.
	local coords
	if util.isHex() then
		coords = util.adjacentCoords(actor.x, actor.y)
	else
		coords = util.adjacentCoords(actor.x, actor.y, false, true) -- diagonals only
	end
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

--- One-tile step that respects bump-attack / door / talk semantics by going through
--- the engine's standard movement pipeline. attackOrMoveDir dispatches to Combat:bumpInto
--- for occupied tiles (hostile attack, friendly displace, NPC talk, closed door open).
--- Caller must guarantee (nx, ny) is a passable neighbor of the actor.
local function step_to(actor, nx, ny)
	local dir = util.getDir(nx, ny, actor.x, actor.y)
	if dir then
		actor:attackOrMoveDir(dir)
	else
		actor:move(nx, ny)
	end
end

--- Which adjacent hostile the talent would bump into if we were standing next to `primary` right now.
--- Pulled out of step_toward_hostile so the preview path can highlight the exact tile we will bump.
local function pick_bump_target(actor, primary, cfg)
	local bump_actor = primary
	local adj_entries = adjacent_hostile_entries(actor)
	local focus = M.melee_focus_target(actor)
	local focus_adj = nil
	if focus then
		for _, e in ipairs(adj_entries) do
			if e.actor == focus then
				focus_adj = focus
				break
			end
		end
	end
	if focus_adj then
		bump_actor = focus_adj
	elseif #adj_entries >= 2 then
		local pick = pick_adjacent_hostile_entry(adj_entries, cfg)
		if pick then bump_actor = pick.actor end
	end
	return bump_actor
end

--- Pure computation: where would unconditional_step go right now?
--- Returns { kind = "bump", x, y, bump_actor } for a bump (hostile at (x,y)),
---         { kind = "move", x, y } for a standard step,
--- or nil if there is nowhere to step.
--- Does not mutate game state (autoexplore_next_tile already guarantees that).
function M.compute_next_step(actor, cfg)
	cfg = cfg or {}
	if not game.level or not actor.x or not actor.y then return nil end

	local foe = pick_hostile(actor, cfg)
	if foe then
		local primary = foe.actor
		local tx, ty = primary.x, primary.y
		if cells_are_adjacent(actor.x, actor.y, tx, ty) then
			local bump = pick_bump_target(actor, primary, cfg)
			return { kind = "bump", x = bump.x, y = bump.y, bump_actor = bump }
		end

		local pick_mode = M.opt(cfg, "enemy_pick_mode")
		local maw = M.opt(cfg, "move_around_weaker")
		local avoid = maw and (pick_mode == "highest_rank")

		local nx, ny = M.astar_first_step_to_adjacent(actor, tx, ty, primary, { avoid_weaker = avoid })
		if nx and ny then return { kind = "move", x = nx, y = ny } end

		if avoid then
			local dx, dy = trivial_diagonal_closer(actor, primary)
			if dx then return { kind = "move", x = dx, y = dy } end
		end

		-- attackOrMoveDir fallback: step toward (tx,ty) even if no pathable route — the engine
		-- will either move one tile or bump whatever's blocking. Report the neighbor tile in that direction.
		local dir = util.getDir(tx, ty, actor.x, actor.y)
		if dir then
			local sx, sy = util.coordAddDir(actor.x, actor.y, dir)
			if sx and sy then return { kind = "move", x = sx, y = sy } end
		end
		return nil
	end

	local nx, ny = M.autoexplore_next_tile(actor)
	if nx and ny then return { kind = "move", x = nx, y = ny } end
	return nil
end

--- Execute a previously-computed step. Must be called in the same logical game state the plan was
--- computed in (same turn, same positions). The caller is expected to re-validate freshness before use.
local function apply_step_plan(actor, plan)
	if plan.kind == "bump" and plan.bump_actor then
		actor:bumpInto(plan.bump_actor, plan.bump_actor.x, plan.bump_actor.y)
		return true
	end
	step_to(actor, plan.x, plan.y)
	return true
end

local function step_toward_hostile(actor, foe_entry, cfg)
	local primary = foe_entry.actor
	local tx, ty = primary.x, primary.y

	-- Already beside this foe: bump-attack, do not pathfind to another flank tile (avoids orbiting).
	if cells_are_adjacent(actor.x, actor.y, tx, ty) then
		local bump_actor = pick_bump_target(actor, primary, cfg)
		-- bumpInto goes straight to the canonical attack/displace/talk path. We use it
		-- instead of attackOrMoveDir(util.getDir(...)) because hex neighbors don't all
		-- correspond cleanly to the 8-direction codes attackOrMoveDir consumes, and
		-- bumpInto already handles bump_attack_disabled, energy gating, etc.
		actor:bumpInto(bump_actor, bump_actor.x, bump_actor.y)
		return true
	end

	local pick_mode = M.opt(cfg, "enemy_pick_mode")
	local maw = M.opt(cfg, "move_around_weaker")
	local avoid = maw and (pick_mode == "highest_rank")

	local nx, ny = M.astar_first_step_to_adjacent(actor, tx, ty, primary, { avoid_weaker = avoid })
	if nx and ny then
		step_to(actor, nx, ny)
		return true
	end

	if avoid then
		local dx, dy = trivial_diagonal_closer(actor, primary)
		if dx then
			step_to(actor, dx, dy)
			return true
		end
	end

	local dir = util.getDir(tx, ty, actor.x, actor.y)
	if dir then actor:attackOrMoveDir(dir) end
	return true
end

--- Next tile auto-explore would enter, without starting a run, showing dialogs,
--- or mutating game state. Implementation strategy:
---
--- We DRIVE Player:autoExplore through its "fresh run" branch (self.running == nil)
--- rather than the "update existing run" branch. The fresh branch is what real
--- player-initiated auto-explore uses, so its target/path selection matches what
--- the player would otherwise see if they tapped the auto-explore key.
---
--- The "update existing run" branch (taken when self.running.explore is set) adds
--- extra defensive filters that don't apply on a first step — e.g. line 2470 of
--- PlayerExplore.lua refuses any path whose first tile has terrain.notice = true,
--- which makes the talent silently bail out near escort portals, level changers,
--- and other "noticed" terrain that real auto-explore would happily walk into.
---
--- The fresh branch has its own side effects we have to neutralize for a peek:
---   * Dialog:simplePopup — registers a "Running..." popup. We intercept it.
---   * runStep()          — actually moves the player. We stub it.
---   * runStop()          — only triggered transitively if runStep is enabled, but
---                          stubbed defensively in case some inner path calls it.
---   * sets self.running and self.running_prev — restored at the end.
---
--- @return number|nil, number|nil
function M.autoexplore_next_tile(actor)
	local saved_running     = actor.running
	local saved_running_prev = actor.running_prev
	actor.running = nil

	-- rawget tells us whether the method was inherited (nil) vs an instance override.
	-- Restoring with rawset(nil) leaves inheritance intact in the common case.
	local saved_runStop = rawget(actor, "runStop")
	local saved_runStep = rawget(actor, "runStep")
	actor.runStop = function() return false end
	actor.runStep = function() return false end

	-- Patch Dialog.simplePopup at the class level. The fresh branch immediately
	-- sets dialog.__showup = nil and dialog.__hidden = true, so any table with
	-- writable fields satisfies it; we never want it actually registered.
	local saved_simplePopup = Dialog.simplePopup
	Dialog.simplePopup = function() return {} end

	-- Record-and-roll-back persistent map.attrs writes the fresh branch can make:
	--   autoexplore_ignore — flagged on adjacent special terrain or vault doors
	--   noticed            — marks terrain the player has "noticed" (escort portals,
	--                        level changers, etc.); persisting this would mutate
	--                        future auto-explore filtering
	--   obj_seen           — marks an unreachable object as seen
	-- Real auto-explore wants these writes to persist (the user "saw" the thing),
	-- but a passive peek must not silently mutate future auto-explore behavior.
	-- attrs is a table with __call = mapattrs(t, x, y, k, v); we swap its
	-- metatable for a recorder while leaving reads pass-through.
	local map = game.level.map
	local attrs_table = map.attrs
	local saved_meta = getmetatable(attrs_table)
	local mapattrs_orig = saved_meta.__call
	local touched = {}
	local recorder_meta = { __call = function(t, x, y, k, v)
		if v ~= nil and (k == "autoexplore_ignore" or k == "noticed" or k == "obj_seen") then
			touched[#touched + 1] = { x, y, k, mapattrs_orig(t, x, y, k) }
		end
		return mapattrs_orig(t, x, y, k, v)
	end }
	setmetatable(attrs_table, recorder_meta)

	local ok_call, err = pcall(actor.autoExplore, actor)

	-- Restore metatable only if our recorder is still on top. If another mod
	-- stacked its own metatable in between (rare), leave that alone rather than
	-- clobbering it; we'll just leak our recorder for this call.
	if getmetatable(attrs_table) == recorder_meta then
		setmetatable(attrs_table, saved_meta)
	end
	-- mapattrs treats v == nil as "read only"; to actually clear an attr we have
	-- to poke the underlying per-tile sub-table directly. T-Engine map.attrs is
	-- keyed by (x + y * map.w) with per-cell sub-tables; this layout has been
	-- stable across ToME 1.6/1.7. If a future engine version changes it, the
	-- type check below leaves the value in place rather than corrupting state.
	local w = map.w
	for _, e in ipairs(touched) do
		local x, y, k, prev = e[1], e[2], e[3], e[4]
		if prev == nil then
			local cell = attrs_table[x + y * w]
			if type(cell) == "table" then cell[k] = nil end
		else
			mapattrs_orig(attrs_table, x, y, k, prev)
		end
	end
	Dialog.simplePopup = saved_simplePopup
	rawset(actor, "runStop", saved_runStop)
	rawset(actor, "runStep", saved_runStep)

	local nx, ny
	if ok_call and actor.running and actor.running.path and actor.running.path[1] then
		nx, ny = actor.running.path[1].x, actor.running.path[1].y
	end
	actor.running = saved_running
	actor.running_prev = saved_running_prev
	if not ok_call then error(err) end
	return nx, ny
end

--- Inspect the player's ranged-attack stance.
--- @param actor mod.class.Player
--- @return table { has_archery, archery_empty, has_knives, knives_empty }
---   has_archery — an archery weapon (bow/sling/crossbow) is equipped with matching ammo slot
---                 (we don't require ammo to be present; an empty quiver still counts as "has archery")
---   archery_empty — true if has_archery and ammo is missing or shots_left <= 0
---   has_knives  — actor knows T_THROWING_KNIVES (their "ammo" is the prepared-knives effect)
---   knives_empty — true if has_knives and the EFF_THROWING_KNIVES effect is absent or stacks <= 0
local function ranged_status(actor)
	local out = { has_archery = false, archery_empty = false, has_knives = false, knives_empty = false }

	-- Archery: detect the weapon directly rather than calling actor:hasArcheryWeapon(),
	-- because hasArcheryWeapon already filters out the result when ammo is missing
	-- ("no ammo") which would make us misread an out-of-ammo bow as "no archery".
	local mh = actor.getInven and actor:getInven("MAINHAND")
	local main = mh and mh[1]
	if main and main.combat and main.archery_kind then
		out.has_archery = true
		local quiver = actor:getInven("QUIVER")
		local ammo = quiver and quiver[1]
		if not ammo or not (ammo.archery_ammo and ammo.combat) then
			out.archery_empty = true
		else
			-- infinite_ammo as either an actor attribute (e.g. EFF_BULLSEYE) or a
			-- per-ammo flag (e.g. some artifact quivers) bypasses shots_left entirely.
			local infinite = ammo.infinite or actor:attr("infinite_ammo")
			if not infinite and (ammo.combat.shots_left or 0) <= 0 then
				out.archery_empty = true
			end
		end
	end

	-- Throwing Knives: charges live on the EFF_THROWING_KNIVES effect (eff.stacks),
	-- regenerated automatically by the talent's per-turn callback. "Empty" means
	-- you have to wait at least one turn before throwing again.
	if actor.knowTalent and actor.T_THROWING_KNIVES and actor:knowTalent(actor.T_THROWING_KNIVES) then
		out.has_knives = true
		local eff = actor:hasEffect(actor.EFF_THROWING_KNIVES)
		if not eff or (eff.stacks or 0) <= 0 then
			out.knives_empty = true
		end
	end

	return out
end

--- True if the player has at least one ranged source and every present source is empty.
local function should_block_for_empty_ammo(actor)
	local r = ranged_status(actor)
	if not r.has_archery and not r.has_knives then return false end
	if r.has_archery and not r.archery_empty then return false end
	if r.has_knives and not r.knives_empty then return false end
	return true
end

--- Hand off to the engine's exclusive targeting mode so Enter/Space accept and Esc cancels,
--- exactly like any normal targeted talent. We bypass Actor:getTarget and game:targetGetForPlayer
--- because both are tangled with ToME's melee/immediate targeting (Player:getTarget rewrites
--- range=1 specs into an 8-direction arrow fan when immediate_melee_keys is on; targetGetForPlayer
--- adds autoaccept gating we already handle ourselves upstream). Instead we drive targetMode
--- directly: seed target.{x, y, entity} from the plan, enter "exclusive" keygrab mode, yield. The
--- engine's own targetmode_key bindings (Enter/Space = ACCEPT, Esc = EXIT, cursor moves, mouse)
--- resume our coroutine with either (x, y, entity) on confirm or (nil, nil, nil) on cancel.
--- @return number|nil, number|nil  confirmed (x, y), or nil, nil on cancel
local function confirm_plan_via_targeting(actor, plan)
	if not game.target then return plan.x, plan.y end  -- fallback: commit without prompt if no UI
	local co = coroutine.running()
	if not co then return plan.x, plan.y end  -- talent action always runs in a coroutine; guard for safety

	-- Seed the cursor on the plan tile. For bumps, use the hostile so the engine shows its tooltip
	-- naturally; for plain moves, point target.entity at whatever already occupies the tile (usually
	-- nothing, occasionally a friendly / item).
	local entity = (plan.kind == "bump" and plan.bump_actor) or game.level.map(plan.x, plan.y, Map.ACTOR)
	game.target.target.entity = entity
	game.target.target.x = plan.x
	game.target.target.y = plan.y

	-- "hit" type fills display_default_target + block_path etc. so Target:realDisplay has something to
	-- draw. range=1 constrains the cursor, nowarning skips "target yourself?" (irrelevant for a step),
	-- no_restrict skips canProject (we are not projecting a spell, we are previewing a step).
	local typ = {
		type = "hit",
		range = 1,
		nowarning = true,
		no_restrict = true,
		source_actor = actor,
		start_x = actor.x, start_y = actor.y,
		no_start_scan = true,          -- don't let the engine snap the cursor to a nearby enemy
		no_move_tooltip = true,
		talent = { name = "One Step Forward" },
	}

	-- targetMode("exclusive", msg, co, typ) stashes co in game.target_co, swaps key handlers, and
	-- returns immediately. coroutine.yield() parks the talent's action; when the player hits
	-- ACCEPT/EXIT/clicks/etc., GameTargeting:targetMode(false, ...) resumes co with the result.
	game:targetMode("exclusive", false, co, typ)
	local tx, ty = coroutine.yield()
	return tx, ty
end

--- One unconditional step: hostile approach if any visible hostiles, else auto-explore tile.
--- @param cfg table|nil optional per-call overrides {
---   enemy_pick_mode = "closest"|"highest_rank",
---   adjacent_enemy_pick_mode = "lowest_hp_remaining_absolute"|"lowest_hp_remaining_percent"|"highest_rank"|"lowest_rank",
---   move_around_weaker = boolean,
---   block_step_on_empty_ammo = boolean,
---   confirm_before_stepping = boolean,
--- }
--- Any unset key reads from config.settings.tome.one_step_forward, then M.defaults.
--- @return boolean true if a move, bump-attack, or highlight was made (i.e. the press did something)
function M.unconditional_step(actor, cfg)
	cfg = cfg or {}
	if not game.level or not actor.x or not actor.y then return false end

	if M.opt(cfg, "block_step_on_empty_ammo") and should_block_for_empty_ammo(actor) then
		game.logPlayer(actor, "#LIGHT_RED#Out of ammo: not stepping.#LAST#")
		return false
	end

	local confirm_mode = M.opt(cfg, "confirm_before_stepping") and actor.player
	if not confirm_mode then
		-- Fast path: compute + execute in one shot, identical to the pre-option behavior.
		local foe = pick_hostile(actor, cfg)
		if foe then return step_toward_hostile(actor, foe, cfg) end
		local nx, ny = M.autoexplore_next_tile(actor)
		if nx and ny then
			-- Route through the standard movement pipeline so closed doors get opened
			-- (bumpInto), items underfoot are picked up, etc., just like real auto-explore.
			step_to(actor, nx, ny)
			return true
		end
		return false
	end

	-- Confirm mode: show the engine's standard targeting cursor on the planned tile. Enter/Space
	-- accepts, Esc cancels, mouse click accepts, right-click cancels — all handled by the engine's
	-- targetmode keybindings. If ToME's auto_accept_target setting is on, skip the prompt entirely
	-- (matches how Rush, Shoot, etc. behave with that setting).
	local plan = M.compute_next_step(actor, cfg)
	if not plan then return false end

	if config and config.settings and config.settings.auto_accept_target then
		return apply_step_plan(actor, plan)
	end

	local tx, ty = confirm_plan_via_targeting(actor, plan)
	if not tx or not ty then return false end  -- Esc / right-click cancel

	-- Player accepted the plan tile as-is: commit via apply_step_plan so bumps go through the
	-- canonical bumpInto path (hex-safe, picks up melee focus / adjacent tiebreak rules).
	if tx == plan.x and ty == plan.y then
		if plan.kind == "bump" and plan.bump_actor and plan.bump_actor.dead then
			game.logPlayer(actor, "Target is gone.")
			return false
		end
		return apply_step_plan(actor, plan)
	end

	-- Player moved the cursor to a different tile before confirming. Treat as a directed step: must
	-- still be an adjacent walkable/bump-able neighbor (we gave the cursor range=1, but be defensive).
	if not cells_are_adjacent(actor.x, actor.y, tx, ty) then
		game.logPlayer(actor, "That tile is not adjacent.")
		return false
	end
	local victim = game.level.map(tx, ty, Map.ACTOR)
	if victim and actor:reactionToward(victim) < 0 then
		actor:bumpInto(victim, tx, ty)
		return true
	end
	if actor:canMove(tx, ty) then
		step_to(actor, tx, ty)
		return true
	end
	-- Door / friendly / odd terrain: let attackOrMoveDir sort it out.
	local dir = util.getDir(tx, ty, actor.x, actor.y)
	if dir then
		actor:attackOrMoveDir(dir)
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
