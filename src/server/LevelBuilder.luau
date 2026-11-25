-- Procedurally builds "Circle 0: The Descent Gate", the tutorial level: a long,
-- twisting speed course over a lava sea that teaches every mechanic in order and
-- offers a choice of routes along the way.
--
-- The main route is laid out like a turtle drawing a road: straights, banked
-- curves, eased slopes, gaps, launch ramps, loops, a helix and a corkscrew. Branch
-- routes are ribbons that peel off the main road (sideways and up or down) and
-- merge back further on.
--
--   1. Run & Jump        hurdles and a gap, then a sweeping right-hander
--   2. Roll & Momentum   a long drop, rolling hills, and a HIGH RIDGE branch above
--   3. Spin-Dash & Loop  a loop, then a guided helix spiralling down
--   4. Air Dash          launch ramp over a chasm, or the long LOW BRIDGE around it
--   5. Homing Chain      imps over a gap up to a terrace, or the winding CLIMB ramp
--   6. Stomp & Descent   a 30 degree stomp slope, then a twisting canyon descent
--   7. Boost & Wall Run  boost gauntlet with a wall-run pipe, then a FORK around a lava pillar
--   8. Finale            dip, giant loop, corkscrew, sky jump and the Descent Gate
--
-- Also places Checkpoints, TutorialZones, GoalGate and invisible "EnemySpawn"
-- markers (filled by EnemyService). Falling into the lava respawns you at your
-- latest checkpoint.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LevelBuilder = {}

local ORIGIN = Vector3.new(0, 200, 0)
local LEVEL_NAME = "HellTestLevel"

local ROAD = 40 -- main road width
local BRANCH = 30 -- branch road width
local STEP = 8 -- longest road piece on straights, studs
local TURN_STEP = math.rad(5) -- curve resolution

local COLOR = {
	rock = Color3.fromRGB(48, 28, 28),
	pillar = Color3.fromRGB(36, 22, 24),
	track = Color3.fromRGB(92, 42, 34),
	track2 = Color3.fromRGB(104, 48, 38),
	branch = Color3.fromRGB(70, 36, 46),
	slope = Color3.fromRGB(122, 52, 36),
	loop = Color3.fromRGB(145, 32, 26),
	pipe = Color3.fromRGB(78, 34, 42),
	hurdle = Color3.fromRGB(72, 32, 32),
	trim = Color3.fromRGB(255, 110, 30),
	branchTrim = Color3.fromRGB(255, 60, 90),
	gold = Color3.fromRGB(255, 195, 80),
	lava = Color3.fromRGB(255, 85, 20),
}

local Y = Vector3.yAxis

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

local function deco(props)
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return props
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return (1 - math.cos(math.pi * t)) / 2
end

local function rotateAround(v: Vector3, axis: Vector3, angle: number): Vector3
	return CFrame.fromAxisAngle(axis, angle):VectorToWorldSpace(v)
end

-- A plank whose top surface runs from a to b. upHint says which side is "up".
-- extra lengthens it at both ends so curved runs leave no gaps on the outside.
local function plank(parent: Instance, a: Vector3, b: Vector3, upHint: Vector3, width: number, thickness: number, props, extra: number?)
	local f = b - a
	local len = f.Magnitude
	if len < 0.05 then
		return nil
	end
	f = f.Unit
	local lateral = f:Cross(upHint)
	if lateral.Magnitude < 1e-3 then
		lateral = f:Cross(Vector3.xAxis)
	end
	lateral = lateral.Unit
	local up = lateral:Cross(f).Unit
	local center = (a + b) / 2 - up * (thickness / 2)
	local p = newPart(parent, props or {})
	p.Size = Vector3.new(width, thickness, len + 0.6 + (extra or 0))
	p.CFrame = CFrame.fromMatrix(center, lateral, up, -f)
	return p
end

-- Floating world sign (supplements the HUD tutorial banner).
local function sign(parent: Instance, position: Vector3, text: string)
	local post = newPart(parent, deco({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		Position = position,
		Transparency = 1,
	}))
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
	local marker = newPart(parent, deco({
		Name = "EnemySpawn",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2,
		Position = position,
		Transparency = 1,
	}))
	if patrol then
		marker:SetAttribute("Patrol", patrol)
	end
	if patrolSpeed then
		marker:SetAttribute("PatrolSpeed", patrolSpeed)
	end
	return marker
end

-- =============================================================================
-- The road: a list of samples {pos, up, s, build, guide, look} laid out by a turtle
-- =============================================================================

local Road = {}
Road.__index = Road

function Road.new(start: Vector3, yaw: number)
	local self = setmetatable({}, Road)
	self.pos = start
	self.yaw = yaw -- 0 = +X, positive turns left (toward -Z)
	self.s = 0
	self.samples = {}
	self.marks = {}
	self:Add(start, Y, true, false, nil)
	return self
end

function Road:Heading(): Vector3
	return Vector3.new(math.cos(self.yaw), 0, -math.sin(self.yaw))
end

function Road:Right(): Vector3
	return self:Heading():Cross(Y)
end

