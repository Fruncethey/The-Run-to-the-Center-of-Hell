# The Run to the Center of Hell: momentum prototype

A custom momentum character controller for Roblox, plus a test level.

## What's in it

| Path | What it does |
|---|---|
| `src/shared/Momentum/Config.luau` | Every tuning number (speeds, gravity, slope factor, boost, camera). Start here when tweaking feel. |
| `src/shared/Momentum/Controller.luau` | The controller: own velocity, slope physics, ground snapping, surface alignment (walls, loops, ceilings), jump, roll, spin-dash, heat and boost. |
| `src/shared/Momentum/ChaseCamera.luau` | Chase camera that swings behind your direction of travel, pulls back and widens FOV with speed. |
| `src/shared/Momentum/Hud.luau` | Speedometer, heat meter, state readout, tutorial stage banner, run timer, checkpoint toast and completion screen. |
| `src/shared/Momentum/TutorialTracker.luau` | Tracks tutorial stage zones, checkpoints, run timer, peak speed and the finish gate. |
| `src/shared/Momentum/RunCycle.luau` | Procedural run cycle (R15 and R6) driven by speed: walk, run and sprint blend together, with idle and in-air poses. |
| `src/shared/Momentum/CharacterFx.luau` | Runs the run cycle (R6 falls back to default animations), spin-ball, boost trail, glow and afterimages. |
| `src/shared/Momentum/InputState.luau` | Keyboard and gamepad input. |
| `src/shared/Momentum/LockOn.luau` | Picks the enemy to lock onto in the air, draws the reticle, handles touching enemies (defeat or get hurt). |
| `src/server/EnemyService.server.luau` | Spawns Cinder Imps at every `EnemySpawn` marker, makes them hover and patrol, confirms defeats and respawns them. |
| `src/shared/Momentum/AshFx.luau` | Ash's live effects: the streaming scarf tail and his eye expressions. |
| `src/shared/Momentum/AshFace.luau` | Ash's orange circle eyes and their expressions. |
| `src/client/MomentumClient.client.luau` | Starts everything for the local player. |
| `src/server/AshBuilder.luau` + `AshCharacter.server.luau` | Builds Ash, the main character, and makes him everyone's `StarterCharacter`. |
| `src/server/PlayerSetup.server.luau` | Collision group for characters, turns off shift-lock (Shift is boost). |
| `src/server/LevelBuilder.luau` + `BuildTestLevel.server.luau` | Builds "Circle 0: The Descent Gate", a full 8-stage tutorial level on server start (skips if `Workspace.HellTestLevel` already exists). |
| `InstallInStudio.luau` | One-paste installer for the Studio Command Bar (no Rojo needed). |
| `tools/make_installer.py` | Regenerates `InstallInStudio.luau` from `src/` (`python3 tools/make_installer.py .`). |
| `default.project.json` | Rojo project. |

## Install

**Option A, Rojo.** Run `rojo serve` in this folder, then connect from the Rojo plugin in Studio.
Scripts go to `ReplicatedStorage.Momentum`, `ServerScriptService.MomentumServer` and
`StarterPlayer.StarterPlayerScripts.MomentumClient`.

**Option B, no tools.** Open a place (the Baseplate template is fine), open
View > Command Bar, paste all of `InstallInStudio.luau`, press Enter. Running it again replaces the scripts.

If your place already has a `Workspace.HellTestLevel` from an older version, delete it so the level is rebuilt
with the newest layout (including checkpoints, tutorial zones and enemy spawns) the next time you press Play.

Then press Play (F5). The level floats 200 studs up over a lava sea, so your old Baseplate is unaffected;
its spawn gets disabled so you start on the level's orange spawn pad.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | WASD / arrows | Left stick |
| Jump (hold for higher) | Space | A |
| Homing attack (when the red reticle is on an enemy) or air dash | Space in the air | A in the air |
| Stomp (slam straight down) | Q, Left Ctrl or C in the air | X or B in the air |
| Spin-dash (hold while slow, release to launch; tap jump to rev) / roll (hold while fast) | Q, Left Ctrl or C | X or B |
| Boost (needs heat) | Left Shift or E | R2 or Y |
| Look around | Hold right mouse and drag, wheel to zoom | Right stick |
| Respawn at checkpoint (or restart after finishing) | R | Select |

The heat meter fills while you go faster than 50 studs/s. Boost needs the bar past the white tick.

## Tutorial course ("Circle 0: The Descent Gate")

The tutorial is one long, twisting speed course (about 8,000 studs) over a lava sea. It runs through 8 stages with 7 checkpoints, contextual HUD stage prompts, a run timer and a finish gate. Along the way you get banked curves, rolling hills, long drops, two loops, a helix, a corkscrew and four optional branch routes that split off and merge back:

