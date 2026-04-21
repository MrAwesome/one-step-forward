# One Step Forward

ToME 1.7 addon. Adds one talent: **One Step Forward**.

Press it to take exactly one step.

- No visible hostiles: step along the path auto-explore would take (items, doors, exits, unseen tiles).
- Visible hostiles: step along a shortest walkable path toward one of them, or bump-attack if already adjacent.

When already next to your target and more than one hostile is adjacent, the bump prefers the last hostile you attacked with the default Attack talent (bump-to-attack, Attack hotkey, or this talent). Other talents and ranged shots don't change that.

Costs no energy, no cooldown, can't be used by NPCs.

## Configuration

In-game: **Game Options → [One Step Forward]** tab.

- **Approach target priority** — `Closest` (default) or `Highest rank`.
- **Adjacent bump tiebreak** — used when no melee-focus target is adjacent: `Lowest remaining life (absolute)` (default), `Lowest remaining life (fraction)`, `Highest rank`, `Lowest rank`.
- **Avoid weaker hostiles when stepping** — with `Highest rank`, prefer equal-length paths and sidesteps that keep distance from weaker visible foes.
- **Don't step with empty ammo** — refuse to step when an equipped bow/sling/crossbow has no shots left (and `infinite_ammo` is off), or when the Throwing Knives talent is learned and no knives are prepared. Pure melee characters are never blocked.
- **Confirm before stepping (targetable)** — pressing the talent opens the standard targeting cursor. Enter/Space or left-click commits; Esc or right-click cancels. Directional keys behave like other targeted talents:
	- With visible hostiles, the cursor starts locked on the foe One Step Forward would approach, and arrows cycle (scan) between visible enemies. Confirming on any foe walks one step toward it (or bump-attacks if adjacent).
	- With no visible hostiles, the cursor sits on the planned step tile and arrows free-move it one tile. Confirm on any adjacent tile to redirect the step or bump.

	**Sticky target**: once you confirm a specific foe, One Step Forward remembers that choice across subsequent presses — keeping to that enemy until it dies, leaves sight, or you pick another. With **Highest rank** priority, the sticky also yields automatically if a higher-rank foe appears. With **Closest** priority, the sticky stays until you replace it manually.

	If ToME's **Automatically accept target** option is enabled, the step commits on the first press with no prompt, just like any other targeted talent (and the plan's priority foe becomes the sticky).

Settings persist per profile under `tome.one_step_forward` in your ToME config.

## Layout

- `data/api.lua` — pick/path/step primitives, reads live settings from `config.settings.tome.one_step_forward`.
- `data/talents.lua` — talent definition.
- `hooks/load.lua` — talent registration + in-game options page.
- `superload/` — minimal patches: grant the talent on birth/load, capture melee focus on real Attack uses, exclude transient state from saves.
