long_name = "One Step Forward"
short_name = "one_step_forward"
for_module = "tome"
version = { 1, 7, 6 }
addon_version = { 1, 0, 0 }
weight = 50
author = { "Glenn" }
homepage = ""
description = [[Adds a single activated talent for the player: take exactly one step using the same targeting rules as auto-explore when no hostile is visible, or one step toward a chosen visible hostile when there is one.

Future-friendly: enemy selection and optional safety checks are isolated in data/api.lua so you can add a conditional variant later without rewriting the core.]]
tags = { "movement", "quality of life", "autoexplore" }

data = true
hooks = true
superload = true
