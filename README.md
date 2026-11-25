# The Run to the Center of Hell: momentum prototype

A custom momentum character controller for Roblox, plus a test level.

## What's in it

| Path | What it does |
|---|---|
| `src/shared/Momentum/Config.luau` | Every tuning number (speeds, gravity, slope factor, boost, camera). Start here when tweaking feel. |
| `src/shared/Momentum/Controller.luau` | The controller: own velocity, slope physics, ground snapping, surface alignment (walls, loops, ceilings), jump, roll, spin-dash, heat and boost. |
| `src/shared/Momentum/ChaseCamera.luau` | Chase camera that swings behind your direction of travel, pulls back and widens FOV with speed. |
| `src/shared/Momentum/Hud.luau` | Speedometer, heat meter, state readout, controls hint. |
| `src/shared/Momentum/RunCycle.luau` | Procedural run cycle driven by speed: walk, run and sprint blend together, with idle and in-air poses. |
| `src/shared/Momentum/CharacterFx.luau` | Runs the run cycle (R6 falls back to default animations), spin-ball, boost trail and glow. |
| `src/shared/Momentum/InputState.luau` | Keyboard and gamepad input. |
| `src/client/MomentumClient.client.luau` | Starts everything for the local player. |
| `src/server/PlayerSetup.server.luau` | Collision group for characters, turns off shift-lock (Shift is boost). |
| `src/server/LevelBuilder.luau` + `BuildTestLevel.server.luau` | Builds the test level on server start (skips it if `Workspace.HellTestLevel` already exists). |
| `InstallInStudio.luau` | One-paste installer for the Studio Command Bar (no Rojo needed). |
| `default.project.json` | Rojo project. |

## Install

**Option A, Rojo.** Run `rojo serve` in this folder, then connect from the Rojo plugin in Studio.
Scripts go to `ReplicatedStorage.Momentum`, `ServerScriptService.MomentumServer` and
`StarterPlayer.StarterPlayerScripts.MomentumClient`.

**Option B, no tools.** Open a place (the Baseplate template is fine), open
View > Command Bar, paste all of `InstallInStudio.luau`, press Enter. Running it again replaces the scripts.

Then press Play (F5). The level floats 200 studs up over a lava sea, so your old Baseplate is unaffected;
its spawn gets disabled so you start on the level's orange spawn pad.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | WASD / arrows | Left stick |
| Jump (hold for higher) | Space | A |
| Spin-dash (hold while slow, release to launch; tap jump to rev) / roll (hold while fast) | Q, Left Ctrl or C | X or B |
| Boost (needs heat) | Left Shift or E | R2 or Y |
| Look around | Hold right mouse and drag, wheel to zoom | Right stick |
| Respawn | R | Select |

The heat meter fills while you go faster than 50 studs/s. Boost needs the bar past the white tick.

## Test checklist

1. **The drop:** hold W from spawn. You should hit about 110 on the speedometer at the bottom.
2. **Hill:** you slow going up, speed back up coming down.
3. **Loop:** go in at 85+ and you run the full loop, coming out 16 studs to the right. Go in slow and you peel off the top and fall.
4. **Launch ramp:** right after the loop, sends you flying.
5. **Quarter pipe (end):** go vertical, run out of speed, fall back in and ride it back down. Boost up it to fly onto the ledge behind.
6. **Wall run:** after the drop, steer left (A briefly) toward the long curved wall on the left. The HUD says WALL RUN.
7. **Spin-dash:** stand still, hold Q for a second, release.
8. **Boost:** once the heat bar passes the tick, hold Shift.

## How it works (short version)

- The Humanoid is put in the `Physics` state so it does nothing. Every frame, just before physics, the client
  simulates the character and writes the root CFrame and velocity. The client owns its character, so it replicates.
- Character parts are in a collision group that doesn't collide with the world; the controller does its own
  collision with a sphere cast (walls, ramps) and a ray cast down along the current surface normal (ground snapping).
- When grounded, "up" is the surface normal. Gravity is projected along the surface (`SlopeFactor`), which gives
  momentum on slopes and lets you lose speed going up loops and walls. Below `MinWallSpeed` on a steep surface you peel off.
- Moving onto a new surface keeps your speed and redirects it along the surface, which is what makes loops and
  quarter pipes flow.
- Parts with the attribute `MomentumGuide = true` lock your direction to the part's LookVector. The loop uses this so
  its sideways offset carries you to the exit lane. Use it for corkscrews and later for grind rails.
- Input is read on flat ground relative to the camera, then tilted onto the surface you're on, so "forward" keeps
  meaning "keep going" on walls and upside down.

## Run cycle

`RunCycle.luau` poses the R15 joints every frame instead of playing an uploaded animation, so the gait follows your exact speed:

| Speed | Look |
|---|---|
| Standing | Idle breathing |
| Up to 20 | Walk: short stride, relaxed arm swing, upright |
| 20 to 60 | Blends into a run: longer stride, high knee lift, pumping arms, forward lean, bounce |
| 100 to 150 and up | Sprint: arms swept back, deep lean, full stride |
| In the air | Arms out for balance, one knee tucked, a little flail when falling fast |

Step rate climbs from 1.4 to 5 steps per second and levels off so the legs don't strobe at 300 speed.
Tune it with the `RunCycle*` values in `Config.luau`.

## Known limits

- The run cycle is drawn on your own screen only. Joint poses set by a script don't replicate, so in multiplayer
  other players would see you in a standing pose. The fix is to run the same run cycle for every character on
  each client, using their replicated velocity.

- Single-player feel only. Other players see your character move, but there's no server validation yet.
- Characters are collision-less with the world on the server, so server-side touch events against the character
  are the thing to watch when adding hazards or rings (use client-side checks or region queries).
- Ground snapping follows convex edges up to 60 degrees, so very sharp crests still stick at high speed.
