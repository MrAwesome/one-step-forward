long_name = "One Step Forward"
short_name = "one_step_forward"
for_module = "tome"
version = { 1, 7, 6 }
addon_version = { 1, 0, 2 }
weight = 100
author = { "Gleesus" }
homepage = "https://github.com/MrAwesome/one-step-forward"
description = [[
Gives every character a very simple (and very dangerous) talent: take exactly one step forward.

Meant to make life much easier when playing on a controller / Steam Deck / toaster.

If no hostiles are visible, will use the same targeting rules as auto-explore.

If hostiles are visible, will step towards the targeted hostile. If the targeted hostile is adjacent, they will be bump-attacked.

This means you will walk towards or attack either:
1) the hostile most recently explicitly targeted with this ability
2) the closest *or* most highly-ranked hostile (this is configurable in the options menu)
If multiple hostiles are adjacent, the bump prefers the one you most recently attacked, and otherwise uses a configurable tiebreak.

By default, steps will ask for confirmation, unless you enable "Automatic accept target" in your ToME settings (ctrl+shift+p by default) or disable "Confirm before stepping" in the addon options.

There are several other options available in the in-game Game Options menu under "[One Step Forward]".

Heavily inspired by the auto-attack system in Path of Achra (which was in turn heavily inspired by ToME).

''Please note: The author is a software engineer, but as an experiment this was '''heavily''' vibe-coded so do not be surprised if your game explodes.''
]]
tags = { "movement", "quality of life", "autoexplore" }

data = true
hooks = true
superload = true
