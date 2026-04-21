# Agent Notes

Reference paths for this ToME rebalance addon project.

## Reference addons (extracted)

Path: `../te4-addons-reference/extracted`

Contains unpacked source of many existing ToME addons (Nekarcos QoL suite, ZOmnibus, Plenum Tooltip, Odyssey of the Summoner, etc.). Use as examples for:
- Addon directory layout (`init.lua`, `superload/`, `data/`, `hooks/`)
- `superload` patterns for overriding engine/game files
- Hook registration and event handling
- `init.lua` metadata format and `load.lua` structure

## Engine and game source

Path: `~/code/t-engine4` (absolute: `/home/glenn/code/t-engine4`)

Full T-Engine 4 + ToME source tree. Layout:
- `game/engines/default/` — base engine Lua
- `game/modules/tome/` — ToME module (classes, talents, data, damage types, combat, etc.)
- `src/` — C engine
- `documentation/` — engine docs

Consult when:
- Superloading a class/file — read the original to know existing methods/fields
- Balancing talents/damage — check formulas in `game/modules/tome/data/talents/`
- Checking combat/actor internals — `game/modules/tome/class/`

## Workflow tip

Before superloading, `rg` the target symbol in `~/code/t-engine4/game/modules/tome/` to find the canonical definition and avoid breaking upstream signatures.
