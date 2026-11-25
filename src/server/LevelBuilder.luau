-- Procedurally builds "Circle 0: The Descent Gate", a full 8-stage tutorial
-- course teaching every mechanic of the momentum controller in order:
--   1. Run & Jump        (acceleration, tap vs hold jump, forgiving gaps)
--   2. Roll & Momentum   (downhill drop, rolling 2x slope gain, hill, imps)
--   3. Spin-Dash & Loop  (charge & rev spin-dash, guided vertical loop)
--   4. Air Dash & Control(launch ramp over lava chasm, mid-air steering)
--   5. Homing Chain      (4-imp aerial chain climbing to a high terrace)
--   6. Stomp Dive        (mid-air stomp through an imp onto a 30-deg speed ramp)
--   7. Boost & Wall Run  (heat builder, boost imp gauntlet, curved wall-run pipe)
--   8. The Finale        (boost dip, giant loop, sky jump, and the Descent Gate)
--
-- Also places Checkpoints, TutorialZones, GoalGate, and invisible "EnemySpawn"
-- markers (filled by EnemyService). Floats over a lava sea; falling respawns
-- you at your latest checkpoint.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LevelBuilder = {}

local ORIGIN = Vector3.new(0, 200, 0)
local LEVEL_NAME = "HellTestLevel"

local COLOR = {
	rock = Color3.fromRGB(48, 28, 28),
	pillar = Color3.fromRGB(36, 22, 24),
	track = Color3.fromRGB(92, 42, 34),
	slope = Color3.fromRGB(122, 52, 36),
	loop = Color3.fromRGB(145, 32, 26),
	pipe = Color3.fromRGB(78, 34, 42),
	hurdle = Color3.fromRGB(72, 32, 32),
	trim = Color3.fromRGB(255, 110, 30),
	gold = Color3.fromRGB(255, 195, 80),
	lava = Color3.fromRGB(255, 85, 20),
}

