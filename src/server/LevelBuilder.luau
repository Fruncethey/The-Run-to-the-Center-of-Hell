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

-- Scale of the course. Distances along the road, slope heights and curve radii are
-- multiplied by K, so the whole course is big and open; jump gaps and launch ramps
-- are NOT scaled, so every jump still needs the same speed and timing.
local K = 1.6
local LOOP_K = 1.3 -- loops grow less, so the run-up they need stays reasonable
local function L(x: number): number
	return x * K
end
local ROAD = 60 -- main road width
local BRANCH = 44 -- branch road width
local LW = ROAD / 40 -- sideways offsets (branches, signs) were laid out for a 40-wide road
local STEP = 8 -- longest road piece on straights, studs
local TURN_STEP = math.rad(5) -- curve resolution

-- Art direction: a stylized, PS2-era hell. Flat painted colors with strong contrast
-- (plum and obsidian rock, brick-red and orange roads, glowing lava trims) under a
-- purple-to-orange sky. Ash is electric cyan, so nothing in the level uses blue or cyan.
local COLOR = {
	rock = Color3.fromRGB(118, 44, 88), -- plum obsidian
	rock2 = Color3.fromRGB(156, 52, 58), -- red rock band
	pillar = Color3.fromRGB(72, 30, 66), -- dark obsidian
	track = Color3.fromRGB(176, 64, 40), -- brick-red road, alternating stripes
	track2 = Color3.fromRGB(198, 82, 44),
	branch = Color3.fromRGB(122, 48, 128), -- purple side routes
	slope = Color3.fromRGB(226, 112, 40), -- orange slopes
	loop = Color3.fromRGB(214, 38, 58), -- crimson loops
	pipe = Color3.fromRGB(104, 40, 116),
	hurdle = Color3.fromRGB(160, 40, 44),
	trim = Color3.fromRGB(255, 92, 24), -- glowing lava trim
	branchTrim = Color3.fromRGB(255, 70, 170),
	gold = Color3.fromRGB(255, 214, 70),
	lava = Color3.fromRGB(255, 96, 12),
	iron = Color3.fromRGB(52, 40, 58), -- giant chains
}
-- Painted, low-detail surfaces: roads are flat color, rock gets a chunky slate texture
local ROAD_MATERIAL = Enum.Material.SmoothPlastic
local ROCK_MATERIAL = Enum.Material.Slate

local Y = Vector3.yAxis