1. **Stage 1 · Run & Jump:** build speed on the runway, tap `Space` over the hurdles and the gap, then take the sweeping right-hander.
2. **Stage 2 · Roll & Momentum:** hold `Q` down the long drop, roll over four hills, or take the **High Ridge** branch above them. Banked S-curves follow.
3. **Stage 3 · Spin-Dash & Loop:** spin-dash into a narrow loop, then ride a guided helix spiralling down.
4. **Stage 4 · Air Dash:** jump off the ramp and Air Dash over the chasm to the island and the offset landing, or take the long **Low Bridge** around it.
5. **Stage 5 · Homing Chain:** home through the 4-imp chain up to the terrace, or run the winding **Climb** ramp.
6. **Stage 6 · Stomp & Descent:** stomp onto the 30° slope, then carry the speed through a twisting banked canyon.
7. **Stage 7 · Boost & Wall Run:** Boost through the gauntlet or ride the wall-run pipe, then pick a side at the **Fork** around a lava pillar.
8. **Finale:** Boost through the giant loop, keep your speed through the corkscrew, jump off the sky ramp and smash through **The Descent Gate** (press `R` after finishing to run it again).

Edge curbs line the curves and funnel you into the loops and the corkscrew. Missing a jump respawns you at your last checkpoint as soon as you've fallen 100 studs.

## How it works (short version)

- The Humanoid is put in the `Physics` state so it does nothing. Every frame, just before physics, the client
  simulates the character and writes the root CFrame and velocity. The client owns its character, so it replicates.
- Character parts are in a collision group that doesn't collide with the world; the controller does its own
  collision with a sphere cast (walls, ramps) and a ray cast down along the current surface normal (ground snapping).
- When grounded, "up" is the surface normal. Gravity is projected along the surface, which gives momentum on slopes
  and lets you lose speed going up loops and walls. Downhill pulls harder (`SlopeFactorDown` 1.1) than uphill holds
  you back (`SlopeFactor` 0.55), so slopes always pay out speed while loops need the same run-up as before. Below `MinWallSpeed` on a steep surface you peel off.
- Moving onto a new surface keeps your speed and redirects it along the surface, which is what makes loops and
  quarter pipes flow.
- Parts with the attribute `MomentumGuide = true` lock your direction to the part's LookVector. The loop uses this so
  its sideways offset carries you to the exit lane. Use it for corkscrews and later for grind rails.
- Input is read on flat ground relative to the camera, then tilted onto the surface you're on, so "forward" keeps
  meaning "keep going" on walls and upside down.

## Rolling vs running

Hold the roll button (Q) while moving faster than 20 to curl into a roll. It trades control for momentum:

| | Running | Rolling |
|---|---|---|
| Holding forward | Speeds you up to `TopSpeed` (90) | Does nothing: slopes are your engine |
| Above `TopSpeed` | Keeps it while going downhill; on flat ground sheds it back to 90 (`RunOverspeedDrag` 12/s) | Keeps it; friction is only 4/s |
| Downhill | Strong slope gain, about 180 speed at the bottom of the stage 2 drop | 1.6x that (`RollSlopeDown`), over 200 |
| Uphill | Normal slope loss | Half the loss (`RollSlopeUp`) |
| Steering | Full turn rate (above top speed it scales up so the turning circle stays the same) | About a third (`RollTurnFactor`) |
| Braking (hold back) | Strong (160/s) | Weak (30/s) |

You uncurl below 8 speed, or by jumping. Rolling also destroys enemies you hit.
Pressing roll in the air stomps, but only after 0.25 s in the air (`StompMinAirTime`), so cresting a small bump won't slam you down.

## Air movement and homing attack

- **Steering:** in the air your flight path bends toward the stick at `AirTurnRate`, so speed carries you instead of
  stopping on a dime. You can speed up to `TopSpeed`, holding back brakes, and extra speed above `TopSpeed` bleeds off slowly.
- **Air dash:** jump in the air with nothing locked on. Once per jump, reset on landing or on hitting an enemy.
- **Stomp:** roll button in the air. Slams straight down and defeats anything you land next to.
- **Lock-on:** while airborne, the closest enemy ahead of you (within `HomingRange`, inside a cone around your heading,
  in line of sight) gets a spinning red reticle.
- **Homing attack:** jump while locked. You fly at the target at `HomingSpeed`, and on contact it's destroyed and you
  pop up by `HomingBounce`, which is enough to lock and home onto the next one.
- **Touching enemies:** if you're curled up (jumped), rolling, boosting, stomping or homing, you destroy them. Otherwise
  you get knocked back and lose a quarter of your heat, then can't be hit for a moment.

