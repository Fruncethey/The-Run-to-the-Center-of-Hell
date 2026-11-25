-- Ash's local effects, driven by CharacterFx every frame:
--   * his cracks smoulder when slow and blaze brighter the faster he goes
--   * the tattered red scarf tail streams and flutters behind him (a little rope sim)
--   * his sneaker flames grow with speed
-- The scarf knot, cracks and flame emitters themselves are built by AshBuilder on the server.

local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local AshFx = {}
AshFx.__index = AshFx

local SCARF = Color3.fromRGB(165, 24, 22)
local SCARF_DARK = Color3.fromRGB(120, 14, 14)
local CRACK_DIM = Color3.fromRGB(120, 32, 8)
local CRACK_HOT = Color3.fromRGB(255, 175, 70)

local function scarfPart(width: number, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = "AshScarfTail"
	p.Size = Vector3.new(width, 0.06, 0.5)
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

function AshFx.Is(character: Model): boolean
	return character:GetAttribute("AshCharacter") == true
end

function AshFx.new(character: Model, ctrl)
	local self = setmetatable({}, AshFx)
	self.ctrl = ctrl
	self.time = 0
	self.glow = 0

	self.cracks = {}
	self.flames = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "AshCrack" then
			table.insert(self.cracks, d)
		elseif d:IsA("ParticleEmitter") and d.Parent and d.Parent.Name == "AshFlame" then
			table.insert(self.flames, d)
		end
	end
	self.knot = character:FindFirstChild("AshScarfKnot", true)
	self.torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")

	-- Scarf tail: a chain of points hanging off the back of the knot, drawn as flat strips.
	-- The last strip splits in two for a tattered end.
	local folder = Instance.new("Folder")
	folder.Name = "AshScarf"
	folder.Parent = Workspace
	self.folder = folder
	local n = Config.AshScarfSegments
	self.points, self.prev, self.strips = {}, {}, {}
	for i = 1, n do
		local width = 0.5 - 0.2 * (i - 1) / math.max(1, n - 1)
		local color = if i % 2 == 0 then SCARF_DARK else SCARF
		if i < n then
			self.strips[i] = { scarfPart(width, color) }
		else
			self.strips[i] = { scarfPart(width * 0.45, SCARF), scarfPart(width * 0.45, SCARF_DARK) }
		end
		for _, p in self.strips[i] do
			p.Parent = folder
		end
	end
	self:ResetScarf()
	return self
end

function AshFx:Anchor(): (Vector3?, CFrame?)
	local knot = self.knot
	if not (knot and knot.Parent and self.torso) then
		return nil, nil
	end
	local cf = knot.CFrame
	return (cf * CFrame.new(0, -0.05, knot.Size.Z / 2)).Position, self.torso.CFrame
end

-- Lay the scarf straight down the back (used at spawn and after a respawn teleport)
function AshFx:ResetScarf()
	local anchor, torso = self:Anchor()
	if not anchor then
		return
	end
	local down = -torso.UpVector * 0.7 + torso.LookVector * -0.3
	for i = 1, Config.AshScarfSegments do
		local p = anchor + down.Unit * Config.AshScarfSegmentLength * i
		self.points[i] = p
		self.prev[i] = p
	end
	self.lastAnchor = anchor
end

function AshFx:UpdateScarf(dt: number, speed: number, hidden: boolean)
	local anchor, torso = self:Anchor()
	if not anchor then
		return
	end
	if hidden then
		for _, strip in self.strips do
			for _, p in strip do
				p.Transparency = 1
			end
		end
		self:ResetScarf()
		return
	end
	if not self.lastAnchor or (anchor - self.lastAnchor).Magnitude > 40 then
		self:ResetScarf()
	end
	self.lastAnchor = anchor

	local C = Config
	local n, len = C.AshScarfSegments, C.AshScarfSegmentLength
	dt = math.min(dt, 1 / 30)
	local damp = math.exp(-C.AshScarfDrag * dt)
	local back = -torso.LookVector
	local right = torso.RightVector
	local up = torso.UpVector
	local flap = math.clamp(speed / 120, 0, 1.5)

	-- Verlet: keep momentum (minus air drag), fall, and flutter more the faster you go
	for i = 1, n do
		local p = self.points[i]
		local v = (p - self.prev[i]) * damp
		self.prev[i] = p
		local wave = self.time * (8 + 10 * flap) - i * 0.9
		local flutter = (right * math.sin(wave) * 0.6 + up * math.cos(wave * 1.3) * 0.8) * C.AshScarfFlutter * flap * (i / n)
		self.points[i] = p + v + (Vector3.new(0, -C.Gravity * 0.35, 0) + flutter) * dt * dt
	end
	-- Keep each link its length (anchor fixed) and keep the tail behind the body
	for _ = 1, 3 do
		local last = anchor
		for i = 1, n do
			local p = self.points[i]
			local rel = p - anchor
			local depth = rel:Dot(back)
			if depth < 0.15 then
				p += back * (0.15 - depth)
			end
			local d = p - last
			if d.Magnitude > 1e-4 then
				p = last + d.Unit * len
			else
				p = last + back * len
			end
			self.points[i] = p
			last = p
		end
	end

	-- Draw the strips
	local last = anchor
	for i = 1, n do
		local p = self.points[i]
		local seg = p - last
		local mid = (p + last) / 2
		local look = if seg.Magnitude > 1e-4 then seg.Unit else back
		local side = look:Cross(up)
		if side.Magnitude < 0.1 then
			side = look:Cross(back)
		end
		side = side.Unit
		local normal = side:Cross(look)
		local strips = self.strips[i]
		if #strips == 1 then
			local s = strips[1]
			s.Size = Vector3.new(s.Size.X, s.Size.Y, len + 0.08)
			s.CFrame = CFrame.fromMatrix(mid, side, normal, -look)
			s.Transparency = 0
		else
			-- Tattered end: two ragged strips of different lengths, splayed apart
			for k, s in strips do
				local sign = if k == 1 then -1 else 1
				local l = len * (if k == 1 then 1.1 else 0.75)
				local off = side * sign * s.Size.X * 0.7
				local dir = (look + side * sign * 0.25).Unit
				local center = last + off + dir * l / 2
				local sSide = dir:Cross(normal).Unit
				s.Size = Vector3.new(s.Size.X, s.Size.Y, l)
				s.CFrame = CFrame.fromMatrix(center, sSide, normal, -dir)
				s.Transparency = 0
			end
		end
		last = p
	end
end

function AshFx:Update(dt: number, speed: number, hidden: boolean)
	local C = Config
	self.time += dt
	-- Cracks: smoulder and slowly pulse at rest, blaze at speed
	local target = math.clamp(speed / C.AshGlowFullSpeed, 0, 1)
	self.glow += (target - self.glow) * (1 - math.exp(-6 * dt))
	local pulse = 0.12 * (0.5 + 0.5 * math.sin(self.time * 3))
	local heat = math.clamp(self.glow + pulse * (1 - self.glow), 0, 1)
	local color = CRACK_DIM:Lerp(CRACK_HOT, heat)
	for _, crack in self.cracks do
		crack.Color = color
	end

	-- Sneaker flames grow with speed
	for _, fire in self.flames do
		fire.Enabled = not hidden
		fire.Rate = 10 + 70 * self.glow
		fire.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45 + 0.5 * self.glow),
			NumberSequenceKeypoint.new(1, 0),
		})
	end

	self:UpdateScarf(dt, speed, hidden)
end

function AshFx:Destroy()
	self.folder:Destroy()
end

return AshFx