local function newPart(parent: Instance, props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = ROCK_MATERIAL
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

-- A chunky low-poly rock column: a few stacked blocks, each narrower and twisted a little,
-- so it reads as a bold jagged silhouette. 'away' (optional) is the direction the upper
-- tiers step back toward, so walls never lean in over the road.
local function chunkyColumn(parent: Instance, rng: Random, name: string, baseCF: CFrame, size: Vector3, tiers: number, colors, away: Vector3?)
	local y = 0
	local h = size.Y
	for t = 1, tiers do
		local share = if t == tiers then h - y else (h - y) * rng:NextNumber(0.45, 0.62)
		local shrink = 1 - (t - 1) * 0.2
		local step = if away then away * (t - 1) * size.X * 0.12 else Vector3.zero
		local twist = CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.06, 0.06))
		newPart(parent, deco({
			Name = name,
			Size = Vector3.new(size.X * shrink, share, size.Z * shrink),
			CFrame = (baseCF + step) * CFrame.new(0, y + share / 2, 0) * twist,
			Color = colors[rng:NextInteger(1, #colors)],
		}))
		y += share
	end
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
	len *= K
	dy = (dy or 0) * K
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
	radius *= K
	dy = (dy or 0) * K
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
	radius *= LOOP_K
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
	len *= K
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
				Material = props.Material or ROAD_MATERIAL,
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
			Size = Vector3.new(360, 220 + math.abs(pb.Y - pa.Y), math.max(flatLen, 20) + 30),
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
	local r = 28
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
	plank(parent, at(90), at(90) + Y * 90, right, len, 3, { Name = "WallRunWall", Color = COLOR.pipe })
	newPart(parent, deco({
		Name = "WallRunStripe",
		Size = Vector3.new(1, 1, len),
		CFrame = CFrame.lookAt(at(90) + Y * 30 + right * 1.6, at(90) + Y * 30 + right * 1.6 + h),
		Material = Enum.Material.Neon,
		Color = COLOR.gold,
	}))
end

-- Huge canyon walls along both sides of the main road, rising out of the lava,
-- so the course runs through a vast, enclosed space. A wall is left out anywhere
-- it would come near another stretch of road or a branch.
local function buildCliffs(parent: Instance, road, routes, floorY: number)
	local folder = Instance.new("Folder")
	folder.Name = "Cliffs"
	folder.Parent = parent
	local rng = Random.new(1313)
	local SPACING = 56
	local THICK = 34
	local GAP = 36 -- open space between the road edge and the wall
	local CLEAR = ROAD / 2 + 50 -- how close any route may come to a wall's middle
	local flat = {}
	for i, p in routes do
		flat[i] = Vector2.new(p.X, p.Z)
	end
	local total = road.s
	for s = SPACING / 2, total - SPACING / 2, SPACING do
		local pos, h, right = road:At(s)
		for _, side in { -1, 1 } do
			local lat = side * (ROAD / 2 + GAP + THICK / 2)
			local c = pos + right * lat
			local c2 = Vector2.new(c.X, c.Z)
			local ok = true
			for _, q in flat do
				if (q - c2).Magnitude < CLEAR then
					ok = false
					break
				end
			end
			if ok then
				local top = pos.Y + rng:NextNumber(90, 240)
				local height = top - floorY
				local cf = CFrame.lookAt(Vector3.new(c.X, floorY + height / 2, c.Z), Vector3.new(c.X, floorY + height / 2, c.Z) + h)
				-- Chunky stacked tiers that step back away from the road as they rise
				chunkyColumn(folder, rng, "Cliff", CFrame.lookAt(Vector3.new(c.X, floorY, c.Z), Vector3.new(c.X, floorY, c.Z) + h),
					Vector3.new(THICK, height, SPACING + 10), rng:NextInteger(2, 3), { COLOR.rock, COLOR.rock2, COLOR.pillar }, right * side)
				-- A glowing seam along the inner face, level with the road, for a sense of speed
				newPart(folder, deco({
					Name = "CliffGlow",
					Size = Vector3.new(1, 1.5, SPACING + 10),
					CFrame = CFrame.new(Vector3.new(c.X, pos.Y + 14, c.Z) - right * side * (THICK / 2 + 0.3)) * cf.Rotation,
					Material = Enum.Material.Neon,
					Color = COLOR.trim,
				}))
			end
		end
	end
end

-- Is a point (x, z) at least 'gap' studs from every route point?
local function clearOf(routes, x: number, z: number, gap: number): boolean
	for _, p in routes do
		local dx, dz = p.X - x, p.Z - z
		if dx * dx + dz * dz < gap * gap then
			return false
		end
	end
	return true
end

-- One giant chain hanging from the sky into the lava: alternating links of four bars
local function giantChain(parent: Instance, x: number, z: number, topY: number, bottomY: number, yaw: number)
	local LINK, WIDE, BAR = 46, 26, 6
	local pitch = LINK - BAR * 2 -- links overlap so they read as interlocked
	local y = topY
	local n = 0
	while y > bottomY do
		local cf = CFrame.new(x, y - LINK / 2, z) * CFrame.Angles(0, yaw + (n % 2) * math.pi / 2, 0)
		for _, side in { -1, 1 } do
			newPart(parent, deco({
				Name = "ChainLink",
				Size = Vector3.new(BAR, LINK, BAR),
				CFrame = cf * CFrame.new(side * (WIDE - BAR) / 2, 0, 0),
				Material = Enum.Material.Metal,
				Color = COLOR.iron,
			}))
			newPart(parent, deco({
				Name = "ChainLink",
				Size = Vector3.new(WIDE, BAR, BAR),
				CFrame = cf * CFrame.new(0, side * (LINK - BAR) / 2, 0),
				Material = Enum.Material.Metal,
				Color = COLOR.iron,
			}))
		end
		y -= pitch
		n += 1
	end
end

-- A distant obsidian tower: stacked tiers with glowing window bands and a spike on top
local function hellTower(parent: Instance, rng: Random, x: number, z: number, floorY: number, height: number)
	local base = CFrame.new(x, floorY, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	local w = rng:NextNumber(70, 110)
	local y = 0
	local tiers = 4
	for t = 1, tiers do
		local h = height / tiers * (1.25 - (t - 1) * 0.15)
		local tw = w * (1 - (t - 1) * 0.2)
		newPart(parent, deco({
			Name = "Tower",
			Size = Vector3.new(tw, h, tw),
			CFrame = base * CFrame.new(0, y + h / 2, 0),
			Color = if t % 2 == 0 then COLOR.pillar else COLOR.rock,
		}))
		-- Glowing window band near the top of each tier
		newPart(parent, deco({
			Name = "TowerGlow",
			Size = Vector3.new(tw + 1, 5, tw + 1),
			CFrame = base * CFrame.new(0, y + h * 0.8, 0),
			Material = Enum.Material.Neon,
			Color = COLOR.trim,
		}))
		y += h
	end
	newPart(parent, deco({
		Name = "TowerSpike",
		Size = Vector3.new(w * 0.18, height * 0.3, w * 0.18),
		CFrame = base * CFrame.new(0, y + height * 0.15, 0) * CFrame.Angles(0, math.pi / 4, 0),
		Color = COLOR.pillar,
	}))
end

-- Big set pieces around the course: chunky lava spires, floating rock islands with glowing
-- undersides, giant chains hanging from the sky, and obsidian towers on the horizon.
-- All decoration, kept clear of every route.
local function buildScenery(parent: Instance, minC: Vector3, maxC: Vector3, routes, floorY: number, topY: number)
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	folder.Parent = parent
	local rng = Random.new(666)
	-- Lava spires
	local placed = 0
	for _ = 1, 400 do
		if placed >= 46 then
			break
		end
		local x = rng:NextNumber(minC.X, maxC.X)
		local z = rng:NextNumber(minC.Z, maxC.Z)
		local size = rng:NextNumber(20, 38)
		if clearOf(routes, x, z, size + 50) then
			placed += 1
			local h = rng:NextNumber(160, 320)
			chunkyColumn(folder, rng, "Spire", CFrame.new(x, floorY, z), Vector3.new(size, h, size), 3, { COLOR.pillar, COLOR.rock, COLOR.rock2 })
			newPart(folder, deco({
				Name = "LavaRing",
				Size = Vector3.new(size + 2, 3, size + 2),
				CFrame = CFrame.new(x, floorY + rng:NextNumber(12, 50), z),
				Material = Enum.Material.Neon,
				Color = COLOR.trim,
			}))
		end
	end
	-- Floating rock islands: upside-down chunky rocks with lava glowing underneath
	placed = 0
	for _ = 1, 400 do
		if placed >= 28 then
			break
		end
		local x = rng:NextNumber(minC.X, maxC.X)
		local z = rng:NextNumber(minC.Z, maxC.Z)
		local size = rng:NextNumber(40, 90)
		if clearOf(routes, x, z, size + 110) then
			placed += 1
			local y = rng:NextNumber(minC.Y + 60, topY + 120)
			local h = size * rng:NextNumber(0.9, 1.5)
			-- Built upward from the bottom tip, then flipped, so the wide end is on top
			chunkyColumn(folder, rng, "FloatingRock", CFrame.new(x, y, z) * CFrame.Angles(math.pi, rng:NextNumber(0, math.pi), 0),
				Vector3.new(size, h, size), 3, { COLOR.rock, COLOR.rock2, COLOR.pillar })
			newPart(folder, deco({
				Name = "FloatingRockTop",
				Size = Vector3.new(size * 1.05, 4, size * 1.05),
				CFrame = CFrame.new(x, y + 2, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Color = COLOR.rock2,
			}))
			newPart(folder, deco({
				Name = "FloatingRockGlow",
				Size = Vector3.new(size * 0.35, 3, size * 0.35),
				CFrame = CFrame.new(x, y - h - 1, z),
				Material = Enum.Material.Neon,
				Color = COLOR.lava,
			}))
		end
	end
	-- Giant chains hanging out of the sky
	placed = 0
	for _ = 1, 300 do
		if placed >= 9 then
			break
		end
		local x = rng:NextNumber(minC.X, maxC.X)
		local z = rng:NextNumber(minC.Z, maxC.Z)
		if clearOf(routes, x, z, 140) then
			placed += 1
			giantChain(folder, x, z, topY + rng:NextNumber(500, 800), floorY - 10, rng:NextNumber(0, math.pi))
		end
	end
	-- Obsidian towers ringing the horizon, just past the edge of the course
	local center = (minC + maxC) / 2
	local radius = math.max(maxC.X - minC.X, maxC.Z - minC.Z) / 2 + 500
	for k = 1, 14 do
		local a = (k / 14) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local r = radius + rng:NextNumber(0, 400)
		local x, z = center.X + math.cos(a) * r, center.Z + math.sin(a) * r
		local height = topY - floorY + rng:NextNumber(250, 600)
		if clearOf(routes, x, z, 200) then
			hellTower(folder, rng, x, z, floorY, height)
		end
	end
end

-- Purple-to-orange sky, heavy colored haze that swallows the distance, saturated grading
-- and strong bloom on lava and lights
local function setupLighting()
	Lighting.ClockTime = 17.85 -- dusk: the sun sits just on the horizon, behind the orange haze
	Lighting.GeographicLatitude = 0
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(150, 80, 170)
	Lighting.OutdoorAmbient = Color3.fromRGB(200, 120, 190)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 150, 80) -- warm light from above
	Lighting.ColorShift_Bottom = Color3.fromRGB(120, 40, 150) -- purple bounce from below
	Lighting.EnvironmentDiffuseScale = 0.2
	Lighting.EnvironmentSpecularScale = 0.2
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.StarCount = 0
	sky.SunAngularSize = 24 -- a huge low red sun
	sky.MoonAngularSize = 0
	sky.Parent = Lighting
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(255, 120, 65) -- orange haze along the horizon
	atmosphere.Decay = Color3.fromRGB(130, 40, 160)
	atmosphere.Glare = 0.6
	atmosphere.Haze = 2.2
	atmosphere.Parent = Lighting
	-- A low purple cloud ceiling covers the default skybox, so the sky is purple overhead
	-- and fades into the orange haze at the horizon from every direction
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.9
	clouds.Density = 0.5
	clouds.Color = Color3.fromRGB(72, 26, 96)
	clouds.Parent = Workspace.Terrain
	-- One bloom, tuned for the neon lava; turn off any other bloom so it doesn't stack
	for _, e in Lighting:GetChildren() do
		if e:IsA("BloomEffect") and e.Name ~= "HellBloom" then
			e.Enabled = false
		end
	end
	local bloom = Lighting:FindFirstChild("HellBloom") or Instance.new("BloomEffect")
	bloom.Name = "HellBloom"
	bloom.Intensity = 1
	bloom.Size = 28
	bloom.Threshold = 0.95
	bloom.Parent = Lighting
	local grade = Lighting:FindFirstChild("HellGrade") or Instance.new("ColorCorrectionEffect")
	grade.Name = "HellGrade"
	grade.Saturation = 0.25
	grade.Contrast = 0.12
	grade.Brightness = 0.02
	grade.TintColor = Color3.fromRGB(255, 240, 235)
	grade.Parent = Lighting
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
	local hurdle1 = R.s - L(50)
	R:Gap(26)
	local landing1 = R:Mark("landing1")
	R:Straight(120)
	local hurdle2 = landing1 + L(55)
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
				{ s = valley + L(10), lat = 0 },
				{ s = valley + L(120), lat = -46 * LW, y = yv + L(8) },
				{ s = hills + L(120), lat = -62 * LW, y = yv + L(52) },
				{ s = hills + L(380), lat = -62 * LW, y = yv + L(52) },
				-- Back down to road level while still beside the road, then slide in,
				-- so the merge never puts an edge across the main road
				{ s = hillsEnd + L(10), lat = -(ROAD + BRANCH) / 2 - 1 },
				{ s = hillsEnd + L(60), lat = 0 },
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
		local y0 = R:Point(rampAt - L(60)).Y - ORIGIN.Y
		table.insert(branches, {
			name = "LowBridge",
			keys = {
				{ s = rampAt - L(60), lat = 0 },
				{ s = rampAt + 30, lat = 52 * LW, y = y0 - 18 },
				{ s = island + L(45), lat = 70 * LW, y = y0 - 30 },
				{ s = arrival + L(10), lat = 56 * LW, y = y0 - 18 },
				{ s = arrival + L(60), lat = (ROAD + BRANCH) / 2 + 1 },
				{ s = arrival + L(100), lat = 0 },
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
				{ s = gapStart - L(50), lat = 0 },
				{ s = gapStart + 30, lat = -55 * LW, y = y0 + 2 },
				{ s = gapStart + 100, lat = -80 * LW, y = y0 + 12 },
				{ s = terrace - 10, lat = -50 * LW, y = y0 + 22 },
				{ s = terrace + L(70), lat = 0 },
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
	skipRoad(R, fork + L(30), forkEnd - L(30))
	do
		local y0 = R:Point(fork).Y - ORIGIN.Y
		-- Left fork: a speed dip; right fork: flat with imps
		table.insert(branches, {
			name = "ForkLeft",
			width = ROAD - 6,
			keys = {
				{ s = fork, lat = 0 },
				{ s = fork + L(100), lat = -48 * LW, y = y0 - L(4) },
				{ s = fork + L(150), lat = -52 * LW, y = y0 - L(22) },
				{ s = fork + L(200), lat = -48 * LW, y = y0 - L(4) },
				{ s = forkEnd, lat = 0, y = y0 },
			},
		})
		table.insert(branches, {
			name = "ForkRight",
			width = ROAD - 6,
			keys = {
				{ s = fork, lat = 0 },
				{ s = fork + L(100), lat = 48 * LW, y = y0 },
				{ s = fork + L(200), lat = 48 * LW, y = y0 },
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
	sign(props, R:Point(dropStart + L(30), 0, 9), "HOLD Q DOWNHILL TO ROLL (2x SPEED)")
	enemySpawn(spawns, R:Point(valley + L(90), -6, 4), Vector3.new(0, 0, 7), 1.2)
	enemySpawn(spawns, R:Point(valley + L(120), 6, 4), Vector3.new(0, 0, -7), 1.2)
	sign(props, R:Point(valley + L(60), 10, 13), "ROLL THROUGH IMPS TO SMASH THEM")
	sign(props, R:Point(valley + L(30), -30 * LW, 14), "HIGH RIDGE ← (SKIP THE HILLS)")
	do
		local yv = R:Point(valley).Y
		local p = R:Point(hills + L(250), -62 * LW)
		enemySpawn(spawns, Vector3.new(p.X, yv + L(52) + 12, p.Z))
	end

	-- Stage 3
	chevrons(props, R, stage[3] + L(30), 3, 20)
	sign(props, R:Point(stage[3] + L(50), 0, 13), "STOPPED? HOLD Q TO SPIN-DASH (TAP SPACE TO REV)")
	sign(props, R:Point(loop1, 9, 80), "THE LOOP: SPIN-DASH OR 100+ SPEED")
	sign(props, R:Point(helix, 0, 16), "THE SPIRAL: HOLD FORWARD, IT STEERS FOR YOU")

	-- Stage 4
	sign(props, R:Point(rampAt - L(20), 0, 22), "JUMP + TAP SPACE MID-AIR TO AIR DASH")
	sign(props, R:Point(rampAt - L(70), 40 * LW, 14), "LOW BRIDGE → (THE LONG WAY)")
	sign(props, R:Point(island + L(60), 6, 16), "STEER RIGHT IN MID-AIR + AIR DASH")

	-- Stage 5: homing chain over the gap
	do
		local y0 = R:Point(gapStart).Y
		for i, frac in { 0.22, 0.42, 0.62, 0.8 } do
			local p = R:Point(gapStart + 175 * frac)
			enemySpawn(spawns, Vector3.new(p.X, y0 + 8 + i * 5, p.Z))
		end
		sign(props, R:Point(gapStart - L(30), 0, 22), "LOCK ON -> TAP SPACE TO HOMING ATTACK")
		sign(props, R:Point(gapStart - L(40), -45 * LW, 14), "← CLIMB (NO HOMING NEEDED)")
	end

	-- Stage 6: stomp imp hovering over the steep part of the slope
	do
		local mid = stompSlope + L(165)
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
	chevrons(props, R, gauntlet - L(60), 5, 28)
	sign(props, R:Point(gauntlet - L(20), 0, 15), "HOLD SHIFT TO BOOST THROUGH IMPS (NEEDS HEAT)")
	for i, lat in { 0, 8, -8, 0 } do
		local _, _, right = R:At(gauntlet + L(70 + i * 60))
		enemySpawn(spawns, R:Point(gauntlet + L(70 + i * 60), lat, 4), right * (if i % 2 == 0 then 8 else -8), 1.1)
	end
	wallRunPipe(level, R, gauntlet, gauntletEnd)
	sign(props, R:Point(gauntlet + L(40), -26 * LW, 22), "OR STEER LEFT TO WALL RUN!")
	enemySpawn(spawns, R:Point(gauntlet + L(140), -ROAD / 2 - 16, 30))
	enemySpawn(spawns, R:Point(gauntlet + L(260), -ROAD / 2 - 16, 30))
	do
		local base = R:Point((fork + forkEnd) / 2)
		newPart(props, {
			Name = "ForkPillar",
			Size = Vector3.new(34 * LW, 400, 34 * LW),
			Position = base - Y * 190,
			Color = COLOR.pillar,
		})
		newPart(props, deco({
			Name = "ForkPillarGlow",
			Size = Vector3.new(34 * LW + 1, 3, 34 * LW + 1),
			Position = base - Y * 30,
			Material = Enum.Material.Neon,
			Color = COLOR.trim,
		}))
		sign(props, R:Point(fork - 10, 0, 18), "← SPEED DIP   |   IMP ROW →")
		enemySpawn(spawns, R:Point(fork + L(130), 48 * LW, 4))
		enemySpawn(spawns, R:Point(fork + L(170), 48 * LW, 4))
	end

	-- Stage 8
	chevrons(props, R, bigLoop - L(90), 3, 20)
	sign(props, R:Point(bigLoop, 10, 100), "BOOST THROUGH THE GIANT LOOP!")
	sign(props, R:Point(cork - 20, 0, 18), "CORKSCREW! KEEP YOUR SPEED UP")
	sign(props, R:Point(skyRamp - 30, 0, 18), "SKY JUMP! JUMP AT THE TOP OF THE RAMP")
	do
		local y = R:Point(skyRamp).Y
		for _, frac in { 0.35, 0.6 } do
			local p = R:Point(skyRamp + 44 + 80 * frac)
			enemySpawn(spawns, Vector3.new(p.X, y + 30, p.Z))
		end
	end
	buildGoalGate(level, R, plaza + L(70), 36 * LW)
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
	local floorY = minC.Y - 160 -- a deep drop to the lava below
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
	buildScenery(level, minC - Vector3.new(pad, 0, pad), maxC + Vector3.new(pad, 0, pad), routePts, floorY, maxC.Y)
	buildCliffs(level, R, routePts, floorY)
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