local function W(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function newPart(parent: Instance, props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Basalt
	p.Color = COLOR.rock
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- A plank whose top surface runs from a to b. upHint says which side is "up".
local function plank(parent: Instance, a: Vector3, b: Vector3, upHint: Vector3, width: number, thickness: number, props)
	local f = b - a
	local len = f.Magnitude
	f = f.Unit
	local lateral = f:Cross(upHint).Unit
	local up = lateral:Cross(f).Unit
	local center = (a + b) / 2 - up * (thickness / 2)
	local p = newPart(parent, props or {})
	p.Size = Vector3.new(width, thickness, len + 0.6)
	p.CFrame = CFrame.fromMatrix(center, lateral, up, -f)
	return p
end

-- Run planks through a list of (x, y) points in the XY plane at depth z.
local function profile(parent: Instance, pts: { Vector2 }, z: number, width: number, thickness: number, props)
	for i = 1, #pts - 1 do
		local p0, p1 = pts[i], pts[i + 1]
		local d = (p1 - p0).Unit
		plank(parent, W(p0.X, p0.Y, z), W(p1.X, p1.Y, z), Vector3.new(-d.Y, d.X, 0), width, thickness, props)
	end
end

-- Points on a concave arc (a valley) around center (cx, cy), angles in degrees.
local function arc(pts: { Vector2 }, cx: number, cy: number, r: number, a0: number, a1: number, n: number)
	for i = 0, n do
		local a = math.rad(a0 + (a1 - a0) * i / n)
		table.insert(pts, Vector2.new(cx + r * math.sin(a), cy - r * math.cos(a)))
	end
end

-- Points on a convex arc (a crest / hill top) around center (cx, cy), angles in degrees.
-- At a = 0 the tangent is flat (+X); positive angles curve smoothly downward.
local function crestArc(pts: { Vector2 }, cx: number, cy: number, r: number, a0: number, a1: number, n: number)
	for i = 0, n do
		local a = math.rad(a0 + (a1 - a0) * i / n)
		table.insert(pts, Vector2.new(cx + r * math.sin(a), cy + r * math.cos(a)))
	end
end

local function strip(parent: Instance, from: Vector3, to: Vector3, width: number, color: Color3?)
	-- Glowing floor markings. CanQuery = false so the controller ignores them.
	local d = to - from
	if d.Magnitude < 0.05 then
		return
	end
	newPart(parent, {
		Name = "Marker",
		Size = Vector3.new(width, 0.2, d.Magnitude),
		CFrame = CFrame.lookAt((from + to) / 2 + Vector3.new(0, 0.1, 0), to + Vector3.new(0, 0.1, 0)),
		Material = Enum.Material.Neon,
		Color = color or COLOR.trim,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

-- Flat track deck with glowing side trim strips.
local function deck(parent: Instance, name: string, x0: number, x1: number, yTop: number, zCenter: number, width: number, thickness: number?)
	local th = thickness or 6
	local len = x1 - x0
	local part = newPart(parent, {
		Name = name,
		Size = Vector3.new(len, th, width),
		Position = W((x0 + x1) / 2, yTop - th / 2, zCenter),
		Color = COLOR.track,
	})
	local halfW = width / 2 - 0.8
	strip(parent, W(x0, yTop, zCenter - halfW), W(x1, yTop, zCenter - halfW), 0.8)
	strip(parent, W(x0, yTop, zCenter + halfW), W(x1, yTop, zCenter + halfW), 0.8)
	return part
end

-- Glowing neon chevron arrows pointing in +X along a flat surface.
local function chevrons(parent: Instance, xStart: number, yTop: number, zCenter: number, count: number, spacing: number, color: Color3?)
	local c = color or COLOR.gold
	for i = 0, count - 1 do
		local x = xStart + i * spacing
		strip(parent, W(x - 4, yTop, zCenter - 4.5), W(x + 2, yTop, zCenter), 1.0, c)
		strip(parent, W(x - 4, yTop, zCenter + 4.5), W(x + 2, yTop, zCenter), 1.0, c)
	end
end

-- Floating world sign (supplements the HUD tutorial banner).
local function sign(parent: Instance, position: Vector3, text: string)
	local post = newPart(parent, {
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(340, 62)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 360
	gui.LightInfluence = 0
	gui.Parent = post
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 210, 150)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
end

-- Invisible marker; EnemyService spawns an enemy here.
local function enemySpawn(parent: Instance, position: Vector3, patrol: Vector3?, patrolSpeed: number?)
	local marker = newPart(parent, {
		Name = "EnemySpawn",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2,
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	if patrol then
		marker:SetAttribute("Patrol", patrol)
	end
	if patrolSpeed then
		marker:SetAttribute("PatrolSpeed", patrolSpeed)
	end
	return marker
end

-- Invisible box volume for HUD tutorial stage prompts.
local function tutorialZone(
	parent: Instance,
	order: number,
	title: string,
	hint: string,
	x0: number,
	x1: number,
	yMin: number,
	yMax: number,
	zMin: number,
	zMax: number
)
	local zone = newPart(parent, {
		Name = string.format("Zone%d", order),
		Size = Vector3.new(x1 - x0, yMax - yMin, zMax - zMin),
		Position = W((x0 + x1) / 2, (yMin + yMax) / 2, (zMin + zMax) / 2),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	zone:SetAttribute("ZoneOrder", order)
	zone:SetAttribute("ZoneTitle", title)
	zone:SetAttribute("ZoneHint", hint)
	return zone
end

-- Glowing obsidian checkpoint arch; lights up cyan when crossed.
local function buildCheckpoint(parent: Instance, index: number, label: string, x: number, yFloor: number, zCenter: number, width: number)
	local folder = Instance.new("Folder")
	folder.Name = string.format("Checkpoint%d", index)
	folder:SetAttribute("CheckpointIndex", index)
	folder:SetAttribute("CheckpointLabel", label)
	folder.Parent = parent

	local halfW = width / 2 + 1
	local h = 22
	for _, side in { -1, 1 } do
		local pz = zCenter + side * halfW
		newPart(folder, {
			Name = "Pillar",
			Size = Vector3.new(3.5, h, 3.5),
			Position = W(x, yFloor + h / 2, pz),
			Color = COLOR.pillar,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		local accent = newPart(folder, {
			Name = "Beacon",
			Size = Vector3.new(4.1, h - 2, 1.2),
			Position = W(x, yFloor + h / 2, pz),
			Material = Enum.Material.Neon,
			Color = COLOR.trim,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		accent:SetAttribute("GlowAccent", true)
	end

	newPart(folder, {
		Name = "Crossbar",
		Size = Vector3.new(3.5, 3, width + 5.5),
		Position = W(x, yFloor + h + 1, zCenter),
		Color = COLOR.pillar,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local barGlow = newPart(folder, {
		Name = "ArchGlow",
		Size = Vector3.new(4.1, 1.1, width + 2),
		Position = W(x, yFloor + h - 0.5, zCenter),
		Material = Enum.Material.Neon,
		Color = COLOR.trim,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	barGlow:SetAttribute("GlowAccent", true)

	local triggerPos = W(x, yFloor + 16, zCenter)
	local trigger = newPart(folder, {
		Name = "Trigger",
		Size = Vector3.new(16, 36, width + 12),
		CFrame = CFrame.lookAt(triggerPos, triggerPos + Vector3.xAxis),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	trigger:SetAttribute("SpawnPosition", W(x, yFloor + 4, zCenter))
	return folder
end

-- Monumental finish gate at the end of the tutorial course.
local function buildGoalGate(parent: Instance, x: number, yFloor: number, zCenter: number, width: number)
	local folder = Instance.new("Folder")
	folder.Name = "GoalGate"
	folder.Parent = parent

	local halfW = width / 2
	local h = 44
	for _, side in { -1, 1 } do
		local pz = zCenter + side * halfW
		newPart(folder, {
			Name = "Monolith",
			Size = Vector3.new(8, h, 8),
			Position = W(x, yFloor + h / 2, pz),
			Color = COLOR.pillar,
		})
		-- Horn spire crowning each monolith
		newPart(folder, {
			Name = "Spire",
			Size = Vector3.new(5, 16, 5),
			CFrame = CFrame.new(W(x, yFloor + h + 6, pz + side * 2)) * CFrame.Angles(side * 0.25, 0, 0),
			Color = COLOR.rock,
		})
		local vein = newPart(folder, {
			Name = "Vein",
			Size = Vector3.new(8.6, h - 4, 2),
			Position = W(x, yFloor + h / 2, pz),
			Material = Enum.Material.Neon,
			Color = COLOR.trim,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		vein:SetAttribute("GlowAccent", true)
	end

	newPart(folder, {
		Name = "Crown",
		Size = Vector3.new(9, 7, width + 10),
		Position = W(x, yFloor + h + 1, zCenter),
		Color = COLOR.pillar,
	})
	local crownGlow = newPart(folder, {
		Name = "CrownGlow",
		Size = Vector3.new(9.6, 2.2, width + 4),
		Position = W(x, yFloor + h - 2.5, zCenter),
		Material = Enum.Material.Neon,
		Color = COLOR.trim,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	crownGlow:SetAttribute("GlowAccent", true)

	local curtain = newPart(folder, {
		Name = "PortalCurtain",
		Size = Vector3.new(1.2, h - 4, width - 6),
		Position = W(x, yFloor + (h - 4) / 2, zCenter),
		Material = Enum.Material.Neon,
		Color = COLOR.trim,
		Transparency = 0.68,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	curtain:SetAttribute("GlowAccent", true)

	local triggerPos = W(x + 2, yFloor + 55, zCenter)
	newPart(folder, {
		Name = "Trigger",
		Size = Vector3.new(28, 120, width + 24),
		CFrame = CFrame.lookAt(triggerPos, triggerPos + Vector3.xAxis),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	sign(folder, W(x - 10, yFloor + h + 12, zCenter), "THE DESCENT GATE — FINISH")
	return folder
end

local function buildLoop(
	parent: Instance,
	name: string,
	cx: number,
	yBase: number,
	radius: number,
	zStart: number,
	zEnd: number,
	segments: number,
	width: number
)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent

	local function point(theta: number): Vector3
		-- Ease the sideways shift in and out so you enter and leave the loop straight
		local s = theta / (2 * math.pi)
		local z = zStart + (zEnd - zStart) * (3 * s * s - 2 * s * s * s)
		return W(cx + radius * math.sin(theta), yBase + radius - radius * math.cos(theta), z)
	end

	for i = 0, segments - 1 do
		local t0 = 2 * math.pi * i / segments
		local t1 = 2 * math.pi * (i + 1) / segments
		local tm = (t0 + t1) / 2
		local inward = Vector3.new(-math.sin(tm), math.cos(tm), 0)
		local p = plank(folder, point(t0), point(t1), inward, width, 1.6, {
			Name = "LoopSegment",
			Color = if i % 2 == 0 then COLOR.loop else COLOR.track,
			Material = Enum.Material.Slate,
		})
		-- Guide parts lock your direction to the segment so the loop's sideways
		-- offset carries you to the exit lane.
		p:SetAttribute("MomentumGuide", true)
	end
end

-- Decorative volcanic monoliths rising out of the lava sea for depth & scale.
local function buildScenery(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	folder.Parent = parent

	local pillars = {
		{ 60, -52, 18, 220 },
		{ 140, 56, 22, 240 },
		{ 390, -60, 24, 250 },
		{ 520, 62, 20, 210 },
		{ 720, -64, 26, 230 },
		{ 940, 76, 24, 240 },
		{ 1140, -52, 22, 220 },
		{ 1290, 74, 26, 230 },
		{ 1540, -56, 24, 240 },
		{ 1650, 76, 22, 250 },
		{ 1870, -62, 26, 220 },
		{ 2040, 74, 24, 230 },
		{ 2260, 78, 28, 240 },
		{ 2520, -68, 24, 230 },
		{ 2740, 86, 26, 250 },
		{ 2940, -48, 22, 260 },
		{ 2960, 92, 22, 260 },
	}
	for i, spec in pillars do
		local x, z, size, h = spec[1], spec[2], spec[3], spec[4]
		local yBase = -110
		newPart(folder, {
			Name = "Spire" .. i,
			Size = Vector3.new(size, h, size),
			Position = W(x, yBase + h / 2, z),
			Color = COLOR.pillar,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		-- Glowing lava band near the base of every spire
		newPart(folder, {
			Name = "LavaRing" .. i,
			Size = Vector3.new(size + 1, 2.5, size + 1),
			Position = W(x, yBase + 18 + (i % 3) * 14, z),
			Material = Enum.Material.Neon,
			Color = COLOR.trim,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
	end
end

local function setupLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(110, 50, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 60, 45)
	Lighting.EnvironmentDiffuseScale = 0.3
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.34
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(255, 120, 70)
	atmosphere.Decay = Color3.fromRGB(110, 25, 15)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 2.0
	atmosphere.Parent = Lighting
	if not Lighting:FindFirstChild("HellBloom") then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "HellBloom"
		bloom.Intensity = 0.6
		bloom.Size = 30
		bloom.Threshold = 1.4
		bloom.Parent = Lighting
	end
end

function LevelBuilder.Build(): Folder
	local existing = Workspace:FindFirstChild(LEVEL_NAME)
	if existing then
		Workspace:SetAttribute("MomentumKillY", ORIGIN.Y - 90)
		return existing
	end

	local level = Instance.new("Folder")
	level.Name = LEVEL_NAME

	local zones = Instance.new("Folder")
	zones.Name = "TutorialZones"
	zones.Parent = level

	local checkpoints = Instance.new("Folder")
	checkpoints.Name = "Checkpoints"
	checkpoints.Parent = level

	local spawns = Instance.new("Folder")
	spawns.Name = "EnemySpawns"
	spawns.Parent = level

	-- Molten lava sea beneath the entire 3000+ stud course (two <=2048-stud tiles)
	for _, cx in { 520, 2568 } do
		newPart(level, {
			Name = "LavaSea",
			Size = Vector3.new(2048, 1, 1400),
			Position = W(cx, -108, 10),
			Material = Enum.Material.Neon,
			Color = COLOR.lava,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
	end

	-- =========================================================================
	-- STAGE 1: RUN & JUMP (X = -45..340, Y = 80, Z = 0)
	-- =========================================================================
	deck(level, "Stage1Runway", -45, 198, 80, 0, 36, 8)
	local spawnPos = W(-25, 80.5, 0)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MomentumSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.lookAt(spawnPos, spawnPos + Vector3.xAxis)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Neon
	spawn.Color = COLOR.trim
	spawn.Parent = level

	-- Decorative start gate arch
	for _, side in { -1, 1 } do
		newPart(level, {
			Name = "StartPillar",
			Size = Vector3.new(5, 28, 5),
			Position = W(5, 94, side * 19),
			Color = COLOR.pillar,
			CanCollide = false,
			CanQuery = false,
		})
	end
	newPart(level, {
		Name = "StartBeam",
		Size = Vector3.new(5, 4, 43),
		Position = W(5, 109, 0),
		Color = COLOR.pillar,
		CanCollide = false,
		CanQuery = false,
	})
	sign(level, W(5, 117, 0), "CIRCLE 0: THE DESCENT GATE")
	chevrons(level, 25, 80, 0, 3, 28)

	-- Low step hurdle (tap Space)
	newPart(level, {
		Name = "LowHurdle",
		Size = Vector3.new(6, 4.5, 36),
		Position = W(149, 82.25, 0),
		Color = COLOR.hurdle,
	})
	strip(level, W(146, 84.5, -17), W(146, 84.5, 17), 1.0, COLOR.gold)
	sign(level, W(149, 91, 0), "TAP SPACE TO HOP")

	-- Gap 1 (26 studs: X = 198..224) + Stage 1 landing deck
	deck(level, "Stage1Landing", 224, 340, 80, 0, 36, 8)

	-- Higher hurdle (hold Space for full jump height)
	newPart(level, {
		Name = "HighHurdle",
		Size = Vector3.new(6, 8.5, 36),
		Position = W(275, 84.25, 0),
		Color = COLOR.hurdle,
	})
	strip(level, W(272, 88.5, -17), W(272, 88.5, 17), 1.0, COLOR.gold)
	sign(level, W(275, 95, 0), "HOLD SPACE TO JUMP HIGHER")

	buildCheckpoint(checkpoints, 1, "ROLL & MOMENTUM", 324, 80, 0, 36)
	tutorialZone(
		zones,
		1,
		"STAGE 1 · RUN & JUMP",
		"Hold W to build speed. Tap Space for a short hop, hold Space to jump higher.",
		-60,
		324,
		50,
		150,
		-30,
		30
	)

	-- =========================================================================
	-- STAGE 2: ROLL & DOWNHILL MOMENTUM (X = 340..782, Y = 80 -> 0, Z = 0)
	-- =========================================================================
	local dropEndX: number
	do
		local slopeDeg = 24
		local slopeRad = math.rad(slopeDeg)
		local crestR = 22
		local botR = 36
		local pts = {}
		crestArc(pts, 340, 80 - crestR, crestR, 0, slopeDeg, 6)
		local crestEnd = pts[#pts]
		local botStartY = botR - botR * math.cos(slopeRad)
		local dxStraight = (crestEnd.Y - botStartY) / math.tan(slopeRad)
		local botCx = crestEnd.X + dxStraight + botR * math.sin(slopeRad)
		arc(pts, botCx, botR, botR, -slopeDeg, 0, 10)
		dropEndX = pts[#pts].X
		profile(level, pts, 0, 36, 4, { Name = "TutorialDrop", Color = COLOR.slope })
		sign(level, W(375, 84, 0), "HOLD Q DOWNHILL TO ROLL (2x SPEED)")
	end

	-- Valley runway with two patrolling imps to bowl right through
	deck(level, "Stage2Valley", dropEndX, 620, 0, 0, 36, 6)
	enemySpawn(spawns, W(570, 4, -5), Vector3.new(0, 0, 7), 1.2)
	enemySpawn(spawns, W(596, 4, 5), Vector3.new(0, 0, -7), 1.2)
	sign(level, W(582, 13, 0), "ROLL THROUGH IMPS TO SMASH THEM")

	-- Smooth momentum hill (16 deg up, rounded crest at Y = 20, 20 deg down)
	local hillEndX: number
	do
		local upDeg, downDeg = 16, 20
		local upRad, downRad = math.rad(upDeg), math.rad(downDeg)
		local botR, crestR, peakY = 28, 24, 20
		local pts = {}
		arc(pts, 620, botR, botR, 0, upDeg, 6)
		local upEnd = pts[#pts]
		local crestCy = peakY - crestR
		local crestStartY = crestCy + crestR * math.cos(upRad)
		local dxUp = (crestStartY - upEnd.Y) / math.tan(upRad)
		local crestCx = upEnd.X + dxUp + crestR * math.sin(upRad)
		crestArc(pts, crestCx, crestCy, crestR, -upDeg, downDeg, 8)
		local crestEnd = pts[#pts]
		local botDownStartY = botR - botR * math.cos(downRad)
		local dxDown = (crestEnd.Y - botDownStartY) / math.tan(downRad)
		local botDownCx = crestEnd.X + dxDown + botR * math.sin(downRad)
		arc(pts, botDownCx, botR, botR, -downDeg, 0, 6)
		hillEndX = pts[#pts].X
		profile(level, pts, 0, 36, 4, { Name = "MomentumHill", Color = COLOR.slope })
		newPart(level, {
			Name = "HillCore",
			Size = Vector3.new(44, peakY - 3, 35),
			Position = W(crestCx, (peakY - 3) / 2, 0),
			Color = COLOR.rock,
		})
	end

	-- Stage 3 floor begins right at hillEndX so there is zero seam
	deck(level, "Stage3Arena", hillEndX, 1070, 0, 8, 52, 6)
	buildCheckpoint(checkpoints, 2, "SPIN-DASH & LOOP", 782, 0, 0, 36)
	tutorialZone(
		zones,
		2,
		"STAGE 2 · ROLL & MOMENTUM",
		"Hold Q while moving downhill to curl into a ball. Rolling doubles downhill speed and smashes imps!",
		324,
		782,
		-20,
		130,
		-30,
		30
	)

	-- =========================================================================
	-- STAGE 3: SPIN-DASH & FIRST LOOP (X = 782..1070, Y = 0, Z = 0 -> 16)
	-- =========================================================================
	chevrons(level, 810, 0, 0, 3, 20, COLOR.gold)
	strip(level, W(868, 0, 0), W(933, 0, 0), 2.0, COLOR.trim)
	sign(level, W(835, 13, 0), "STOPPED? HOLD Q TO SPIN-DASH (TAP SPACE TO REV)")

	buildLoop(level, "TutorialLoop", 935, 0, 24, 0, 16, 48, 14)
	sign(level, W(935, 56, 8), "THE LOOP: 90+ SPEED OR SPIN-DASH")

	chevrons(level, 985, 0, 16, 2, 22, COLOR.gold)
	buildCheckpoint(checkpoints, 3, "AIR DASH", 1045, 0, 16, 36)
	tutorialZone(
		zones,
		3,
		"STAGE 3 · SPIN-DASH & LOOP",
		"Hold Q while slow to charge a Spin-Dash (tap Space to rev), then release to blast through the loop!",
		782,
		1045,
		-20,
		90,
		-26,
		42
	)

	-- =========================================================================
	-- STAGE 4: AIR DASH & AIR CONTROL (X = 1070..1465, Y = 0, Z = 16 -> 8)
	-- =========================================================================
	do
		local pts = {}
		arc(pts, 1070, 32, 32, 0, 22, 6)
		local last = pts[#pts]
		table.insert(pts, last + Vector2.new(math.cos(math.rad(22)), math.sin(math.rad(22))) * 24)
		profile(level, pts, 16, 30, 3, { Name = "AirDashRamp", Color = COLOR.slope })
		sign(level, W(1095, 22, 16), "JUMP + TAP SPACE MID-AIR TO AIR DASH")
	end

	-- 90-stud chasm -> Mid Island (X = 1194..1274, Z = 16)
	deck(level, "AirDashIsland", 1194, 1274, 0, 16, 34, 6)
	chevrons(level, 1216, 0, 16, 2, 24, COLOR.gold)

	-- 62-stud offset gap shifting from Z = 16 -> Z = 8 to practice air steering
	deck(level, "Stage4Arrival", 1336, 1465, 0, 8, 36, 6)
	sign(level, W(1305, 16, 12), "STEER LEFT IN MID-AIR + AIR DASH")
	strip(level, W(1456, 0, -9), W(1456, 0, 25), 1.8, COLOR.gold)

	buildCheckpoint(checkpoints, 4, "HOMING CHAIN", 1395, 0, 8, 36)
	tutorialZone(
		zones,
		4,
		"STAGE 4 · AIR DASH & STEERING",
		"Jump off the ramp and tap Space again in mid-air to Air Dash! Hold A/D in flight to steer.",
		1045,
		1395,
		-40,
		90,
		-20,
		44
	)

	-- =========================================================================
	-- STAGE 5: HOMING ATTACK CHAIN (X = 1395..1780, Y = 0 -> 20, Z = 8)
	-- =========================================================================
	enemySpawn(spawns, W(1495, 9, 8))
	enemySpawn(spawns, W(1533, 15, 8))
	enemySpawn(spawns, W(1571, 21, 8))
	enemySpawn(spawns, W(1609, 25, 8))
	sign(level, W(1495, 22, 8), "LOCK ON -> TAP SPACE TO HOMING ATTACK")

	deck(level, "HomingTerrace", 1638, 1780, 20, 8, 38, 6)
	chevrons(level, 1660, 20, 8, 2, 24, COLOR.gold)

	buildCheckpoint(checkpoints, 5, "STOMP DIVE", 1715, 20, 8, 38)
	tutorialZone(
		zones,
		5,
		"STAGE 5 · HOMING ATTACK",
		"Jump toward the Cinder Imps. When the red reticle locks on, tap Space to home in and chain across!",
		1395,
		1715,
		-30,
		90,
		-20,
		36
	)

	-- =========================================================================
	-- STAGE 6: STOMP DIVE & SLOPE LAUNCH (X = 1715..1975, Y = 20 -> -40, Z = 8)
	-- =========================================================================
	enemySpawn(spawns, W(1810, 6, 8))
	sign(level, W(1795, 30, 8), "JUMP OUT, THEN PRESS Q MID-AIR TO STOMP!")

	local stompEndX: number
	do
		local slopeDeg = 30
		local slopeRad = math.rad(slopeDeg)
		local botR = 32
		local botCy = -40 + botR
		local botStartY = botCy - botR * math.cos(slopeRad)
		local startX, startY = 1780, -2
		local dx = (startY - botStartY) / math.tan(slopeRad)
		local botCx = startX + dx + botR * math.sin(slopeRad)
		local pts = { Vector2.new(startX, startY) }
		arc(pts, botCx, botCy, botR, -slopeDeg, 0, 10)
		stompEndX = pts[#pts].X
		profile(level, pts, 8, 38, 4, { Name = "StompRamp", Color = COLOR.slope })
		-- Glowing target bar on the slope directly underneath the stomp imp
		local targetY = startY - (1810 - startX) * math.tan(slopeRad)
		strip(level, W(1810, targetY + 0.4, -7), W(1810, targetY + 0.4, 23), 2.5, COLOR.gold)
	end

	-- Valley floor out of the stomp ramp
	deck(level, "Stage6Exit", stompEndX, 1975, -40, 8, 48, 6)
	buildCheckpoint(checkpoints, 6, "BOOST & WALL RUN", 1945, -40, 8, 48)
	tutorialZone(
		zones,
		6,
		"STAGE 6 · STOMP",
		"Jump off the ledge and press Q in mid-air to STOMP straight down onto the ramp for an instant speed launch!",
		1715,
		1945,
		-60,
		70,
		-24,
		40
	)

	-- =========================================================================
	-- STAGE 7: HEAT, BOOST & WALL-RUN CANYON (X = 1975..2475, Y = -40, Z = 8)
	-- =========================================================================
	deck(level, "BoostCanyonFloor", 1975, 2475, -40, 8, 48, 6)
	chevrons(level, 2005, -40, 8, 5, 28, COLOR.gold)
	sign(level, W(2080, -25, 8), "HOLD SHIFT TO BOOST THROUGH IMPS (NEEDS HEAT)")

	-- Center boost gauntlet: plow straight through while boosting!
	enemySpawn(spawns, W(2175, -36, 8), Vector3.new(0, 0, 8), 1.1)
	enemySpawn(spawns, W(2235, -36, 8), Vector3.new(0, 0, -8), 1.1)
	enemySpawn(spawns, W(2295, -36, 8), Vector3.new(0, 0, 8), 1.1)

	-- Curved wall-run pipe seamlessly joined to the left edge (Z = -16) of the canyon floor
	do
		local x0, x1 = 2065, 2405
		local xm, len = (x0 + x1) / 2, x1 - x0
		local cz, cy, r = -16, -40 + 20, 20
		local function at(a: number): Vector3
			local rad = math.rad(a)
			return W(xm, cy - r * math.cos(rad), cz - r * math.sin(rad))
		end
		local n = 12
		for i = 0, n - 1 do
			local a0, a1 = 90 * i / n, 90 * (i + 1) / n
			local p0, p1 = at(a0), at(a1)
			local inward = (W(xm, cy, cz) - (p0 + p1) / 2).Unit
			plank(level, p0, p1, inward, len, 3, { Name = "WallRunCurve", Color = COLOR.pipe })
		end
		plank(level, at(90), W(xm, 40, cz - r), Vector3.zAxis, len, 3, { Name = "WallRunWall", Color = COLOR.pipe })
		strip(level, W(x0, -40, -13), W(x1, -40, -13), 1.0, COLOR.gold)
		sign(level, W(2120, -18, -22), "OR STEER LEFT TO WALL RUN!")
		enemySpawn(spawns, W(2195, -14, -29), Vector3.new(16, 0, 0), 0.7)
		enemySpawn(spawns, W(2305, -10, -29), Vector3.new(16, 0, 0), 0.7)
	end

	buildCheckpoint(checkpoints, 7, "THE FINALE", 2445, -40, 8, 48)
	tutorialZone(
		zones,
		7,
		"STAGE 7 · HEAT, BOOST & WALL RUN",
		"Run fast to fill HEAT past the white tick, then hold Shift to BOOST through imps — or steer left to Wall Run!",
		1945,
		2445,
		-60,
		60,
		-50,
		42
	)

	-- =========================================================================
	-- STAGE 8: THE FINALE — DIP, GIANT LOOP, SKY JUMP & DESCENT GATE
	-- (X = 2475..3025, Y = -40 -> -52 -> -40, Z = 8 -> 24)
	-- =========================================================================
	local dipEndX: number
	do
		local slopeDeg = 14
		local slopeRad = math.rad(slopeDeg)
		local crestR, botR = 24, 28
		local pts = {}
		crestArc(pts, 2475, -40 - crestR, crestR, 0, slopeDeg, 5)
		local crestEnd = pts[#pts]
		local botCy = -52 + botR
		local botStartY = botCy - botR * math.cos(slopeRad)
		local dx = (crestEnd.Y - botStartY) / math.tan(slopeRad)
		local botCx = crestEnd.X + dx + botR * math.sin(slopeRad)
		arc(pts, botCx, botCy, botR, -slopeDeg, 0, 6)
		dipEndX = pts[#pts].X
		profile(level, pts, 8, 48, 4, { Name = "FinaleDip", Color = COLOR.slope })
	end

	-- Giant Loop Arena Floor
	deck(level, "FinaleLoopFloor", dipEndX, 2735, -52, 16, 56, 6)
	chevrons(level, dipEndX + 10, -52, 8, 3, 20, COLOR.gold)
	strip(level, W(dipEndX + 20, -52, 8), W(2643, -52, 8), 2.2, COLOR.trim)
	buildLoop(level, "FinaleLoop", 2645, -52, 28, 8, 24, 52, 14)
	sign(level, W(2645, 16, 16), "BOOST THROUGH THE GIANT LOOP!")

	-- Finale Sky-Jump Ramp on exit lane (Z = 24)
	do
		local pts = {}
		arc(pts, 2735, -52 + 32, 32, 0, 25, 6)
		local last = pts[#pts]
		table.insert(pts, last + Vector2.new(math.cos(math.rad(25)), math.sin(math.rad(25))) * 22)
		profile(level, pts, 24, 32, 3, { Name = "FinaleLaunchRamp", Color = COLOR.slope })
	end

	-- Bonus celebratory aerial imps over the final lava gorge
	enemySpawn(spawns, W(2798, -28, 24))
	enemySpawn(spawns, W(2828, -26, 24))

	-- Victory Plaza & The Descent Gate
	deck(level, "VictoryPlaza", 2843, 3015, -40, 24, 60, 8)
	chevrons(level, 2858, -40, 24, 2, 22, COLOR.gold)
	buildGoalGate(level, 2910, -40, 24, 36)

	-- Backstop quarter pipe behind the gate so boosting through doesn't dump you into lava
	do
		local pts = {}
		arc(pts, 2995, -40 + 24, 24, 0, 90, 12)
		table.insert(pts, Vector2.new(3019, 90))
		profile(level, pts, 24, 60, 3, { Name = "VictoryQuarterPipe", Color = COLOR.pipe })
		newPart(level, {
			Name = "VictoryBackWall",
			Size = Vector3.new(24, 130, 60),
			Position = W(3033, 25, 24),
			Color = COLOR.rock,
		})
	end

	tutorialZone(
		zones,
		8,
		"FINALE · FULL THROTTLE",
		"Hit Shift to BOOST through the Giant Loop, soar off the ramp, and smash through the Descent Gate!",
		2445,
		3060,
		-70,
		110,
		-26,
		66
	)

	buildScenery(level)
	setupLighting()

	-- Turn off any other spawns (like the Baseplate template's) so you start here.
	for _, d in Workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and d ~= spawn then
			d.Enabled = false
		end
	end

	level.Parent = Workspace
	Workspace:SetAttribute("MomentumKillY", ORIGIN.Y - 90)
	return level
end

return LevelBuilder