-- build: whether the piece leading up to this sample is solid road
function Road:Add(pos: Vector3, up: Vector3, build: boolean, guide: boolean, opts)
	local last = self.samples[#self.samples]
	local step = if last then (pos - last.pos).Magnitude else 0
	self.s += step
	-- Curbs carry on 50 studs past the end of a curve, so you can't slide off its exit
	local curb = opts and opts.curb
	if curb then
		self.curbSide, self.curbLeft = curb, 50
	elseif self.curbSide and self.curbLeft > 0 and build and not guide then
		curb = self.curbSide
		self.curbLeft -= step
	else
		self.curbSide = nil
	end
	table.insert(self.samples, {
		pos = pos,
		up = up,
		s = self.s,
		build = build,
		guide = guide,
		color = opts and opts.color,
		curb = curb,
		name = opts and opts.name,
		width = opts and opts.width,
	})
	self.pos = pos
end

-- Remember the current distance under a name (for placing things later)
function Road:Mark(name: string)
	self.marks[name] = self.s
	return self.s
end

-- Straight run, optionally changing height with an eased (S-shaped) profile so it
-- blends smoothly into whatever comes before and after.
function Road:Straight(len: number, dy: number?, opts)
	dy = dy or 0
	local h = self:Heading()
	local start = self.pos
	local n = math.max(1, math.ceil(len / STEP))
	for i = 1, n do
		local t = i / n
		local p = start + h * len * t + Y * dy * ease(t)
		local o = opts
		if opts and opts.taper then
			-- Narrow or widen the road (funnels into loops and the corkscrew)
			o = table.clone(opts)
			o.width = opts.taper[1] + (opts.taper[2] - opts.taper[1]) * t
		end
		self:Add(p, Y, true, opts ~= nil and opts.guide == true, o)
	end
end

-- Horizontal curve. angle in degrees, positive = left. bank tilts the road into the turn.
function Road:Curve(angleDeg: number, radius: number, dy: number?, opts)
	dy = dy or 0
	opts = opts or {}
	local angle = math.rad(angleDeg)
	local dir = if angle >= 0 then 1 else -1
	local start = self.pos
	local yaw0 = self.yaw
	local right0 = self:Right()
	local center = start - right0 * radius * dir
	local n = math.max(2, math.ceil(math.abs(angle) / TURN_STEP))
	local bank = math.rad(opts.bank or 0)
	for i = 1, n do
		local t = i / n
		self.yaw = yaw0 + angle * t
		local h = self:Heading()
		local right = h:Cross(Y)
		local p = center + right * radius * dir + Y * dy * ease(t)
		p = Vector3.new(p.X, start.Y + dy * ease(t), p.Z)
		-- Bank fades in and out at the ends of the curve
		local b = bank * math.sin(math.pi * t) ^ 0.6
		local up = rotateAround(Y, h, -b * dir) -- tilt toward the inside of the turn
		self:Add(p, up, true, opts.guide == true, opts)
	end
	self.yaw = yaw0 + angle
end

-- Jump gap: no road. dy changes height, lat shifts sideways (positive = right).
function Road:Gap(len: number, dy: number?, lat: number?)
	local p = self.pos + self:Heading() * len + Y * (dy or 0) + self:Right() * (lat or 0)
	self:Add(p, Y, false, false, nil)
end

-- Launch ramp: curves up from flat to angleDeg over len (a circular arc).
function Road:Ramp(len: number, angleDeg: number, opts)
	local a = math.rad(angleDeg)
	local r = len / math.sin(a)
	local h = self:Heading()
	local start = self.pos
	local n = 6
	for i = 1, n do
		local t = a * i / n
		local p = start + h * r * math.sin(t) + Y * r * (1 - math.cos(t))
		local up = Y * math.cos(t) - h * math.sin(t)
		self:Add(p, up, true, false, opts)
	end
end

-- Vertical loop with a sideways shift so you exit beside the entry (positive = right).
-- The loop is narrower than the road and the shift is wider than the loop, so the
-- way out never overlaps the way in.
function Road:Loop(radius: number, shift: number, width: number)
	local h = self:Heading()
	local right = self:Right()
	local start = self.pos
	local n = 48
	for i = 1, n do
		local th = 2 * math.pi * i / n
		local s = i / n
		local side = right * shift * (3 * s * s - 2 * s * s * s)
		local p = start + h * radius * math.sin(th) + Y * radius * (1 - math.cos(th)) + side
		local up = Y * math.cos(th) - h * math.sin(th)
		self:Add(p, up, true, true, { color = if i % 2 == 0 then COLOR.loop else COLOR.track, width = width })
	end
end

-- Corkscrew: the road twists a full turn around the direction of travel.
function Road:Corkscrew(len: number, radius: number, width: number)
	local h = self:Heading()
	local start = self.pos
	local axis = start + Y * radius
	local n = 40
	for i = 1, n do
		local t = i / n
		local phi = 2 * math.pi * t
		local up = rotateAround(Y, h, phi)
		local p = axis + h * len * t - up * radius
		self:Add(p, up, true, true, { color = if i % 2 == 0 then COLOR.loop else COLOR.track, width = width })
	end
end

-- Sample of the road at distance s: position, heading (flat), right, up
function Road:At(s: number)
	local samples = self.samples
	for i = 2, #samples do
		local a, b = samples[i - 1], samples[i]
		if b.s >= s then
			local t = if b.s > a.s then (s - a.s) / (b.s - a.s) else 0
			local pos = a.pos:Lerp(b.pos, t)
			local d = b.pos - a.pos
			local flat = Vector3.new(d.X, 0, d.Z)
			local h = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
			return pos, h, h:Cross(Y), a.up:Lerp(b.up, t).Unit
		end
	end
	local last = samples[#samples]
	local prev = samples[#samples - 1]
	local d = last.pos - prev.pos
	local h = Vector3.new(d.X, 0, d.Z).Unit
	return last.pos, h, h:Cross(Y), last.up
end

-- A world point beside / above the road at distance s
function Road:Point(s: number, lat: number?, height: number?): Vector3
	local pos, _, right = self:At(s)
	return pos + right * (lat or 0) + Y * (height or 0)
end

-- A flat-oriented frame on the road at s, looking along the road
function Road:Frame(s: number, lat: number?, height: number?): CFrame
	local _, h = self:At(s)
	local p = self:Point(s, lat, height)
	return CFrame.lookAt(p, p + h)
end

-- Turn a list of points (with ups) into road planks with glowing edge trim.
local function buildRibbon(parent: Instance, pts, width: number, props, trimColor: Color3?)
	-- Curb corner points, worked out once per sample so neighbouring curb pieces meet exactly
	local function edge(k: number, side: number): Vector3
		local c = pts[k]
		local prev, nxt = pts[math.max(1, k - 1)], pts[math.min(#pts, k + 1)]
		local f = nxt.pos - prev.pos
		local right = f:Cross(c.up)
		right = if right.Magnitude > 1e-3 then right.Unit else Vector3.zAxis
		return c.pos + right * side * ((c.width or width) / 2 + 1) + c.up * 4.5
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if b.build ~= false then
			local f = b.pos - a.pos
			-- Bend at each end, so the outside of curves stays closed
			local bend = 0
			for _, j in { i - 2, i + 1 } do
				local c = pts[j]
				if c then
					local g = if j < i then a.pos - c.pos else c.pos - b.pos
					if g.Magnitude > 0.05 and f.Magnitude > 0.05 then
						bend = math.max(bend, math.acos(math.clamp(g.Unit:Dot(f.Unit), -1, 1)))
					end
				end
			end
			local w = b.width or width
			local extra = w * math.sin(math.min(bend, 0.6)) * 0.6
			local up = (a.up + b.up).Unit
			local p = plank(parent, a.pos, b.pos, up, w, 3, {
				Name = b.name or props.Name,
				Color = b.color or props.Color or (if i % 2 == 0 then COLOR.track else COLOR.track2),
				Material = props.Material or Enum.Material.Basalt,
			}, extra)
			if p then
				if b.guide then
					-- Guide parts lock your direction to the road (loops, helix, corkscrew)
					p:SetAttribute("MomentumGuide", true)
				end
				local cf, size = p.CFrame, p.Size
				for _, side in { -1, 1 } do
					newPart(parent, deco({
						Name = "Trim",
						Size = Vector3.new(0.8, 0.14, size.Z),
						CFrame = cf * CFrame.new(side * (size.X / 2 - 0.9), size.Y / 2 + 0.05, 0),
						Material = Enum.Material.Neon,
						Color = trimColor or COLOR.trim,
					}))
					-- Curbs keep you on the outside of fast curves
					-- and funnel you into loops. Each runs edge to edge, so a narrowing road
					-- gets a smoothly angled wall instead of a staircase.
					if b.curb == side or b.curb == 0 then
						local ea, eb = edge(i - 1, side), edge(i, side)
						-- Overlap only forward: a piece poking back past the joint would stick out
						-- in front of the previous one, and you'd start a step already touching it
						local dir = (eb - ea).Unit
						newPart(parent, {
							Name = "Curb",
							Size = Vector3.new(2, 9, (eb - ea).Magnitude + 0.75),
							-- Kept upright (not tilted with the bank), so every piece's inner face
							-- lines up exactly with the next one's
							CFrame = CFrame.lookAt((ea + eb) / 2 + dir * 0.375, eb + dir, Y),
							Color = COLOR.pillar,
						})
					end
				end
			end
		end
	end
end

-- A branch route: peels off the road at s0, follows keyframes {s, lat, y}
-- (lat sideways from the road, y absolute height above ORIGIN), and rejoins at the last key.
-- Each pair of keys is blended with an eased curve, so slopes start and end smoothly.
local function branchPoints(road, keys, step: number?)
	step = step or 6
	local pts = {}
	local s0, s1 = keys[1].s, keys[#keys].s
	local n = math.ceil((s1 - s0) / step)
	local k = 1
	for i = 0, n do
		local s = s0 + (s1 - s0) * i / n
		while k < #keys - 1 and s > keys[k + 1].s do
			k += 1
		end
		local a, b = keys[k], keys[k + 1]
		local t = ease((s - a.s) / (b.s - a.s))
		local lat = a.lat + (b.lat - a.lat) * t
		local pos, _, right = road:At(s)
		local yA = a.y or (road:Point(a.s).Y - ORIGIN.Y)
		local yB = b.y or (road:Point(b.s).Y - ORIGIN.Y)
		local y = yA + (yB - yA) * t
		local p = pos + right * lat
		table.insert(pts, { pos = Vector3.new(p.X, ORIGIN.Y + y, p.Z), up = Y, build = true })
	end
	return pts
end

-- Hide the main road between two distances (used where a fork replaces it)
local function skipRoad(road, s0: number, s1: number)
	for _, smp in road.samples do
		if smp.s > s0 + 0.01 and smp.s <= s1 + 0.01 then
			smp.build = false
		end
	end
end

-- Invisible boxes along the road between s0 and s1 for the HUD stage prompt.
local function tutorialZones(parent: Instance, road, order: number, title: string, hint: string, s0: number, s1: number)
	local chunk = 90
	local n = math.max(1, math.ceil((s1 - s0) / chunk))
	for i = 0, n - 1 do
		local a = s0 + (s1 - s0) * i / n
		local b = s0 + (s1 - s0) * (i + 1) / n
		local mid = (a + b) / 2
		local pa, pb = road:Point(a), road:Point(b)
		local flatLen = Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z).Magnitude
		local cf = road:Frame(mid, 0, 40)
		local zone = newPart(parent, deco({
			Name = string.format("Zone%d", order),
			Size = Vector3.new(220, 170 + math.abs(pb.Y - pa.Y), math.max(flatLen, 20) + 30),
			CFrame = cf,
			Transparency = 1,
		}))
		zone:SetAttribute("ZoneOrder", order)
		zone:SetAttribute("ZoneTitle", title)
		zone:SetAttribute("ZoneHint", hint)
	end
end

-- Glowing obsidian checkpoint arch across the road; lights up cyan when crossed.
local function buildCheckpoint(parent: Instance, road, index: number, label: string, s: number)
	local folder = Instance.new("Folder")
	folder.Name = string.format("Checkpoint%d", index)
	folder:SetAttribute("CheckpointIndex", index)
	folder:SetAttribute("CheckpointLabel", label)
	folder.Parent = parent

	local cf = road:Frame(s)
	local halfW = ROAD / 2 + 1.5
	local h = 22
	for _, side in { -1, 1 } do
		newPart(folder, deco({
			Name = "Pillar",
			Size = Vector3.new(3.5, h, 3.5),
			CFrame = cf * CFrame.new(side * halfW, h / 2, 0),
			Color = COLOR.pillar,
		}))
		local accent = newPart(folder, deco({
			Name = "Beacon",
			Size = Vector3.new(1.2, h - 2, 4.1),
			CFrame = cf * CFrame.new(side * halfW, h / 2, 0),
			Material = Enum.Material.Neon,
			Color = COLOR.trim,
		}))
		accent:SetAttribute("GlowAccent", true)
	end
	newPart(folder, deco({
		Name = "Crossbar",
		Size = Vector3.new(ROAD + 6.5, 3, 3.5),
		CFrame = cf * CFrame.new(0, h + 1, 0),
		Color = COLOR.pillar,
	}))
	local barGlow = newPart(folder, deco({
		Name = "ArchGlow",
		Size = Vector3.new(ROAD + 3, 1.1, 4.1),
		CFrame = cf * CFrame.new(0, h - 0.5, 0),
		Material = Enum.Material.Neon,
		Color = COLOR.trim,
	}))
	barGlow:SetAttribute("GlowAccent", true)

	local trigger = newPart(folder, deco({
		Name = "Trigger",
		Size = Vector3.new(ROAD + 40, 50, 24),
		CFrame = cf * CFrame.new(0, 15, 0),
		Transparency = 1,
	}))
	trigger:SetAttribute("SpawnPosition", cf.Position + Y * 4)
	return folder
end

-- Monumental finish gate at the end of the course.
local function buildGoalGate(parent: Instance, road, s: number, width: number)
	local folder = Instance.new("Folder")
	folder.Name = "GoalGate"
	folder.Parent = parent

	local cf = road:Frame(s)
	local halfW = width / 2
	local h = 44
	for _, side in { -1, 1 } do
		newPart(folder, {
			Name = "Monolith",
			Size = Vector3.new(8, h, 8),
			CFrame = cf * CFrame.new(side * halfW, h / 2, 0),
			Color = COLOR.pillar,
		})
		newPart(folder, {
			Name = "Spire",
			Size = Vector3.new(5, 16, 5),
			CFrame = cf * CFrame.new(side * (halfW + 2), h + 6, 0) * CFrame.Angles(0, 0, -side * 0.25),
			Color = COLOR.rock,
		})
		local vein = newPart(folder, deco({
			Name = "Vein",
			Size = Vector3.new(2, h - 4, 8.6),
			CFrame = cf * CFrame.new(side * halfW, h / 2, 0),
			Material = Enum.Material.Neon,
			Color = COLOR.trim,
		}))
		vein:SetAttribute("GlowAccent", true)
	end
	newPart(folder, {
		Name = "Crown",
		Size = Vector3.new(width + 10, 7, 9),
		CFrame = cf * CFrame.new(0, h + 1, 0),
		Color = COLOR.pillar,
	})
	local crownGlow = newPart(folder, deco({
		Name = "CrownGlow",
		Size = Vector3.new(width + 4, 2.2, 9.6),
		CFrame = cf * CFrame.new(0, h - 2.5, 0),
		Material = Enum.Material.Neon,
		Color = COLOR.trim,
	}))
	crownGlow:SetAttribute("GlowAccent", true)
	local curtain = newPart(folder, deco({
		Name = "PortalCurtain",
		Size = Vector3.new(width - 6, h - 4, 1.2),
		CFrame = cf * CFrame.new(0, (h - 4) / 2, 0),
		Material = Enum.Material.Neon,
		Color = COLOR.trim,
		Transparency = 0.68,
	}))
	curtain:SetAttribute("GlowAccent", true)
	newPart(folder, deco({
		Name = "Trigger",
		Size = Vector3.new(width + 24, 120, 28),
		CFrame = cf * CFrame.new(0, 55, 0),
		Transparency = 1,
	}))
	sign(folder, (cf * CFrame.new(0, h + 12, 6)).Position, "THE DESCENT GATE — FINISH")
	return folder
end

-- Chevron arrows painted on the road pointing the way
local function chevrons(parent: Instance, road, s: number, count: number, spacing: number, color: Color3?)
	for i = 0, count - 1 do
		local cf = road:Frame(s + i * spacing, 0, 0.12)
		for _, side in { -1, 1 } do
			newPart(parent, deco({
				Name = "Chevron",
				Size = Vector3.new(1, 0.2, 7.5),
				CFrame = cf * CFrame.new(side * 2.25, 0, -1) * CFrame.Angles(0, side * math.rad(-50), 0),
				Material = Enum.Material.Neon,
				Color = color or COLOR.gold,
			}))
		end
	end
end

-- Quarter pipe + wall along the left edge of a straight piece of road (wall running)
local function wallRunPipe(parent: Instance, road, s0: number, s1: number)
	local a, h, right = road:At(s0)
	local b = road:At(s1)
	local len = (b - a).Magnitude
	local mid = (a + b) / 2
	local r = 20
	local edge = -right * (ROAD / 2)
	local function at(deg: number): Vector3
		local rad = math.rad(deg)
		return mid + edge - right * r * math.sin(rad) + Y * (r - r * math.cos(rad))
	end
	local n = 12
	for i = 0, n - 1 do
		local p0, p1 = at(90 * i / n), at(90 * (i + 1) / n)
		local inward = (mid + edge + Y * r - (p0 + p1) / 2).Unit
		plank(parent, p0, p1, inward, len, 3, { Name = "WallRunCurve", Color = COLOR.pipe })
	end
	plank(parent, at(90), at(90) + Y * 60, right, len, 3, { Name = "WallRunWall", Color = COLOR.pipe })
	newPart(parent, deco({
		Name = "WallRunStripe",
		Size = Vector3.new(1, 1, len),
		CFrame = CFrame.lookAt(at(90) + Y * 20 + right * 1.6, at(90) + Y * 20 + right * 1.6 + h),
		Material = Enum.Material.Neon,
		Color = COLOR.gold,
	}))
end

-- Decorative volcanic spires rising out of the lava sea, kept clear of the routes.
local function buildScenery(parent: Instance, minC: Vector3, maxC: Vector3, routes, floorY: number)
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	folder.Parent = parent
	local rng = Random.new(666)
	local placed = 0
	for _ = 1, 400 do
		if placed >= 46 then
			break
		end
		local x = rng:NextNumber(minC.X, maxC.X)
		local z = rng:NextNumber(minC.Z, maxC.Z)
		local size = rng:NextNumber(16, 30)
		local clear = true
		for _, p in routes do
			if (Vector3.new(p.X, 0, p.Z) - Vector3.new(x, 0, z)).Magnitude < size + 45 then
				clear = false
				break
			end
		end
		if clear then
			placed += 1
			local h = rng:NextNumber(160, 300)
			newPart(folder, deco({
				Name = "Spire",
				Size = Vector3.new(size, h, size),
				CFrame = CFrame.new(x, floorY + h / 2, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Color = COLOR.pillar,
			}))
			newPart(folder, deco({
				Name = "LavaRing",
				Size = Vector3.new(size + 1, 2.5, size + 1),
				CFrame = CFrame.new(x, floorY + rng:NextNumber(12, 50), z),
				Material = Enum.Material.Neon,
				Color = COLOR.trim,
			}))
		end
	end
end

local function setupLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(110, 50, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 60, 45)
	Lighting.EnvironmentDiffuseScale = 0.3
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(255, 120, 70)
	atmosphere.Decay = Color3.fromRGB(110, 25, 15)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.8
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

-- =============================================================================
-- The course
-- =============================================================================

function LevelBuilder.Build(): Instance
	local existing = Workspace:FindFirstChild(LEVEL_NAME)
	if existing then
		if Workspace:GetAttribute("MomentumKillY") == nil then
			Workspace:SetAttribute("MomentumKillY", ORIGIN.Y - 200)
		end
		return existing
	end

	-- A persistent model, so with streaming on every client still gets the whole
	-- course (checkpoints, stage zones and the road you respawn onto) up front
	local level = Instance.new("Model")
	level.Name = LEVEL_NAME
	level.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local roadFolder = Instance.new("Folder")
	roadFolder.Name = "Road"
	roadFolder.Parent = level
	local branchFolder = Instance.new("Folder")
	branchFolder.Name = "Branches"
	branchFolder.Parent = level
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = level
	local zones = Instance.new("Folder")
	zones.Name = "TutorialZones"
	zones.Parent = level
	local checkpoints = Instance.new("Folder")
	checkpoints.Name = "Checkpoints"
	checkpoints.Parent = level
	local spawns = Instance.new("Folder")
	spawns.Name = "EnemySpawns"
	spawns.Parent = level

	local road = Road.new(ORIGIN + Vector3.new(-40, 80, 0), 0)
	local R = road
	local branches = {} -- { name, keys, color }
	local stage = {}

	-- ---------------------------------------------------------------- STAGE 1
	stage[1] = R:Mark("s1")
	R:Straight(200)
	local hurdle1 = R.s - 50
	R:Gap(26)
	local landing1 = R:Mark("landing1")
	R:Straight(120)
	local hurdle2 = landing1 + 55
	R:Curve(-60, 190, 0, { curb = -1 })
	R:Straight(70)
	local cp1 = R.s - 20

	-- ---------------------------------------------------------------- STAGE 2
	stage[2] = R:Mark("s2")
	R:Straight(30)
	local dropStart = R.s
	R:Straight(330, -95, { color = COLOR.slope }) -- long drop, about 24 degrees at its steepest
	local valley = R:Mark("valley")
	R:Straight(150)
	local hills = R.s
	R:Straight(130, 28, { color = COLOR.slope })
	R:Straight(130, -28, { color = COLOR.slope })
	R:Straight(120, 34, { color = COLOR.slope })
	R:Straight(130, -34, { color = COLOR.slope })
	local hillsEnd = R:Mark("hillsEnd")
	R:Straight(60)
	-- HIGH RIDGE: climbs off to the left above the valley and the hills, then drops back in
	do
		local yv = R:Point(valley).Y - ORIGIN.Y
		table.insert(branches, {
			name = "HighRidge",
			keys = {
				{ s = valley + 10, lat = 0 },
				{ s = valley + 120, lat = -46, y = yv + 8 },
				{ s = hills + 120, lat = -62, y = yv + 52 },
				{ s = hills + 380, lat = -62, y = yv + 52 },
				-- Back down to road level while still beside the road, then slide in,
				-- so the merge never puts an edge across the main road
				{ s = hillsEnd + 10, lat = -36 },
				{ s = hillsEnd + 60, lat = 0 },
			},
		})
	end
	R:Curve(95, 210, -20, { bank = 14, curb = 1 })
	R:Curve(-80, 210, -10, { bank = 14, curb = -1 })
	R:Straight(70)
	local cp2 = R.s - 20

	-- ---------------------------------------------------------------- STAGE 3
	stage[3] = R:Mark("s3")
	R:Straight(120)
	R:Straight(80, 0, { taper = { ROAD, 20 }, curb = 0 })
	local loop1 = R:Mark("loop1")
	R:Loop(26, 26, 20)
	R:Straight(60, 0, { taper = { 20, ROAD } })
	R:Straight(10)
	local helix = R:Mark("helix")
	-- The helix: a guided spiral down, banked into the turn
	R:Curve(-360, 90, -70, { bank = 16, guide = true, curb = -1 })
	R:Straight(40, 0, { guide = true, curb = 0 }) -- straightens you out of the spiral
	R:Straight(50)
	local cp3 = R.s - 20

	-- ---------------------------------------------------------------- STAGE 4
	stage[4] = R:Mark("s4")
	R:Straight(90)
	local rampAt = R.s
	R:Ramp(40, 22, { color = COLOR.slope })
	R:Gap(105, -14)
	local island = R:Mark("island")
	R:Straight(90)
	R:Gap(70, 0, 14)
	local arrival = R:Mark("arrival")
	R:Straight(140)
	local cp4 = R.s - 20
	-- LOW BRIDGE: the long way round the chasm, no jumps needed
	do
		local y0 = R:Point(rampAt - 60).Y - ORIGIN.Y
		table.insert(branches, {
			name = "LowBridge",
			keys = {
				{ s = rampAt - 60, lat = 0 },
				{ s = rampAt + 30, lat = 52, y = y0 - 18 },
				{ s = island + 45, lat = 70, y = y0 - 30 },
				{ s = arrival + 10, lat = 56, y = y0 - 18 },
				{ s = arrival + 60, lat = 36 },
				{ s = arrival + 100, lat = 0 },
			},
		})
	end

	-- ---------------------------------------------------------------- STAGE 5
	stage[5] = R:Mark("s5")
	R:Straight(70)
	local gapStart = R.s
	R:Gap(175, 22)
	local terrace = R:Mark("terrace")
	R:Straight(150)
	local cp5 = R.s - 20
	-- CLIMB: a winding ramp beside the homing gap
	do
		local y0 = R:Point(gapStart).Y - ORIGIN.Y
		table.insert(branches, {
			name = "Climb",
			keys = {
				{ s = gapStart - 50, lat = 0 },
				{ s = gapStart + 30, lat = -55, y = y0 + 2 },
				{ s = gapStart + 100, lat = -80, y = y0 + 12 },
				{ s = terrace - 10, lat = -50, y = y0 + 22 },
				{ s = terrace + 70, lat = 0 },
			},
		})
	end

	-- ---------------------------------------------------------------- STAGE 6
	stage[6] = R:Mark("s6")
	R:Straight(20)
	local stompSlope = R.s
	R:Straight(330, -125, { color = COLOR.slope }) -- 30 degrees at its steepest
	R:Straight(40)
	R:Curve(-75, 170, -35, { bank = 14, curb = -1 })
	R:Curve(110, 170, -40, { bank = 16, curb = 1 })
	R:Curve(-60, 200, -25, { bank = 12, curb = -1 })
	R:Straight(90)
	local cp6 = R.s - 20

	-- ---------------------------------------------------------------- STAGE 7
	stage[7] = R:Mark("s7")
	R:Straight(80)
	local gauntlet = R.s
	R:Straight(380)
	local gauntletEnd = R.s
	R:Straight(60)
	local fork = R:Mark("fork")
	R:Straight(300)
	local forkEnd = R.s
	R:Straight(80)
	local cp7 = R.s - 20
	skipRoad(R, fork + 30, forkEnd - 30)
	do
		local y0 = R:Point(fork).Y - ORIGIN.Y
		-- Left fork: a speed dip; right fork: flat with imps
		table.insert(branches, {
			name = "ForkLeft",
			width = ROAD - 6,
			keys = {
				{ s = fork, lat = 0 },
				{ s = fork + 100, lat = -48, y = y0 - 4 },
				{ s = fork + 150, lat = -52, y = y0 - 22 },
				{ s = fork + 200, lat = -48, y = y0 - 4 },
				{ s = forkEnd, lat = 0, y = y0 },
			},
		})
		table.insert(branches, {
			name = "ForkRight",
			width = ROAD - 6,
			keys = {
				{ s = fork, lat = 0 },
				{ s = fork + 100, lat = 48, y = y0 },
				{ s = fork + 200, lat = 48, y = y0 },
				{ s = forkEnd, lat = 0, y = y0 },
			},
		})
	end

	-- ---------------------------------------------------------------- STAGE 8
	stage[8] = R:Mark("s8")
	R:Straight(130, -16, { color = COLOR.slope })
	R:Straight(80)
	R:Straight(80, 0, { taper = { ROAD, 20 }, curb = 0 })
	local bigLoop = R:Mark("bigLoop")
	R:Loop(32, 26, 20)
	R:Straight(60, 0, { taper = { 20, ROAD } })
	R:Straight(30)
	R:Curve(45, 240, 0, { bank = 10, curb = 1 })
	R:Straight(60)
	R:Straight(80, 0, { taper = { ROAD, 16 }, curb = 0 })
	local cork = R:Mark("cork")
	R:Corkscrew(300, 15, 16)
	-- A short guided run-out, so you leave the twist pointing straight down the road
	R:Straight(40, 0, { guide = true, curb = 0, width = 16 })
	R:Straight(60, 0, { taper = { 16, ROAD }, curb = 0 })
	R:Straight(50)
	local skyRamp = R.s
	R:Ramp(44, 24, { color = COLOR.slope })
	R:Gap(80, -16)
	local plaza = R:Mark("plaza")
	R:Straight(200)
	local finish = R.s

	-- ======================================================== BUILD THE ROADS
	buildRibbon(roadFolder, R.samples, ROAD, { Name = "Road" })
	for _, br in branches do
		local folder = Instance.new("Folder")
		folder.Name = br.name
		folder.Parent = branchFolder
		local pts = branchPoints(R, br.keys)
		buildRibbon(folder, pts, br.width or BRANCH, { Name = br.name, Color = COLOR.branch }, COLOR.branchTrim)
		br.points = pts
	end

	-- ============================================================ STAGE PROPS
	-- Stage 1: start gate, hurdles
	local spawnCf = R:Frame(20, 0, 0.5)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MomentumSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = spawnCf
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.Neon
	spawn.Color = COLOR.trim
	spawn.Parent = level
	do
		local cf = R:Frame(45)
		for _, side in { -1, 1 } do
			newPart(props, deco({
				Name = "StartPillar",
				Size = Vector3.new(5, 28, 5),
				CFrame = cf * CFrame.new(side * (ROAD / 2 + 2), 14, 0),
				Color = COLOR.pillar,
			}))
		end
		newPart(props, deco({
			Name = "StartBeam",
			Size = Vector3.new(ROAD + 9, 4, 5),
			CFrame = cf * CFrame.new(0, 29, 0),
			Color = COLOR.pillar,
		}))
		sign(props, (cf * CFrame.new(0, 37, 0)).Position, "CIRCLE 0: THE DESCENT GATE")
	end
	chevrons(props, R, 60, 3, 28)
	for _, spec in { { hurdle1, 4.5, "TAP SPACE TO HOP" }, { hurdle2, 8.5, "HOLD SPACE TO JUMP HIGHER" } } do
		local cf = R:Frame(spec[1])
		newPart(props, {
			Name = "Hurdle",
			Size = Vector3.new(ROAD, spec[2], 6),
			CFrame = cf * CFrame.new(0, spec[2] / 2, 0),
			Color = COLOR.hurdle,
		})
		sign(props, (cf * CFrame.new(0, spec[2] + 7, 0)).Position, spec[3])
	end

	-- Stage 2
	sign(props, R:Point(dropStart + 30, 0, 9), "HOLD Q DOWNHILL TO ROLL (2x SPEED)")
	enemySpawn(spawns, R:Point(valley + 90, -6, 4), Vector3.new(0, 0, 7), 1.2)
	enemySpawn(spawns, R:Point(valley + 120, 6, 4), Vector3.new(0, 0, -7), 1.2)
	sign(props, R:Point(valley + 60, 10, 13), "ROLL THROUGH IMPS TO SMASH THEM")
	sign(props, R:Point(valley + 30, -30, 14), "HIGH RIDGE ← (SKIP THE HILLS)")
	do
		local yv = R:Point(valley).Y
		local p = R:Point(hills + 250, -62)
		enemySpawn(spawns, Vector3.new(p.X, yv + 52 + 12, p.Z))
	end

	-- Stage 3
	chevrons(props, R, stage[3] + 30, 3, 20)
	sign(props, R:Point(stage[3] + 50, 0, 13), "STOPPED? HOLD Q TO SPIN-DASH (TAP SPACE TO REV)")
	sign(props, R:Point(loop1, 9, 60), "THE LOOP: 90+ SPEED OR SPIN-DASH")
	sign(props, R:Point(helix, 0, 16), "THE SPIRAL: HOLD FORWARD, IT STEERS FOR YOU")

	-- Stage 4
	sign(props, R:Point(rampAt - 20, 0, 22), "JUMP + TAP SPACE MID-AIR TO AIR DASH")
	sign(props, R:Point(rampAt - 70, 40, 14), "LOW BRIDGE → (THE LONG WAY)")
	sign(props, R:Point(island + 60, 6, 16), "STEER RIGHT IN MID-AIR + AIR DASH")

	-- Stage 5: homing chain over the gap
	do
		local y0 = R:Point(gapStart).Y
		for i, frac in { 0.22, 0.42, 0.62, 0.8 } do
			local p = R:Point(gapStart + 175 * frac)
			enemySpawn(spawns, Vector3.new(p.X, y0 + 8 + i * 5, p.Z))
		end
		sign(props, R:Point(gapStart - 30, 0, 22), "LOCK ON -> TAP SPACE TO HOMING ATTACK")
		sign(props, R:Point(gapStart - 40, -45, 14), "← CLIMB (NO HOMING NEEDED)")
	end

	-- Stage 6: stomp imp hovering over the steep part of the slope
	do
		local mid = stompSlope + 165
		local p = R:Point(mid)
		enemySpawn(spawns, p + Y * 30)
		sign(props, R:Point(stompSlope - 10, 0, 26), "JUMP OUT, THEN PRESS Q MID-AIR TO STOMP!")
		newPart(props, deco({
			Name = "StompTarget",
			Size = Vector3.new(ROAD - 6, 0.3, 3),
			CFrame = R:Frame(mid, 0, 0.3),
			Material = Enum.Material.Neon,
			Color = COLOR.gold,
		}))
	end

	-- Stage 7: boost gauntlet, wall-run pipe, fork around a lava pillar
	chevrons(props, R, gauntlet - 60, 5, 28)
	sign(props, R:Point(gauntlet - 20, 0, 15), "HOLD SHIFT TO BOOST THROUGH IMPS (NEEDS HEAT)")
	for i, lat in { 0, 8, -8, 0 } do
		local _, _, right = R:At(gauntlet + 70 + i * 60)
		enemySpawn(spawns, R:Point(gauntlet + 70 + i * 60, lat, 4), right * (if i % 2 == 0 then 8 else -8), 1.1)
	end
	wallRunPipe(level, R, gauntlet, gauntletEnd)
	sign(props, R:Point(gauntlet + 40, -26, 22), "OR STEER LEFT TO WALL RUN!")
	enemySpawn(spawns, R:Point(gauntlet + 140, -ROAD / 2 - 16, 26))
	enemySpawn(spawns, R:Point(gauntlet + 260, -ROAD / 2 - 16, 26))
	do
		local base = R:Point((fork + forkEnd) / 2)
		newPart(props, {
			Name = "ForkPillar",
			Size = Vector3.new(34, 260, 34),
			Position = base - Y * 120,
			Color = COLOR.pillar,
		})
		newPart(props, deco({
			Name = "ForkPillarGlow",
			Size = Vector3.new(35, 3, 35),
			Position = base - Y * 30,
			Material = Enum.Material.Neon,
			Color = COLOR.trim,
		}))
		sign(props, R:Point(fork - 10, 0, 18), "← SPEED DIP   |   IMP ROW →")
		enemySpawn(spawns, R:Point(fork + 130, 48, 4))
		enemySpawn(spawns, R:Point(fork + 170, 48, 4))
	end

	-- Stage 8
	chevrons(props, R, bigLoop - 90, 3, 20)
	sign(props, R:Point(bigLoop, 10, 72), "BOOST THROUGH THE GIANT LOOP!")
	sign(props, R:Point(cork - 20, 0, 18), "CORKSCREW! KEEP YOUR SPEED UP")
	sign(props, R:Point(skyRamp - 30, 0, 18), "SKY JUMP! JUMP AT THE TOP OF THE RAMP")
	do
		local y = R:Point(skyRamp).Y
		for _, frac in { 0.35, 0.6 } do
			local p = R:Point(skyRamp + 44 + 80 * frac)
			enemySpawn(spawns, Vector3.new(p.X, y + 30, p.Z))
		end
	end
	buildGoalGate(level, R, plaza + 70, 36)
	do
		local cf = R:Frame(finish - 2)
		newPart(props, {
			Name = "VictoryBackWall",
			Size = Vector3.new(ROAD + 20, 130, 24),
			CFrame = cf * CFrame.new(0, 40, -14),
			Color = COLOR.rock,
		})
	end

	-- ====================================================== CHECKPOINTS, ZONES
	local cps = {
		{ cp1, "ROLL & MOMENTUM" },
		{ cp2, "SPIN-DASH & LOOP" },
		{ cp3, "AIR DASH" },
		{ cp4, "HOMING CHAIN" },
		{ cp5, "STOMP & DESCENT" },
		{ cp6, "BOOST & WALL RUN" },
		{ cp7, "THE FINALE" },
	}
	for i, cp in cps do
		buildCheckpoint(checkpoints, R, i, cp[2], cp[1])
	end

	local texts = {
		{ "STAGE 1 · RUN & JUMP", "Hold W to build speed. Tap Space for a short hop, hold Space to jump higher." },
		{ "STAGE 2 · ROLL & MOMENTUM", "Hold Q while moving downhill to curl into a ball and roll through imps. Or take the HIGH RIDGE on the left!" },
		{ "STAGE 3 · SPIN-DASH & LOOP", "Hold Q while slow to charge a Spin-Dash (tap Space to rev), blast through the loop, then ride the spiral down." },
		{ "STAGE 4 · AIR DASH", "Jump off the ramp and tap Space mid-air to Air Dash. Hold A/D to steer. Or take the LOW BRIDGE on the right." },
		{ "STAGE 5 · HOMING ATTACK", "Jump toward the imps. When the reticle locks on, tap Space to home in and chain across. Or CLIMB on the left." },
		{ "STAGE 6 · STOMP & DESCENT", "Jump off the ledge and press Q mid-air to STOMP onto the slope, then lean through the canyon curves." },
		{ "STAGE 7 · BOOST & WALL RUN", "Fill HEAT past the tick, hold Shift to BOOST through imps, or steer left to wall run. Pick a side at the fork!" },
		{ "FINALE · FULL THROTTLE", "Boost through the giant loop, hold on through the corkscrew, and fly into the Descent Gate!" },
	}
	local stageEnds = { cp1, cp2, cp3, cp4, cp5, cp6, cp7, finish + 30 }
	local prevEnd = -60
	for i, t in texts do
		tutorialZones(zones, R, i, t[1], t[2], prevEnd, stageEnds[i])
		prevEnd = stageEnds[i]
	end

	-- ============================================================= SCENERY
	local minC, maxC = Vector3.one * math.huge, -Vector3.one * math.huge
	local routePts = {}
	for _, smp in R.samples do
		minC = minC:Min(smp.pos)
		maxC = maxC:Max(smp.pos)
		table.insert(routePts, smp.pos)
	end
	for _, br in branches do
		for _, p in br.points do
			minC = minC:Min(p.pos)
			maxC = maxC:Max(p.pos)
			table.insert(routePts, p.pos)
		end
	end
	local floorY = minC.Y - 70
	local pad = 260
	local tile = 2000
	for x = minC.X - pad, maxC.X + pad, tile do
		for z = minC.Z - pad, maxC.Z + pad, tile do
			local sx = math.min(tile, maxC.X + pad - x)
			local sz = math.min(tile, maxC.Z + pad - z)
			newPart(level, deco({
				Name = "LavaSea",
				Size = Vector3.new(sx, 1, sz),
				Position = Vector3.new(x + sx / 2, floorY, z + sz / 2),
				Material = Enum.Material.Neon,
				Color = COLOR.lava,
			}))
		end
	end
	buildScenery(level, minC - Vector3.new(pad, 0, pad), maxC + Vector3.new(pad, 0, pad), routePts, floorY)
	setupLighting()

	-- Turn off any other spawns (like the Baseplate template's) so you start here.
	for _, d in Workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and d ~= spawn then
			d.Enabled = false
		end
	end

	level:SetAttribute("CourseLength", math.floor(finish))
	level.Parent = Workspace
	Workspace:SetAttribute("MomentumKillY", floorY + 20)
	return level
end

return LevelBuilder
