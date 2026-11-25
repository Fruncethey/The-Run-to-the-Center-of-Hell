-- Procedurally builds "Circle 0: The Test Pit", a small course for the momentum
-- controller: a starting drop, a hill, a loop, a launch ramp, a long wall-run
-- quarter pipe on the left, and a big quarter pipe at the end.
-- The level floats over a lava sea; falling in respawns you.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LevelBuilder = {}

local ORIGIN = Vector3.new(0, 200, 0)
local LEVEL_NAME = "HellTestLevel"

local COLOR = {
	rock = Color3.fromRGB(52, 30, 28),
	track = Color3.fromRGB(96, 44, 34),
	slope = Color3.fromRGB(120, 52, 36),
	loop = Color3.fromRGB(140, 30, 26),
	pipe = Color3.fromRGB(80, 36, 40),
	trim = Color3.fromRGB(255, 110, 30),
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
	local f = (b - a)
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
	gui.Size = UDim2.fromOffset(320, 60)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 400
	gui.LightInfluence = 0
	gui.Parent = post
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 200, 140)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
end

local function strip(parent: Instance, from: Vector3, to: Vector3, width: number)
	-- Glowing floor markings. CanQuery = false so the controller ignores them.
	local d = to - from
	newPart(parent, {
		Name = "Marker",
		Size = Vector3.new(width, 0.2, d.Magnitude),
		CFrame = CFrame.lookAt((from + to) / 2 + Vector3.new(0, 0.1, 0), to + Vector3.new(0, 0.1, 0)),
		Material = Enum.Material.Neon,
		Color = COLOR.trim,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

local function buildLoop(parent: Instance, cx: number, radius: number, zStart: number, zEnd: number)
	local segments = 48
	local width = 12
	local folder = Instance.new("Folder")
	folder.Name = "Loop"
	folder.Parent = parent

	local function point(theta: number): Vector3
		-- Ease the sideways shift in and out so you enter and leave the loop straight
		local s = theta / (2 * math.pi)
		local z = zStart + (zEnd - zStart) * (3 * s * s - 2 * s * s * s)
		return W(cx + radius * math.sin(theta), radius - radius * math.cos(theta), z)
	end

	for i = 0, segments - 1 do
		local t0 = 2 * math.pi * i / segments
		local t1 = 2 * math.pi * (i + 1) / segments
		local tm = (t0 + t1) / 2
		local inward = Vector3.new(-math.sin(tm), math.cos(tm), 0)
		local p = plank(folder, point(t0), point(t1), inward, width, 1.5, {
			Name = "LoopSegment",
			Color = if i % 2 == 0 then COLOR.loop else COLOR.track,
			Material = Enum.Material.Slate,
		})
		-- Guide parts lock your direction to the segment so the loop's sideways
		-- offset carries you to the exit lane.
		p:SetAttribute("MomentumGuide", true)
	end
end

local function setupLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(110, 50, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 60, 45)
	Lighting.EnvironmentDiffuseScale = 0.3
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.38
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(255, 120, 70)
	atmosphere.Decay = Color3.fromRGB(110, 25, 15)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 2.2
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
		Workspace:SetAttribute("MomentumKillY", ORIGIN.Y - 30)
		return existing
	end

	local level = Instance.new("Folder")
	level.Name = LEVEL_NAME

	-- Ground slab and lava sea
	newPart(level, {
		Name = "Floor",
		Size = Vector3.new(1000, 4, 260),
		Position = W(420, -2, 0),
		Color = COLOR.track,
	})
	newPart(level, {
		Name = "LavaSea",
		Size = Vector3.new(2048, 1, 2048),
		Position = W(420, -45, 0),
		Material = Enum.Material.Neon,
		Color = COLOR.lava,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	strip(level, W(-60, 0, -15), W(920, 0, -15), 1)
	strip(level, W(-60, 0, 15), W(920, 0, 15), 1)

	-- 1. Start platform and the drop: 20 degree slope easing into the floor
	newPart(level, { Name = "StartBlock", Size = Vector3.new(60, 40, 30), Position = W(-30, 20, 0) })
	local spawnPos = W(-45, 40.5, 0)
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

	do
		local r, slope = 40, 20
		local arcStartY = r - r * math.cos(math.rad(slope))
		local straightRun = (40 - arcStartY) / math.tan(math.rad(slope))
		local cx = straightRun + r * math.sin(math.rad(slope))
		local pts = { Vector2.new(0, 40) }
		arc(pts, cx, r, r, -slope, 0, 8)
		table.insert(pts, Vector2.new(cx + 6, 0))
		profile(level, pts, 0, 30, 3, { Name = "Drop", Color = COLOR.slope })
		sign(level, W(20, 46, 0), "THE DROP: hold W to build speed")
	end

	-- 2. Hill: 15 degrees up, plateau, 30 degrees down
	do
		local h = 60 * math.tan(math.rad(15))
		local down = h / math.tan(math.rad(30))
		profile(level, {
			Vector2.new(200, 0),
			Vector2.new(260, h),
			Vector2.new(300, h),
			Vector2.new(300 + down, 0),
		}, 0, 30, 4, { Name = "Hill", Color = COLOR.slope })
		newPart(level, { Name = "HillCore", Size = Vector3.new(36, h - 1, 30), Position = W(280, (h - 1) / 2, 0) })
		sign(level, W(280, h + 10, 0), "HILL: slopes trade speed for height")
	end

	-- 3. Loop: enter on the centre line, exit 16 studs to the right
	do
		local cx, r = 430, 26
		buildLoop(level, cx, r, 0, 16)
		strip(level, W(360, 0, 0), W(428, 0, 0), 2)
		sign(level, W(400, 14, -10), "LOOP: 85+ speed, or spin-dash / boost in")
	end

	-- 4. Launch ramp on the loop's exit lane
	do
		local pts = {}
		arc(pts, 560, 30, 30, 0, 30, 6)
		local last = pts[#pts]
		table.insert(pts, last + Vector2.new(math.cos(math.rad(30)), math.sin(math.rad(30))) * 16)
		profile(level, pts, 16, 24, 2, { Name = "LaunchRamp", Color = COLOR.slope })
		sign(level, W(570, 22, 16), "LAUNCH RAMP")
	end

	-- 5. End quarter pipe: curve up into a vertical wall, then fall back in
	do
		local pts = {}
		arc(pts, 760, 24, 24, 0, 90, 12)
		table.insert(pts, Vector2.new(784, 150))
		profile(level, pts, 0, 120, 3, { Name = "QuarterPipe", Color = COLOR.pipe })
		-- Tall enough that you normally peel off and fall back in; if you boost
		-- over the top you land on the ledge behind it.
		newPart(level, { Name = "QuarterPipeBack", Size = Vector3.new(40, 150, 120), Position = W(807, 75, 0) })
		sign(level, W(740, 30, 0), "QUARTER PIPE: go vertical, come back down")
	end

	-- 6. Wall-run pipe along the left side (negative Z) of the whole course
	do
		local x0, x1 = 150, 700
		local xm, len = (x0 + x1) / 2, x1 - x0
		local cz, cy, r = -70, 20, 20
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
		plank(level, at(90), W(xm, 80, cz - r), Vector3.zAxis, len, 3, { Name = "WallRunWall", Color = COLOR.pipe })
		sign(level, W(180, 20, -50), "WALL RUN: steer left into the curve at speed")
		strip(level, W(150, 0, -45), W(700, 0, -45), 1)
	end

	setupLighting()

	-- Turn off any other spawns (like the Baseplate template's) so you start here.
	for _, d in Workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and d ~= spawn then
			d.Enabled = false
		end
	end

	level.Parent = Workspace
	Workspace:SetAttribute("MomentumKillY", ORIGIN.Y - 30)
	return level
end

return LevelBuilder