Enemies are spawned by `EnemyService` at every part named `EnemySpawn` in the level (the level builder places nine).
Move the markers around in Studio, or give one a `Patrol` (Vector3) and `PatrolSpeed` attribute to make it drift.
Anything tagged `HomingTarget` can be locked onto, so later things like soul-chain grapple points can reuse it.

## Run cycle

`RunCycle.luau` poses the R15 (or R6) joints every frame instead of playing an uploaded animation, so the gait follows your exact speed:

| Speed | Look |
|---|---|
| Standing | Idle breathing |
| Up to 20 | Walk: short stride, relaxed arm swing, upright |
| 20 to 60 | Blends into a run: longer stride, high knee lift, pumping arms, forward lean, bounce |
| 100 to 150 and up | Sprint: deep lean, full stride, arms snapping forward and back |
| In the air | Arms out for balance, one knee tucked, a little flail when falling fast |

While running, the arms work cartoon style: one is thrust forward while the other is flung back, and they hold
those poses and snap across in time with the stride (`RunCycleArmSnap`). They also float a little away from the
shoulders, sliding toward where they point (`RunCycleArmDetach`, 0.04 studs).

At speed the whole body banks into turns like a bike, more the faster and tighter the turn
(`RunCycleBank`, capped at `RunCycleBankMax` = 0.48 radians).

Step rate scales linearly with speed (`RunCycleMinCadence` + speed * `RunCycleCadencePerSpeed`): about 0.9 cycles/s
at a walk (20), 2.5 at running top speed (90), 4.2 while boosting (170), and 7.5 at `MaxSpeed` (320), with only a high
anti-strobe ceiling (`RunCycleMaxCadence`, 12).

Above top speed (boosts, slopes) the same gait gets small extras so the pose keeps up, fully in by
`RunCycleOverdriveSpeed` (200): a 12% longer leg stride (`RunCycleOverdriveStride`) and a much deeper forward tilt
(`RunCycleOverdriveLean`). The arm motion never changes with it.

The torso tilts forward with speed: about 27 degrees at a full run (`RunCycleRunLean`), 38 degrees at 155 and
about 57 degrees by 200.
Tune it with the `RunCycle*` values in `Config.luau`.

Running and sprinting are cartoon-exaggerated by `RunCycleExaggeration` (1.05): bigger strides with high knees
(forward swing larger than the back swing), wider arm pumps, a deeper lean,
a bigger bounce on each footfall and a side-to-side hip rock. Walking stays natural. Set it to 1 for the
realistic gait, or around 2 for very rubbery legs.

## Ash, the main character

Everyone plays as Ash, built on the standard R6 rig to keep the art style simple. `AshBuilder` makes him on
server start (plain parts, no uploaded assets) and installs him as `StarterPlayer.StarterCharacter`. His look is
mostly color plus a few touches:

- Electric cyan body (`AshBodyColor` in `Config.luau`), the opposite of lava orange, so he stands out in every level.
- Two glowing orange circle eyes and no mouth (`AshFace.luau`). The eyes alone show his mood: round and blinking
  when idle, squashed and tilted inward when running, happy ^ ^ arcs above top speed or when boosting or homing,
  bigger when falling, and squeezed shut > < when he gets hit.
- A red scarf. The knot is part of the body; the tail is a small rope simulation that hangs at rest and
  streams and whips behind him at speed, splitting into two ragged ends.

The run cycle drives R6 too: the same gait, with the torso taking the lean and twist, and no knees or elbows.
Tune the scarf with the `Ash*` values in `Config.luau`, and his colors in `AshBuilder.luau`.
The scarf tail and changing expressions are drawn on your own screen only;
other players see his resting eyes.

## Afterimages

Above 140 speed (`AfterimageSpeed`) the character leaves glowing ghost copies behind it: one every 0.05 s, each
starting hot orange and cooling to red as it fades over 0.3 s. They get more solid as you approach 200
(`AfterimageFullSpeed`). Running tops out at 90, so you see them when boosting, spin-dashing, rolling down long slopes
or homing. While curled up, the spin-ball leaves the ghosts instead of the body. Tune them with the `Afterimage*`
values in `Config.luau`. Like the run cycle, they're drawn on your own screen only.

## Known limits

- The run cycle is drawn on your own screen only. Joint poses set by a script don't replicate, so in multiplayer
  other players would see you in a standing pose. The fix is to run the same run cycle for every character on
  each client, using their replicated velocity.

- Single-player feel only. Other players see your character move, but there's no server validation yet.
- Characters are collision-less with the world on the server, so server-side touch events against the character
  are the thing to watch when adding hazards or rings (use client-side checks or region queries).
- Ground snapping follows convex edges up to 60 degrees, so very sharp crests still stick at high speed.
