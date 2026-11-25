-- Installer for The Run to the Center of Hell momentum prototype.
-- Paste this whole file into Roblox Studio's Command Bar (View > Command Bar) and press Enter.
-- It (re)creates the scripts; running it again replaces the old copies.
local function put(parent, folderName)
  local old = parent:FindFirstChild(folderName); if old then old:Destroy() end
  local f = Instance.new('Folder'); f.Name = folderName; f.Parent = parent; return f
end
local function script(folder, class, name, source)
  local s = Instance.new(class); s.Name = name; s.Source = source; s.Parent = folder; return s
end
do local f = put(game:GetService('ReplicatedStorage'), 'Momentum')
script(f, 'ModuleScript', 'AshFace', [=====[-- Ash's face: two glowing orange circle eyes and nothing else (no mouth, pupils or
-- brows), drawn with a SurfaceGui on a thin invisible plate in front of the R6 head.
--
-- The server builds it (AshFace.Build) so everyone sees his resting eyes. On your own
-- screen AshFx drives it every frame (AshFace.new + Update), and the eyes alone show
-- his expression:
--   idle        round circles, blinking every few seconds
--   determined  squashed and tilted inward (running, jumping)
--   happy       ^ ^ arcs (above top speed, boosting, homing)
--   falling     bigger circles
--   wince       > < squeezed shut (just got hit)

local Config = require(script.Parent.Config)

local AshFace = {}
AshFace.__index = AshFace

local W, H = 120, 90 -- canvas pixels (plate is 1.2 x 0.9 studs at 100 px per stud)
local EYE = 24 -- circle diameter in pixels
local EYE_Y = 42
local EYE_X = { Left = 40, Right = 80 }
local ORANGE = Color3.fromRGB(255, 140, 30)

local function frame(parent: Instance, name: string, size: UDim2, pos: UDim2, round: boolean?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = ORANGE
	f.BorderSizePixel = 0
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function px(x: number, y: number): UDim2
	return UDim2.fromOffset(x, y)
end

-- Builds the face plate and its gui on an R6 head. Returns the plate.
function AshFace.Build(head: BasePart): BasePart
	local plate = Instance.new("Part")
	plate.Name = "AshFacePlate"
	plate.Size = Vector3.new(W / 100, H / 100, 0.05)
	plate.CFrame = head.CFrame * CFrame.new(0, 0.02, -0.6)
	plate.Transparency = 1
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.Massless = true
	plate.CastShadow = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = plate
	weld.Parent = plate
	plate.Parent = head

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0 -- the eyes glow
	gui.Brightness = 2
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false
	gui.Parent = plate

	for side, x in EYE_X do
		local dir = if side == "Left" then 1 else -1

		-- The circle (squashed, tilted and resized for expressions)
		frame(gui, side .. "Eye", px(EYE, EYE), px(x, EYE_Y), true)

		-- Happy: the top half of an orange ring, like ^
		local happy = frame(gui, side .. "Happy", px(EYE + 4, EYE / 2), px(x, EYE_Y), false)
		happy.BackgroundTransparency = 1
		happy.ClipsDescendants = true
		happy.Visible = false
		local ring = frame(happy, "Ring", px(EYE, EYE), UDim2.new(0.5, 0, 1, 2), true)
		ring.BackgroundTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = ORANGE
		stroke.Thickness = 5
		stroke.Parent = ring

		-- Squeezed shut: > (left eye) or < (right eye)
		local shut = Instance.new("Frame")
		shut.Name = side .. "Shut"
		shut.BackgroundTransparency = 1
		shut.AnchorPoint = Vector2.new(0.5, 0.5)
		shut.Size = px(EYE, EYE)
		shut.Position = px(x, EYE_Y)
		shut.Visible = false
		shut.Parent = gui
		frame(shut, "Top", px(20, 5), UDim2.new(0.5, 0, 0.5, -5)).Rotation = 28 * dir
		frame(shut, "Bottom", px(20, 5), UDim2.new(0.5, 0, 0.5, 5)).Rotation = -28 * dir
	end

	return plate
end

-- Expression targets. w, h: eye size as a share of the circle. tilt: degrees, inner
-- corners down. shape: which drawing to show ("Eye", "Happy" or "Shut").
local EXPRESSIONS = {
	idle = { w = 1, h = 1, tilt = 0, shape = "Eye" },
	determined = { w = 1.1, h = 0.62, tilt = 14, shape = "Eye" },
	happy = { w = 1, h = 1, tilt = 0, shape = "Happy" },
	falling = { w = 1.3, h = 1.3, tilt = 0, shape = "Eye" },
	wince = { w = 1, h = 1, tilt = 0, shape = "Shut" },
}
local SHAPES = { "Eye", "Happy", "Shut" }

-- Client side: drive an existing face. Returns nil if the character has none.
function AshFace.new(character: Model)
	local plate = character:FindFirstChild("AshFacePlate", true)
	local gui = plate and plate:FindFirstChild("Face")
	if not gui then
		return nil
	end
	local self = setmetatable({}, AshFace)
	self.gui = gui
	self.expression = "idle"
	self.state = { w = 1, h = 1, tilt = 0 }
	self.blinkIn = 2 + math.random() * 2
	self.blink = 0
	return self
end

function AshFace:Choose(ctrl, speed: number): string
	local C = Config
	if ctrl.hurtTimer and ctrl.hurtTimer > C.HurtInvulnerability - 0.6 then
		return "wince"
	end
	if not ctrl.grounded and ctrl.velocity.Y < -45 and not ctrl.homingTarget and not ctrl.stomping then
		return "falling"
	end
	if ctrl.boosting or ctrl.homingTarget or speed > C.TopSpeed + 15 then
		return "happy"
	end
	if speed > 20 or not ctrl.grounded then
		return "determined"
	end
	return "idle"
end

function AshFace:Update(dt: number, ctrl, speed: number, hidden: boolean)
	local gui = self.gui
	if not gui.Parent then
		return
	end
	gui.Enabled = not hidden
	if hidden then
		return
	end

	local name = self:Choose(ctrl, speed)
	self.expression = name
	local target = EXPRESSIONS[name]
	local s = self.state
	local k = 1 - math.exp(-14 * dt)
	for _, key in { "w", "h", "tilt" } do
		s[key] += (target[key] - s[key]) * k
	end

	-- Blink every few seconds: the circles squash flat for a moment
	self.blinkIn -= dt
	if self.blinkIn <= 0 then
		self.blink = 0.12
		self.blinkIn = 2 + math.random() * 3
	end
	self.blink = math.max(0, self.blink - dt)
	local h = if self.blink > 0 then 0.12 else s.h

	for side in EYE_X do
		local dir = if side == "Left" then 1 else -1
		local eye = gui[side .. "Eye"]
		eye.Size = px(EYE * s.w, math.max(3, EYE * h))
		eye.Rotation = s.tilt * dir
		for _, shape in SHAPES do
			gui[side .. shape].Visible = shape == target.shape
		end
	end
end

return AshFace
]=====])
script(f, 'ModuleScript', 'AshFx', [=====[-- Ash's local effects, driven by CharacterFx every frame:
--   * the tattered red scarf tail streams and flutters behind him (a little rope sim)
--   * his eyes change expression (AshFace)
-- The scarf knot itself is built by AshBuilder on the server.

local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)
local AshFace = require(script.Parent.AshFace)

local AshFx = {}
AshFx.__index = AshFx

local SCARF = Color3.fromRGB(165, 24, 22)
local SCARF_DARK = Color3.fromRGB(120, 14, 14)

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

	self.knot = character:FindFirstChild("AshScarfKnot", true)
	self.torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	self.face = AshFace.new(character)

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
	self.time += dt
	self:UpdateScarf(dt, speed, hidden)
	if self.face then
		self.face:Update(dt, self.ctrl, speed, hidden)
	end
end

function AshFx:Destroy()
	self.folder:Destroy()
end

return AshFx
]=====])
script(f, 'ModuleScript', 'CharacterFx', [=====[-- Visuals for the local character: a speed-driven procedural run cycle
-- (R6 and R15; other rigs fall back to the default run/idle/fall animations), a molten spin-ball while jumping, rolling or charging, and a fire trail
-- plus glow while boosting, and glowing afterimages at very high speed.
-- Everything here is local-only presentation.

local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)
local RunCycle = require(script.Parent.RunCycle)
local AshFx = require(script.Parent.AshFx)

local CharacterFx = {}
CharacterFx.__index = CharacterFx

local BALL_SIZE = 4.6

-- Afterimage tint: fresh ghosts are hot yellow-orange, cooling to deep red as they fade
local GHOST_HOT = Color3.fromRGB(255, 190, 70)
local GHOST_COLD = Color3.fromRGB(190, 20, 10)

local function loadTrack(animator: Animator, animate: Instance?, folderName: string)
	local folder = animate and animate:FindFirstChild(folderName)
	local anim = folder and folder:FindFirstChildWhichIsA("Animation", true)
	if not anim then
		return nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Looped = true
		return track
	end
	return nil
end

function CharacterFx.new(character: Model, humanoid: Humanoid, root: BasePart, ctrl)
	local self = setmetatable({}, CharacterFx)
	self.character = character
	self.root = root
	self.ctrl = ctrl
	self.spin = 0
	self.hidden = false
	self.mode = nil

	-- Our own state drives animation, so turn off the default Animate script.
	local animate = character:FindFirstChild("Animate")
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animate and animate:IsA("LocalScript") then
		animate.Disabled = true
	end
	self.tracks = {}
	self.runCycle = RunCycle.new(character)
	if animator then
		for _, t in animator:GetPlayingAnimationTracks() do
			t:Stop(0)
		end
	end
	if animator and not self.runCycle then
		self.tracks.run = loadTrack(animator, animate, "run")
		self.tracks.idle = loadTrack(animator, animate, "idle")
		self.tracks.fall = loadTrack(animator, animate, "fall")
	end

	local ball = Instance.new("Part")
	ball.Name = "MomentumSpinBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * BALL_SIZE
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 90, 30)
	ball.Transparency = 1
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	local stripe = Instance.new("Decal")
	stripe.Texture = "rbxasset://textures/SpawnLocation.png"
	stripe.Face = Enum.NormalId.Front
	stripe.Transparency = 1
	stripe.Parent = ball
	ball.Parent = Workspace
	self.ball = ball

	local a0 = Instance.new("Attachment")
	a0.Name = "MomentumTrailTop"
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "MomentumTrailBottom"
	a1.Position = Vector3.new(0, -1.2, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(200, 30, 10))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Enabled = false
	trail.Parent = root
	self.trail = trail

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 40)
	light.Range = 14
	light.Brightness = 0
	light.Parent = root
	self.light = light

	self.parts = {}
	local function track(d)
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(self.parts, d)
		end
	end
	for _, d in character:GetDescendants() do
		track(d)
	end
	self.descConn = character.DescendantAdded:Connect(track)

	local ghostFolder = Instance.new("Folder")
	ghostFolder.Name = "MomentumAfterimages"
	ghostFolder.Parent = Workspace
	self.ghostFolder = ghostFolder
	self.ghosts = {}
	self.ghostTimer = 0

	if AshFx.Is(character) then
		self.ash = AshFx.new(character, ctrl)
	end

	return self
end

-- Copy one visible part as a ghost: same shape and pose, glowing, no collisions.
local function ghostPart(source: BasePart): BasePart?
	local archivable = source.Archivable
	source.Archivable = true
	local ok, copy = pcall(source.Clone, source)
	source.Archivable = archivable
	if not ok or not copy then
		return nil
	end
	for _, child in copy:GetChildren() do
		if not (child:IsA("SpecialMesh") or child:IsA("DataModelMesh")) then
			child:Destroy()
		end
	end
	if copy:IsA("MeshPart") then
		copy.TextureID = ""
	end
	local mesh = copy:FindFirstChildWhichIsA("SpecialMesh")
	if mesh then
		mesh.TextureId = ""
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.CastShadow = false
	copy.Massless = true
	copy.Material = Enum.Material.Neon
	copy.Color = GHOST_HOT
	copy.LocalTransparencyModifier = 0
	copy.CFrame = source.CFrame
	return copy
end

function CharacterFx:SpawnGhost(strength: number)
	local sources = {}
	if self.hidden then
		-- Curled up: ghost the spin-ball instead of the body
		table.insert(sources, self.ball)
	else
		for _, p in self.parts do
			if p:IsA("BasePart") and p.Parent and p ~= self.root and p.Transparency < 0.95 then
				table.insert(sources, p)
			end
		end
	end
	local ghost = { parts = {}, age = 0, strength = strength }
	for _, source in sources do
		local copy = ghostPart(source)
		if copy then
			copy.Transparency = 1
			copy.Parent = self.ghostFolder
			table.insert(ghost.parts, copy)
		end
	end
	table.insert(self.ghosts, ghost)
end

function CharacterFx:UpdateGhosts(dt: number, speed: number)
	local C = Config
	local strength = math.clamp((speed - C.AfterimageSpeed) / (C.AfterimageFullSpeed - C.AfterimageSpeed), 0, 1)
	if strength > 0 then
		self.ghostTimer += dt
		if self.ghostTimer >= C.AfterimageInterval then
			self.ghostTimer = 0
			self:SpawnGhost(0.35 + 0.65 * strength)
		end
	else
		self.ghostTimer = C.AfterimageInterval -- first ghost appears right away next time
	end

	-- Fade and cool every ghost, oldest first
	local i = 1
	while i <= #self.ghosts do
		local ghost = self.ghosts[i]
		ghost.age += dt
		local t = ghost.age / C.AfterimageLifetime
		if t >= 1 then
			for _, part in ghost.parts do
				part:Destroy()
			end
			table.remove(self.ghosts, i)
		else
			local solid = (1 - C.AfterimageStartTransparency) * ghost.strength * (1 - t) ^ 1.5
			local color = GHOST_HOT:Lerp(GHOST_COLD, t)
			for _, part in ghost.parts do
				part.Transparency = 1 - solid
				part.Color = color
			end
			i += 1
		end
	end
end

function CharacterFx:SetHidden(hidden: boolean)
	if hidden == self.hidden then
		return
	end
	self.hidden = hidden
	for _, p in self.parts do
		if p.Parent then
			p.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

function CharacterFx:Play(mode)
	if mode == self.mode then
		return
	end
	for name, track in self.tracks do
		if name ~= mode and track.IsPlaying then
			track:Stop(0.15)
		end
	end
	local track = mode and self.tracks[mode]
	if track then
		track:Play(0.15)
	end
	self.mode = mode
end

-- Joint poses have to be written before physics each frame, so the client calls
-- this from PreSimulation (right after the controller moves the character).
function CharacterFx:UpdatePose(dt: number)
	local rc = self.runCycle
	if not rc then
		return
	end
	local ctrl = self.ctrl
	if ctrl.ball or ctrl.rolling or ctrl.charging then
		rc:Reset()
		return
	end
	local v = ctrl.velocity
	-- How fast the heading is turning around our up axis, for banking into turns
	local up = ctrl.visualUp or Vector3.yAxis
	local flat = v - up * v:Dot(up)
	local turnRate = 0
	local last = self.lastFlat
	if last and flat.Magnitude > 5 and last.Magnitude > 5 and dt > 0 then
		local a, b = last.Unit, flat.Unit
		turnRate = math.atan2(a:Cross(b):Dot(up), a:Dot(b)) / dt
	end
	self.lastFlat = flat
	rc:Update(dt, v.Magnitude, ctrl.grounded, v.Y, turnRate)
end

function CharacterFx:Update(dt: number)
	local ctrl = self.ctrl
	local speed = ctrl.velocity.Magnitude
	local inBall = ctrl.ball or ctrl.rolling or ctrl.charging

	self:SetHidden(inBall)
	if inBall then
		if not self.runCycle then
			self:Play(nil)
		end
		local up = ctrl.visualUp
		local cf = self.root.CFrame
		local radius = BALL_SIZE / 2
		self.spin += (speed / radius + (if ctrl.charging then 25 + ctrl.spinCharge * 40 else 0)) * dt
		local center = cf.Position - up * (ctrl.hipHeight - radius)
		if not ctrl.grounded then
			center = cf.Position
		end
		local size = BALL_SIZE + (if ctrl.charging then ctrl.spinCharge * 0.8 * (0.6 + 0.4 * math.sin(os.clock() * 40)) else 0)
		self.ball.Size = Vector3.one * size
		self.ball.CFrame = (cf - cf.Position + center) * CFrame.Angles(-self.spin, 0, 0)
		self.ball.Transparency = 0.1
		self.ball.Decal.Transparency = 0.3
	else
		self.ball.Transparency = 1
		self.ball.Decal.Transparency = 1
		if self.runCycle then
			-- posed in UpdatePose
		elseif ctrl.grounded then
			self:Play(if speed > 3 then "run" else "idle")
			local run = self.tracks.run
			if run and self.mode == "run" then
				run:AdjustSpeed(math.clamp(speed / 22, 0.7, 3.5))
			end
		else
			self:Play("fall")
		end
	end

	self:UpdateGhosts(dt, speed)
	if self.ash then
		self.ash:Update(dt, speed, self.hidden)
	end

	self.trail.Enabled = ctrl.boosting
	self.light.Brightness = ctrl.heat * 1.5 + (if ctrl.boosting then 2.5 else 0)
	self.light.Range = 10 + ctrl.heat * 8
end

function CharacterFx:Destroy()
	self:SetHidden(false)
	if self.runCycle then
		pcall(self.runCycle.Reset, self.runCycle)
	end
	if self.descConn then
		self.descConn:Disconnect()
	end
	self.ball:Destroy()
	self.ghostFolder:Destroy()
	if self.ash then
		self.ash:Destroy()
	end
	self.trail:Destroy()
	self.light:Destroy()
end

return CharacterFx
]=====])
script(f, 'ModuleScript', 'ChaseCamera', [=====[-- Chase camera: swings in behind your direction of travel, pulls back and widens
-- the FOV as speed rises, and kicks out a little more while boosting.
-- Hold right mouse (or use the right stick) to look around; mouse wheel zooms.

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

local ChaseCamera = {}
ChaseCamera.__index = ChaseCamera

function ChaseCamera.new()
	local self = setmetatable({}, ChaseCamera)
	self.yaw = 0
	self.pitch = Config.CamPitch
	self.distance = Config.CamDistance
	self.fov = Config.FovBase
	self.zoom = 0
	self.manualTimer = 0
	self.stick = Vector2.zero
	self.ctrl = nil

	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.IgnoreWater = true

	UserInputService.InputChanged:Connect(function(io, processed)
		if io.KeyCode == Enum.KeyCode.Thumbstick2 then
			local p = Vector2.new(io.Position.X, io.Position.Y)
			self.stick = if p.Magnitude > 0.2 then p else Vector2.zero
		elseif io.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			self.zoom = math.clamp(self.zoom - io.Position.Z * 2, -8, 24)
		end
	end)
	return self
end

function ChaseCamera:Attach(ctrl, ignore: { Instance })
	self.ctrl = ctrl
	self.rayParams.FilterDescendantsInstances = ignore
	local f = ctrl.facing
	self.yaw = math.atan2(-f.X, -f.Z)
	self.pitch = Config.CamPitch
	self.respawnCount = ctrl.respawnCount
end

function ChaseCamera:Update(dt: number)
	local ctrl = self.ctrl
	local camera = Workspace.CurrentCamera
	if not ctrl or not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	if ctrl.respawnCount ~= self.respawnCount then
		self.respawnCount = ctrl.respawnCount
		self.yaw = math.atan2(-ctrl.facing.X, -ctrl.facing.Z)
		self.pitch = Config.CamPitch
	end

	-- Manual look
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		local d = UserInputService:GetMouseDelta()
		if d.Magnitude > 0 then
			self.yaw -= d.X * Config.CamSensitivity
			self.pitch -= d.Y * Config.CamSensitivity
			self.manualTimer = Config.CamManualHold
		end
	elseif UserInputService.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	if self.stick.Magnitude > 0 then
		self.yaw -= self.stick.X * Config.GamepadCamSpeed * dt
		self.pitch += self.stick.Y * Config.GamepadCamSpeed * 0.6 * dt
		self.manualTimer = Config.CamManualHold
	end
	self.manualTimer -= dt

	-- Auto-follow the direction of travel (not while upside down in a loop)
	local v = ctrl.velocity
	local h = Vector3.new(v.X, 0, v.Z)
	local upright = (not ctrl.grounded) or ctrl.up.Y > 0.35
	if self.manualTimer <= 0 and upright and not ctrl.charging and h.Magnitude > Config.CamFollowMinSpeed then
		local target = math.atan2(-h.X, -h.Z)
		local rate = Config.CamFollowRate * math.clamp(h.Magnitude / 60, 0.3, 2)
		self.yaw = lerpAngle(self.yaw, target, 1 - math.exp(-rate * dt))
		self.pitch += (Config.CamPitch - self.pitch) * (1 - math.exp(-2 * dt))
	end
	self.pitch = math.clamp(self.pitch, -1.3, 0.5)

	-- Pull back and widen with speed
	local alpha = math.clamp(v.Magnitude / Config.CamSpeedForMax, 0, 1)
	local targetDistance = Config.CamDistance + (Config.CamMaxDistance - Config.CamDistance) * alpha + self.zoom
	self.distance += (targetDistance - self.distance) * (1 - math.exp(-3 * dt))
	local targetFov = Config.FovBase + (Config.FovMax - Config.FovBase) * alpha
	if ctrl.boosting then
		targetFov += Config.FovBoostKick
	end
	self.fov += (targetFov - self.fov) * (1 - math.exp(-5 * dt))

	local focus = ctrl.root.Position + Vector3.new(0, Config.CamHeight, 0)
	local rot = CFrame.fromEulerAnglesYXZ(self.pitch, self.yaw, 0)
	local offset = rot:VectorToWorldSpace(Vector3.new(0, 0, self.distance))
	local hit = Workspace:Raycast(focus, offset, self.rayParams)
	local eye = focus + offset
	if hit then
		eye = focus + offset.Unit * math.max(1, hit.Distance - 1)
	end
	if ctrl.boosting then
		eye += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.15
	end

	camera.CFrame = CFrame.lookAt(eye, focus)
	camera.FieldOfView = self.fov
end

return ChaseCamera
]=====])
script(f, 'ModuleScript', 'Config', [=====[-- Tuning values for the momentum controller, camera and heat meter.
-- Units are studs and seconds. Tweak freely while playtesting.

local Config = {
	-- Core movement
	Gravity = 110,
	TerminalVelocity = 220,
	Accel = 55, -- ground acceleration while holding a direction
	Decel = 160, -- braking when holding against your velocity
	Friction = 35, -- ground slowdown with no input
	TopSpeed = 90, -- the fastest you can get by running on flat ground
	MaxSpeed = 320, -- hard cap (slopes, spin-dash and boost can exceed TopSpeed)
	SlopeFactor = 0.55, -- share of gravity that slows you going uphill
	SlopeFactorDown = 1.1, -- share of gravity that speeds you up going downhill
	DescentMinPull = 6, -- on a slope steeper than about 3 degrees, running keeps the speed it gains
	TurnRateSlow = 9, -- radians/sec when standing still
	TurnRateFast = 1.4, -- radians/sec at top speed and above

	-- Air movement
	AirAccel = 45, -- speeding up in the air (only up to TopSpeed)
	AirTurnRate = 2.2, -- radians/sec you can bend your flight path
	AirBrake = 70, -- slowdown when holding against your direction in the air
	AirDrag = 4, -- slowdown above TopSpeed while airborne (not while boosting)
	AirDashSpeed = 110, -- jump again in the air with no target locked
	AirDashLift = 8,
	StompSpeed = 170, -- roll button in the air slams you down
	StompMinAirTime = 0.25, -- so pressing roll as you crest a small bump doesn't stomp

	-- Jump
	JumpPower = 55, -- launched along the surface normal
	JumpCutSpeed = 25, -- releasing jump early caps upward speed to this

	-- Surfaces
	MinWallSpeed = 25, -- below this you peel off walls, ceilings and loop tops
	SteepSurfaceY = 0.5, -- a surface whose normal.Y is below this counts as a wall
	LandMinNormalY = 0.55, -- from the air you only land on surfaces flatter than this
	SnapDistance = 2.5, -- how far below your feet the ground probe reaches
	SnapMinDot = 0.5, -- largest surface angle change (60 deg) the ground snap follows
	TransitionMinDot = 0.64, -- largest angle change (50 deg) you can run straight into
	DetachPush = 6,
	BodyRadius = 1.2,
	BodyOffset = 0.5,
	Skin = 0.05,
	FallRespawnDepth = 100, -- falling this far below where you last stood respawns you
	MaxStepDistance = 2, -- physics substeps so fast movement never tunnels
	VisualUpRate = 12,

	-- Rolling and spin-dash
	-- Rolling keeps momentum better than running but steers and brakes worse,
	-- and holding forward doesn't speed you up: slopes are your engine.
	RollMinSpeed = 20, -- hold the roll button above this speed to curl up
	RollEndSpeed = 8, -- uncurl below this speed
	RollFriction = 4, -- running sheds speed above TopSpeed much faster (RunOverspeedDrag)
	RollTurnFactor = 0.35, -- share of running's turn rate you keep while rolling
	RollBrake = 30, -- holding back while rolling (running brakes at Decel)
	RollSlopeDown = 1.6, -- rolling downhill gains 1.6x the speed running does
	RollSlopeUp = 0.5, -- and loses half as much going uphill
	RunOverspeedDrag = 12, -- on flat ground, running above TopSpeed (not boosting) bleeds back down to it
	SpinDashMaxStartSpeed = 20,
	SpinChargeTime = 0.9, -- seconds of holding for a full charge
	SpinRevBonus = 0.25, -- each jump tap while charging adds this much charge
	SpinDashMin = 60,
	SpinDashMax = 160,

	-- Heat meter and boost
	HeatSpeedThreshold = 50, -- heat builds above this speed
	HeatSpeedRange = 100,
	HeatFillRate = 0.35,
	HeatCoolRate = 0.03,
	BoostDrain = 0.3, -- heat per second while boosting
	BoostMinHeat = 0.15, -- heat needed to start a boost
	BoostSpeed = 170,
	BoostAccel = 500,
	BoostAirHold = 4, -- boosting in the air slows your fall

	-- Chase camera
	CamDistance = 14,
	CamMaxDistance = 28,
	CamHeight = 3,
	CamPitch = -0.25,
	CamSpeedForMax = 200,
	CamFollowRate = 3,
	CamFollowMinSpeed = 12,
	CamManualHold = 1.2, -- seconds the auto-follow waits after you move the camera
	CamSensitivity = 0.004,
	GamepadCamSpeed = 3,
	FovBase = 70,
	FovMax = 95,
	FovBoostKick = 8,

	-- Homing attack and enemies
	HomingRange = 75, -- how far away an enemy can be locked onto
	HomingConeDot = 0.2, -- how far off your heading it can be (cosine of the angle)
	HomingSpeed = 190,
	HomingHitRadius = 4.5,
	HomingMaxTime = 1.0, -- give up if the target hasn't been reached by then
	HomingBounce = 55, -- upward pop after a hit, so you can chain to the next one
	EnemyContactRadius = 2.6, -- added to the enemy's own radius
	EnemyKnockback = 45,
	EnemyHeatLoss = 0.25, -- heat lost when an enemy hits you
	HurtInvulnerability = 1.2, -- seconds you can't be hit again

	-- Procedural run cycle (R15 and R6)
	RunCycleWalkSpeed = 20, -- full walk stride by this speed
	RunCycleRunSpeed = 60, -- full run (knee lift, arm pump, lean) by this speed
	RunCycleSprintSpeed = 100, -- arms start sweeping back here
	RunCycleSprintBlend = 50, -- ...and are fully back this much faster
	RunCycleMinCadence = 0.5, -- base step cycles per second at slow speeds
	RunCycleCadencePerSpeed = 0.022, -- extra step cycles per second per stud/s (~2.5 at 90, ~4.2 at 170, ~7.5 at 320)
	RunCycleMaxCadence = 12, -- high safety cap so extreme speeds don't strobe at 60 FPS
	RunCycleSmoothing = 8, -- how fast the gait follows speed changes
	-- Overdrive: small extras from running top speed (TopSpeed) up to RunCycleOverdriveSpeed,
	-- so the pose keeps up with boosts and slopes. Below TopSpeed nothing changes.
	RunCycleOverdriveSpeed = 200, -- the extras are fully in by this speed
	RunCycleOverdriveStride = 0.12, -- leg stride grows by up to 12%
	RunCycleOverdriveLean = 0.4, -- extra forward tilt of the torso by RunCycleOverdriveSpeed, radians
	RunCycleRunLean = 0.45, -- forward tilt of the torso at full running speed, radians
	-- Top-speed pose: above normal running speed (boosts, slopes) the arms sweep behind the back
	RunCycleTopStart = 100, -- starts blending in here (running tops out at 90)
	RunCycleTopFull = 150, -- fully in by this speed
	RunCycleTopLean = 0.5, -- extra forward tilt of the torso, radians
	RunCycleTopArmBack = 1.35, -- how far back the arms sweep, radians
	RunCycleTopArmOut = 0.2, -- arms angle slightly out from the body, radians
	RunCycleBank = 0.004, -- how far the body leans into turns (times turn rate times speed)
	RunCycleBankMax = 0.48, -- radians, the most it ever banks
	RunCycleArmDetach = 0.04, -- studs the running arms float away from the shoulders
	RunCycleArmSnap = 0.82, -- below 1 the arms hold forward/back and switch quickly (1 = smooth swing)
	RunCycleExaggeration = 1.05, -- cartoon factor for the run and sprint (1 = realistic, 2 = very rubbery)

	-- Afterimages: glowing ghost copies left behind at very high speed
	AfterimageSpeed = 140, -- ghosts start appearing above this speed (running tops out at 90)
	AfterimageFullSpeed = 200, -- ...and are at full strength by this speed
	AfterimageInterval = 0.05, -- seconds between ghosts
	AfterimageLifetime = 0.3, -- seconds each ghost takes to fade out
	AfterimageStartTransparency = 0.45, -- how solid a fresh ghost is at full strength

	-- Ash (the main character)
	AshBodyColor = Color3.fromRGB(30, 200, 255), -- electric cyan: the opposite of lava orange, so he stands out
	AshScarfSegments = 7, -- links in the scarf tail
	AshScarfSegmentLength = 0.5,
	AshScarfDrag = 3, -- air drag on the scarf; higher streams it straighter behind
	AshScarfFlutter = 40, -- how hard the tail whips about at speed

	CollisionGroup = "MomentumPlayer",
}

return Config
]=====])
script(f, 'ModuleScript', 'Controller', [=====[-- Momentum character controller.
-- Replaces Humanoid movement with our own velocity, slope physics, ground snapping
-- and surface alignment, so the character can run up walls and around loops.
-- The Humanoid is kept in the Physics state; every frame we write the root CFrame
-- and velocity ourselves (the client owns its character, so this replicates).

local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local WORLD_UP = Vector3.yAxis

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function projectOnPlane(v: Vector3, n: Vector3): Vector3
	return v - n * v:Dot(n)
end

local function safeUnit(v: Vector3, fallback)
	local m = v.Magnitude
	if m > 1e-5 then
		return v / m
	end
	return fallback
end

-- Rotate unit vector `dir` toward `target` around `normal`, by at most `maxAngle` radians.
local function rotateToward(dir: Vector3, target: Vector3, normal: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(dir:Dot(target), -1, 1))
	if angle <= maxAngle then
		return target
	end
	local axis = if dir:Cross(target):Dot(normal) >= 0 then normal else -normal
	return CFrame.fromAxisAngle(axis, maxAngle) * dir
end

-- How fast running can turn: sharp when slow, wide arcs at top speed.
local function runTurnRate(speed: number): number
	local t = math.clamp(speed / Config.TopSpeed, 0, 1)
	local rate = Config.TurnRateSlow + (Config.TurnRateFast - Config.TurnRateSlow) * t
	-- Past top speed (slopes, boosts) keep the turning circle the same size, so
	-- you can still take the curves at the bottom of a big drop
	return rate * math.max(1, speed / Config.TopSpeed)
end

local function towards(a: Vector3, b: Vector3, t: number): Vector3
	if a:Dot(b) < -0.95 then
		a = (a + Vector3.new(0.1, 0, 0.05)).Unit
	end
	return safeUnit(a:Lerp(b, t), b)
end

local Controller = {}
Controller.__index = Controller

function Controller.new(character: Model, humanoid: Humanoid, root: BasePart)
	local self = setmetatable({}, Controller)
	self.character = character
	self.humanoid = humanoid
	self.root = root

	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		self.hipHeight = root.Size.Y / 2 + 2
	else
		self.hipHeight = humanoid.HipHeight + root.Size.Y / 2
	end

	self.position = root.Position
	self.velocity = Vector3.zero
	self.up = WORLD_UP
	self.visualUp = WORLD_UP
	self.facing = safeUnit(flatten(root.CFrame.LookVector), Vector3.xAxis)
	self.grounded = false
	self.groundPart = nil
	self.airGrace = 0

	self.jumping = false
	self.jumpNormal = WORLD_UP
	self.ball = false -- curled up after a jump
	self.rolling = false
	self.charging = false
	self.spinCharge = 0
	self.boosting = false
	self.heat = 0

	-- Air moves and homing attack
	self.airDashed = false
	self.stomping = false
	self.airTime = 0
	self.homingTarget = nil -- BasePart we're flying at
	self.homingTime = 0
	self.lockTarget = nil -- set each frame by the lock-on system
	self.attackTimer = 0 -- brief window after an attack where touching an enemy still defeats it
	self.hurtTimer = 0
	self.onEnemyHit = nil -- callback(part) when a homing attack connects

	self.spawnPosition = root.Position
	self.spawnFacing = self.facing
	self.initialSpawnPosition = root.Position
	self.initialSpawnFacing = self.facing

	self.input = {
		move = Vector2.zero,
		jumpHeld = false,
		jumpPressed = false,
		rollHeld = false,
		rollPressed = false,
		boostHeld = false,
	}

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	self.rayParams = params

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.RespectCanCollide = true
	self.overlapParams = overlap

	return self
end

function Controller:SetFacing(look: Vector3)
	local f = safeUnit(flatten(look), nil)
	if f then
		self.facing = f
		self.spawnFacing = f
		self.initialSpawnFacing = f
	end
end

function Controller:SetCheckpoint(position: Vector3, facing: Vector3)
	self.spawnPosition = position
	local f = safeUnit(flatten(facing), nil)
	if f then
		self.spawnFacing = f
	end
end

function Controller:AddIgnore(instance: Instance)
	local list = self.rayParams.FilterDescendantsInstances
	table.insert(list, instance)
	self.rayParams.FilterDescendantsInstances = list
	self.overlapParams.FilterDescendantsInstances = list
end

function Controller:GetSpeed(): number
	return self.velocity.Magnitude
end

-- Camera-relative input, worked out on flat ground and then tilted onto the
-- surface we're standing on. Tilting (instead of projecting the camera onto the
-- surface) keeps "forward" meaning "keep going" on walls, loops and ceilings.
function Controller:GetWishDirection(camCF: CFrame, up: Vector3): Vector3
	local mv = self.input.move
	local amount = math.min(mv.Magnitude, 1)
	if amount < 0.1 then
		return Vector3.zero
	end
	local fwd = safeUnit(flatten(camCF.LookVector), nil)
		or safeUnit(flatten(camCF.UpVector), nil)
		or safeUnit(flatten(self.facing), Vector3.xAxis)
	local right = fwd:Cross(WORLD_UP)
	local wish = safeUnit(fwd * mv.Y + right * mv.X, Vector3.zero)

	if up.Y < 0.999 then
		local axis = WORLD_UP:Cross(up)
		local angle = math.acos(math.clamp(up.Y, -1, 1))
		if axis.Magnitude < 1e-3 then
			-- Upside down: flip over the axis we're travelling around
			axis = safeUnit(self.facing:Cross(up), Vector3.zAxis)
		end
		wish = projectOnPlane(CFrame.fromAxisAngle(axis.Unit, angle) * wish, up)
		wish = safeUnit(wish, Vector3.zero)
	end
	return wish * amount
end

function Controller:Step(dt: number, camCF: CFrame)
	dt = math.min(dt, 1 / 20)
	local input = self.input
	self.airGrace = math.max(0, self.airGrace - dt)
	self.attackTimer = math.max(0, self.attackTimer - dt)
	self.airTime = if self.grounded then 0 else self.airTime + dt
	self.hurtTimer = math.max(0, self.hurtTimer - dt)

	local planeUp = if self.grounded then self.up else WORLD_UP
	local wish = self:GetWishDirection(camCF, planeUp)

	-- Jump, or rev the spin-dash while charging. In the air: homing attack if an
	-- enemy is locked on, otherwise a one-time air dash.
	if input.jumpPressed then
		input.jumpPressed = false
		if self.charging then
			self.spinCharge = math.min(1, self.spinCharge + Config.SpinRevBonus)
		elseif self.grounded then
			self:Jump()
		elseif not self.homingTarget then
			if self.lockTarget then
				self:StartHoming(self.lockTarget)
			elseif not self.airDashed then
				self:AirDash(wish)
			end
		end
	end
	if input.rollPressed then
		input.rollPressed = false
		if
			not self.grounded
			and not self.homingTarget
			and not self.stomping
			and self.airTime >= Config.StompMinAirTime
		then
			self:Stomp()
		end
	end
	if self.jumping then
		local along = self.velocity:Dot(self.jumpNormal)
		if not input.jumpHeld then
			if along > Config.JumpCutSpeed then
				self.velocity -= self.jumpNormal * (along - Config.JumpCutSpeed)
			end
			self.jumping = false
		elseif along <= 0 then
			self.jumping = false
		end
	end

	self:UpdateRollAndCharge(dt, wish)
	self:UpdateBoostAndHeat(dt)

	if self.homingTarget then
		self:UpdateHoming(dt)
	elseif self.grounded then
		self:GroundMovement(dt, wish)
	else
		self:AirMovement(dt, wish)
	end

	local speed = self.velocity.Magnitude
	if speed > Config.MaxSpeed then
		self.velocity *= Config.MaxSpeed / speed
	end

	-- Integrate in substeps so high speeds never skip through geometry
	local distance = self.velocity.Magnitude * dt
	local steps = math.clamp(math.ceil(distance / Config.MaxStepDistance), 1, 16)
	local sdt = dt / steps
	for _ = 1, steps do
		self:MoveAndCollide(self.velocity * sdt)
		self:PushOutOfWalls()
		if self.grounded then
			self:ProbeGround(sdt)
		else
			self:ProbeLanding(sdt)
		end
		if self.homingTarget then
			self:CheckHomingHit()
		end
	end

	-- Facing follows velocity on the current plane
	local ref = if self.grounded then self.up else WORLD_UP
	local planar = projectOnPlane(self.velocity, ref)
	if planar.Magnitude > 2 and not self.charging then
		self.facing = planar.Unit
	end

	local targetUp = if self.grounded then self.up else WORLD_UP
	self.visualUp = towards(self.visualUp, targetUp, 1 - math.exp(-Config.VisualUpRate * dt))

	local killY = Workspace:GetAttribute("MomentumKillY")
	if typeof(killY) == "number" and self.position.Y < killY then
		self:Respawn()
	elseif not self.grounded and self.lastGroundY and self.position.Y < self.lastGroundY - Config.FallRespawnDepth then
		-- Missed a jump: respawn now instead of landing on some lower part of the course
		self:Respawn()
	end
end

function Controller:Jump()
	local n = self.up
	self.velocity += n * Config.JumpPower
	self.position += n * 0.1
	self.grounded = false
	self.groundPart = nil
	self.jumping = true
	self.jumpNormal = n
	self.ball = true
	self.rolling = false
	self.airGrace = 0.1
end

function Controller:UpdateRollAndCharge(dt: number, wish: Vector3)
	if not self.grounded then
		self.charging = false
		self.spinCharge = 0
		return
	end

	if self.charging then
		if self.input.rollHeld then
			self.spinCharge = math.min(1, self.spinCharge + dt / Config.SpinChargeTime)
			self.velocity *= math.max(0, 1 - 12 * dt)
			if wish.Magnitude > 0.1 then
				self.facing = wish.Unit
			end
		else
			local dir = safeUnit(projectOnPlane(self.facing, self.up), nil)
			if dir then
				local power = Config.SpinDashMin + (Config.SpinDashMax - Config.SpinDashMin) * self.spinCharge
				self.velocity = dir * power
			end
			self.charging = false
			self.spinCharge = 0
			self.rolling = true
		end
		return
	end

	if self.input.rollHeld and not self.rolling and not self.boosting then
		local speed = self.velocity.Magnitude
		if speed < Config.SpinDashMaxStartSpeed then
			self.charging = true
			self.spinCharge = 0
		elseif speed >= Config.RollMinSpeed then
			self.rolling = true
		end
	end
end

function Controller:UpdateBoostAndHeat(dt: number)
	local speed = self.velocity.Magnitude
	local want = self.input.boostHeld
		and not self.charging
		and not self.stomping
		and self.homingTarget == nil
		and self.heat > 0
	if want and not self.boosting and self.heat < Config.BoostMinHeat then
		want = false
	end
	self.boosting = want

	if self.boosting then
		self.heat = math.max(0, self.heat - Config.BoostDrain * dt)
		self.rolling = false
		if self.grounded then
			local dir = (if speed > 1 then self.velocity / speed else nil)
				or safeUnit(projectOnPlane(self.facing, self.up), nil)
			if dir and speed < Config.BoostSpeed then
				self.velocity = dir * math.min(Config.BoostSpeed, speed + Config.BoostAccel * dt)
			end
		else
			-- Air boost pushes along your horizontal heading. Flying straight up
			-- (off the top of a wall) has no real heading, so it only slows the fall.
			local h = flatten(self.velocity)
			local hs = h.Magnitude
			if hs > 20 and hs < Config.BoostSpeed then
				h = (h / hs) * math.min(Config.BoostSpeed, hs + Config.BoostAccel * dt)
			end
			local vy = self.velocity.Y
			if vy < 0 then
				vy *= math.max(0, 1 - Config.BoostAirHold * dt)
			end
			self.velocity = Vector3.new(h.X, vy, h.Z)
		end
	else
		local over = speed - Config.HeatSpeedThreshold
		if over > 0 then
			self.heat = math.min(1, self.heat + over / Config.HeatSpeedRange * Config.HeatFillRate * dt)
		else
			self.heat = math.max(0, self.heat - Config.HeatCoolRate * dt)
		end
	end
end

function Controller:GroundMovement(dt: number, wish: Vector3)
	local n = self.up
	local vel = projectOnPlane(self.velocity, n)

	-- Gravity along the slope: this is what makes momentum matter
	local gTan = projectOnPlane(Vector3.new(0, -Config.Gravity, 0), n)
	-- Going downhill pulls harder than going uphill holds you back, so slopes
	-- always pay out speed and loops still need the same run-up as before
	local downhill = gTan:Dot(vel) > 0
	local slope = if downhill then Config.SlopeFactorDown else Config.SlopeFactor
	if self.rolling then
		slope *= if downhill then Config.RollSlopeDown else Config.RollSlopeUp
	end
	if not self.charging then
		vel += gTan * slope * dt
	end

	local speed = vel.Magnitude
	local dir = if speed > 0.05 then vel / speed else nil
	local amount = wish.Magnitude
	local w = if amount > 0.05 then wish / amount else nil

	if self.charging then
		-- braking handled in UpdateRollAndCharge
	elseif self.rolling then
		-- No acceleration, a weak brake and a third of the steering, but very little friction
		if w and dir then
			if w:Dot(dir) < -0.5 then
				speed = math.max(0, speed - Config.RollBrake * amount * dt)
			else
				dir = rotateToward(dir, w, n, runTurnRate(speed) * Config.RollTurnFactor * amount * dt)
			end
		end
		speed = math.max(0, speed - Config.RollFriction * dt)
		if speed < Config.RollEndSpeed then
			self.rolling = false
		end
	elseif w then
		if not dir or speed < 3 then
			dir = w
			speed += Config.Accel * amount * dt
		else
			local along = w:Dot(dir)
			if along < -0.5 and not self.boosting then
				speed = math.max(0, speed - Config.Decel * dt)
			else
				dir = rotateToward(dir, w, n, runTurnRate(speed) * dt)
				if speed < Config.TopSpeed and not self.boosting then
					speed = math.min(Config.TopSpeed, speed + Config.Accel * amount * dt)
				end
			end
		end
	elseif not self.boosting then
		speed = math.max(0, speed - Config.Friction * dt)
	end

	-- Running can't hold onto speed past TopSpeed the way a roll can, except while
	-- a real downhill is still feeding it
	local onDescent = downhill and gTan.Magnitude > Config.DescentMinPull
	if not self.rolling and not self.charging and not self.boosting and not onDescent and speed > Config.TopSpeed then
		speed = math.max(Config.TopSpeed, speed - Config.RunOverspeedDrag * dt)
	end

	if dir then
		vel = safeUnit(projectOnPlane(dir, n), dir) * speed
	else
		vel = Vector3.zero
	end

	-- Guide surfaces (loops, corkscrews): lock direction to the part's LookVector
	local part = self.groundPart
	if part and part:GetAttribute("MomentumGuide") and vel.Magnitude > 1 then
		local look = safeUnit(projectOnPlane(part.CFrame.LookVector, n), nil)
		if look then
			local sign = if vel:Dot(look) >= 0 then 1 else -1
			vel = look * sign * vel.Magnitude
		end
	end

	self.velocity = vel
end

-- Air control: bend your flight path toward the stick (limited turn rate, so
-- speed carries you), speed up to TopSpeed, brake by pulling back, and bleed off
-- a little extra speed above TopSpeed.
function Controller:AirMovement(dt: number, wish: Vector3)
	local vel = self.velocity + Vector3.new(0, -Config.Gravity * dt, 0)
	if self.stomping then
		self.velocity = vel
		return
	end

	local h = flatten(vel)
	local hs = h.Magnitude
	local amount = wish.Magnitude
	if amount > 0.05 then
		local w = flatten(wish) / amount
		if hs > 5 then
			local dir = h / hs
			if w:Dot(dir) < -0.5 then
				hs = math.max(0, hs - Config.AirBrake * amount * dt)
			else
				dir = rotateToward(dir, w, WORLD_UP, Config.AirTurnRate * amount * dt)
				if hs < Config.TopSpeed then
					hs = math.min(Config.TopSpeed, hs + Config.AirAccel * amount * dt)
				end
			end
			h = dir * hs
		else
			h += w * Config.AirAccel * amount * dt
		end
	end

	hs = h.Magnitude
	if hs > Config.TopSpeed and not self.boosting then
		h *= math.max(Config.TopSpeed, hs - Config.AirDrag * dt) / hs
	end

	vel = Vector3.new(h.X, math.max(vel.Y, -Config.TerminalVelocity), h.Z)
	self.velocity = vel
end

function Controller:AirDash(wish: Vector3)
	local dir = safeUnit(flatten(wish), nil)
		or safeUnit(flatten(self.velocity), nil)
		or safeUnit(flatten(self.facing), Vector3.xAxis)
	local speed = math.max(flatten(self.velocity).Magnitude, Config.AirDashSpeed)
	self.velocity = dir * speed + Vector3.new(0, Config.AirDashLift, 0)
	self.facing = dir
	self.airDashed = true
	self.ball = true
	self.jumping = false
	self.attackTimer = 0.3
end

function Controller:Stomp()
	self.velocity = Vector3.new(0, -Config.StompSpeed, 0)
	self.stomping = true
	self.ball = true
	self.jumping = false
	self.boosting = false
end

function Controller:StartHoming(target: BasePart)
	self.homingTarget = target
	self.homingTime = 0
	self.ball = true
	self.jumping = false
	self.stomping = false
end

function Controller:CancelHoming()
	self.homingTarget = nil
	self.attackTimer = 0.2
end

local function targetAlive(part: BasePart?): boolean
	return part ~= nil and part.Parent ~= nil and part:IsDescendantOf(Workspace) and not part:GetAttribute("Defeated")
end

function Controller:UpdateHoming(dt: number)
	local target = self.homingTarget
	self.homingTime += dt
	if not targetAlive(target) or self.homingTime > Config.HomingMaxTime then
		self:CancelHoming()
		return
	end
	local to = target.Position - self.position
	local dir = safeUnit(to, nil)
	if dir then
		self.velocity = dir * Config.HomingSpeed
		self.facing = safeUnit(flatten(dir), self.facing)
	end
end

function Controller:CheckHomingHit()
	local target = self.homingTarget
	if target and (target.Position - self.position).Magnitude <= Config.HomingHitRadius then
		self:HomingHit(target)
	end
end

function Controller:HomingHit(target: BasePart)
	local side = safeUnit(flatten(target.Position - self.position), Vector3.zero)
	self.homingTarget = nil
	self.velocity = WORLD_UP * Config.HomingBounce + side * 12
	self.grounded = false
	self.groundPart = nil
	self.airDashed = false
	self.stomping = false
	self.ball = true
	self.attackTimer = 0.25
	self.airGrace = 0.1
	if self.onEnemyHit then
		self.onEnemyHit(target)
	end
end

-- True while touching an enemy should defeat it rather than hurt you.
function Controller:IsAttacking(): boolean
	return self.ball
		or self.rolling
		or self.charging
		or self.boosting
		or self.stomping
		or self.homingTarget ~= nil
		or self.attackTimer > 0
end

-- Defeated an enemy by touching it (jumping, rolling, boosting into it).
function Controller:BounceOff()
	if not self.grounded then
		self.velocity = Vector3.new(self.velocity.X, math.max(self.velocity.Y, Config.HomingBounce * 0.8), self.velocity.Z)
		self.airDashed = false
		self.stomping = false
	end
end

-- An enemy hit you: get knocked away and lose some heat.
function Controller:Hurt(from: Vector3)
	if self.hurtTimer > 0 then
		return
	end
	local away = safeUnit(flatten(self.position - from), nil) or -safeUnit(flatten(self.facing), Vector3.xAxis)
	self.velocity = away * Config.EnemyKnockback + WORLD_UP * 30
	self.position += WORLD_UP * 0.3
	self.grounded = false
	self.groundPart = nil
	self.rolling = false
	self.charging = false
	self.boosting = false
	self.ball = false
	self.homingTarget = nil
	self.airGrace = 0.2
	self.hurtTimer = Config.HurtInvulnerability
	self.heat = math.max(0, self.heat - Config.EnemyHeatLoss)
end

-- Sweep the body sphere along `motion`, sliding along walls and climbing onto
-- surfaces that are close enough in angle to the one we're on.
function Controller:MoveAndCollide(motion: Vector3)
	for _ = 1, 4 do
		local len = motion.Magnitude
		if len < 1e-4 then
			return
		end
		local up = if self.grounded then self.up else WORLD_UP
		local center = self.position + up * Config.BodyOffset
		local hit = Workspace:Spherecast(center, Config.BodyRadius, motion, self.rayParams)
		if not hit then
			self.position += motion
			return
		end

		local dir = motion / len
		local travel = math.max(0, hit.Distance - Config.Skin)
		self.position += dir * travel
		local rest = motion - dir * travel
		local nrm = hit.Normal

		if self.grounded and nrm:Dot(self.up) >= Config.TransitionMinDot then
			self:SetGround(nrm, hit.Instance)
			rest = safeUnit(projectOnPlane(rest, nrm), Vector3.zero) * rest.Magnitude
		elseif not self.grounded and nrm.Y >= Config.LandMinNormalY and self.velocity:Dot(nrm) < 0 then
			self:Land(nrm, hit.Instance)
			rest = projectOnPlane(rest, nrm)
		else
			local into = self.velocity:Dot(nrm)
			if into < 0 then
				self.velocity -= nrm * into
			end
			rest = projectOnPlane(rest, nrm)
			self.position += nrm * Config.Skin
		end
		motion = rest
	end
end

-- A sweep that starts touching a part doesn't see it, so running along a wall
-- that slowly angles into your path (the outside of a curve) can let the body
-- creep into it a little each step and come out the other side. Push the body
-- sphere back out of any wall-like block it overlaps.
function Controller:PushOutOfWalls()
	local up = if self.grounded then self.up else WORLD_UP
	local center = self.position + up * Config.BodyOffset
	local radius = Config.BodyRadius
	for _, part in Workspace:GetPartBoundsInRadius(center, radius, self.overlapParams) do
		if part:IsA("Part") and part.Shape == Enum.PartType.Block then
			local half = part.Size / 2
			local loc = part.CFrame:PointToObjectSpace(center)
			local closest = Vector3.new(
				math.clamp(loc.X, -half.X, half.X),
				math.clamp(loc.Y, -half.Y, half.Y),
				math.clamp(loc.Z, -half.Z, half.Z)
			)
			local away = loc - closest
			local dist = away.Magnitude
			if dist > 1e-4 and dist < radius then
				local nrm = part.CFrame:VectorToWorldSpace(away / dist)
				-- Walls only: floors and ceilings are handled by the ground probe
				if math.abs(nrm:Dot(up)) < 0.5 then
					self.position += nrm * (radius - dist + Config.Skin)
					center = self.position + up * Config.BodyOffset
					local into = self.velocity:Dot(nrm)
					if into < 0 then
						self.velocity -= nrm * into
					end
				end
			end
		end
	end
end

function Controller:ProbeGround(dt: number)
	local n = self.up
	local reach = self.hipHeight + Config.SnapDistance + self.velocity.Magnitude * dt * 0.5
	local hit = Workspace:Raycast(self.position + n, -n * (reach + 1), self.rayParams)
	if hit and hit.Normal:Dot(n) >= Config.SnapMinDot then
		self.position = hit.Position + hit.Normal * self.hipHeight
		self:SetGround(hit.Normal, hit.Instance)
		if self.up.Y < Config.SteepSurfaceY and self.velocity.Magnitude < Config.MinWallSpeed then
			self:Detach(true)
		end
	else
		self:Detach(false)
	end
end

function Controller:ProbeLanding(dt: number)
	if self.airGrace > 0 then
		return
	end
	local fall = math.max(0, -self.velocity.Y) * dt
	local hit = Workspace:Raycast(self.position + WORLD_UP, -WORLD_UP * (1 + self.hipHeight + fall + 0.05), self.rayParams)
	if hit and hit.Normal.Y >= Config.LandMinNormalY and self.velocity:Dot(hit.Normal) <= 0 then
		self.position = hit.Position + hit.Normal * self.hipHeight
		self:Land(hit.Normal, hit.Instance)
	end
end

-- Move onto a new ground surface keeping our speed (Sonic-style surface transitions).
function Controller:SetGround(n: Vector3, part: Instance?)
	if n ~= self.up then
		local speed = self.velocity.Magnitude
		self.velocity = safeUnit(projectOnPlane(self.velocity, n), Vector3.zero) * speed
	end
	self.up = n
	self.groundPart = part
	self.grounded = true
	self.lastGroundY = self.position.Y
end

-- Touch down from the air: the part of our velocity going into the surface is lost.
function Controller:Land(n: Vector3, part: Instance?)
	self.velocity = projectOnPlane(self.velocity, n)
	self.up = n
	self.groundPart = part
	self.grounded = true
	self.jumping = false
	self.ball = false
	self.airDashed = false
	if self.stomping or self.homingTarget then
		self.attackTimer = 0.15 -- a stomp still flattens whatever you land next to
	end
	self.stomping = false
	self.homingTarget = nil
	self.rolling = self.input.rollHeld and self.velocity.Magnitude >= Config.RollMinSpeed
end

function Controller:Detach(pushOff: boolean)
	if pushOff then
		self.velocity += self.up * Config.DetachPush
		self.position += self.up * 0.2
	end
	self.grounded = false
	self.groundPart = nil
	self.airGrace = 0.15
	self.rolling = false
end

function Controller:Respawn()
	self.position = self.spawnPosition + Vector3.new(0, 2, 0)
	self.velocity = Vector3.zero
	self.facing = self.spawnFacing
	self.up = WORLD_UP
	self.visualUp = WORLD_UP
	self.grounded = false
	self.groundPart = nil
	self.lastGroundY = nil
	self.rolling = false
	self.charging = false
	self.boosting = false
	self.ball = false
	self.airDashed = false
	self.stomping = false
	self.homingTarget = nil
	self.heat = 0
	self.respawnCount = (self.respawnCount or 0) + 1
end

function Controller:ResetToStart()
	self.spawnPosition = self.initialSpawnPosition
	self.spawnFacing = self.initialSpawnFacing
	self:Respawn()
end

-- Write our simulated state to the character. Called every frame before physics.
function Controller:Apply()
	local up = self.visualUp
	local fwd = safeUnit(projectOnPlane(self.facing, up), nil)
		or safeUnit(projectOnPlane(self.root.CFrame.LookVector, up), nil)
		or safeUnit(projectOnPlane(Vector3.xAxis, up), Vector3.zAxis)
	local right = fwd:Cross(up).Unit
	self.root.CFrame = CFrame.fromMatrix(self.position, right, up, -fwd)
	self.root.AssemblyLinearVelocity = self.velocity
	self.root.AssemblyAngularVelocity = Vector3.zero
end

return Controller
]=====])
script(f, 'ModuleScript', 'Hud', [=====[-- Speedometer, heat meter and a controls hint.

local Config = require(script.Parent.Config)

local Hud = {}
Hud.__index = Hud

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.fromRGB(255, 235, 210)
	l.TextStrokeTransparency = 0.4
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function Hud.new(playerGui: PlayerGui)
	local self = setmetatable({}, Hud)

	local old = playerGui:FindFirstChild("MomentumHud")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MomentumHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local panel = Instance.new("Frame")
	panel.BackgroundTransparency = 1
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 24, 1, -24)
	panel.Size = UDim2.fromOffset(340, 110)
	panel.Parent = gui

	self.speed = label(panel, { Text = "0", TextSize = 48, Size = UDim2.new(1, 0, 0, 50) })
	label(panel, {
		Text = "STUDS / SEC",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 16),
	})
	self.state = label(panel, {
		Text = "",
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 16),
		TextColor3 = Color3.fromRGB(255, 160, 80),
	})

	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 0, 1, -22)
	bar.Size = UDim2.new(1, 0, 0, 22)
	bar.BackgroundColor3 = Color3.fromRGB(35, 12, 10)
	bar.BorderSizePixel = 0
	bar.Parent = panel
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke", bar)
	stroke.Color = Color3.fromRGB(255, 120, 40)
	stroke.Thickness = 2
	self.barStroke = stroke

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)
	local gradient = Instance.new("UIGradient", fill)
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 20, 10)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 110, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 160)),
	})
	self.fill = fill

	-- Marker showing the minimum heat needed to start a boost
	local mark = Instance.new("Frame")
	mark.Size = UDim2.new(0, 2, 1, 0)
	mark.Position = UDim2.fromScale(Config.BoostMinHeat, 0)
	mark.BackgroundColor3 = Color3.fromRGB(255, 240, 200)
	mark.BackgroundTransparency = 0.3
	mark.BorderSizePixel = 0
	mark.Parent = bar

	self.heatLabel = label(bar, {
		Text = "HEAT",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	})

	label(gui, {
		Text = "WASD move   Space jump (in air: homing attack on a locked imp, or air dash)   Hold Q spin-dash / roll (in air: stomp)   Shift boost   Right-drag camera   R respawn",
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(16, 52),
		Size = UDim2.new(1, -32, 0, 18),
		TextTransparency = 0.15,
	})

	-- Tutorial stage prompt banner (top center, auto-hidden when no tutorial zone is active)
	local banner = Instance.new("Frame")
	banner.Name = "TutorialBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 78)
	banner.Size = UDim2.fromOffset(640, 56)
	banner.BackgroundColor3 = Color3.fromRGB(24, 10, 10)
	banner.BackgroundTransparency = 0.25
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = gui
	Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 8)
	local bannerStroke = Instance.new("UIStroke", banner)
	bannerStroke.Color = Color3.fromRGB(255, 115, 35)
	bannerStroke.Thickness = 1.5
	bannerStroke.Transparency = 0.25

	self.banner = banner
	self.bannerTitle = label(banner, {
		Text = "",
		TextSize = 15,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 175, 85),
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 20),
	})
	self.bannerHint = label(banner, {
		Text = "",
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 240, 225),
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -24, 0, 22),
	})

	-- Run timer & checkpoint counter (top right)
	local courseBox = Instance.new("Frame")
	courseBox.Name = "CourseStats"
	courseBox.AnchorPoint = Vector2.new(1, 0)
	courseBox.Position = UDim2.new(1, -24, 0, 78)
	courseBox.Size = UDim2.fromOffset(168, 56)
	courseBox.BackgroundColor3 = Color3.fromRGB(24, 10, 10)
	courseBox.BackgroundTransparency = 0.3
	courseBox.BorderSizePixel = 0
	courseBox.Visible = false
	courseBox.Parent = gui
	Instance.new("UICorner", courseBox).CornerRadius = UDim.new(0, 8)
	local courseStroke = Instance.new("UIStroke", courseBox)
	courseStroke.Color = Color3.fromRGB(255, 115, 35)
	courseStroke.Thickness = 1.5
	courseStroke.Transparency = 0.35

	self.courseBox = courseBox
	self.timerLabel = label(courseBox, {
		Text = "00:00.0",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 28),
	})
	self.cpLabel = label(courseBox, {
		Text = "CP 0 / 0",
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(120, 225, 255),
		Position = UDim2.fromOffset(10, 34),
		Size = UDim2.new(1, -20, 0, 16),
	})

	-- Checkpoint toast (below banner)
	self.toast = label(gui, {
		Text = "",
		TextSize = 20,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(80, 230, 255),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 144),
		Size = UDim2.fromOffset(560, 28),
		Visible = false,
	})

	-- Completion overlay (shown after crossing the Descent Gate)
	local complete = Instance.new("Frame")
	complete.Name = "TutorialComplete"
	complete.AnchorPoint = Vector2.new(0.5, 0.5)
	complete.Position = UDim2.fromScale(0.5, 0.42)
	complete.Size = UDim2.fromOffset(440, 176)
	complete.BackgroundColor3 = Color3.fromRGB(18, 10, 14)
	complete.BackgroundTransparency = 0.14
	complete.BorderSizePixel = 0
	complete.Visible = false
	complete.Parent = gui
	Instance.new("UICorner", complete).CornerRadius = UDim.new(0, 12)
	local completeStroke = Instance.new("UIStroke", complete)
	completeStroke.Color = Color3.fromRGB(50, 225, 255)
	completeStroke.Thickness = 2.5

	self.complete = complete
	label(complete, {
		Text = "TUTORIAL COMPLETE!",
		TextSize = 30,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(80, 230, 255),
		Position = UDim2.fromOffset(16, 18),
		Size = UDim2.new(1, -32, 0, 38),
	})
	self.completeStats = label(complete, {
		Text = "",
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 235, 210),
		Position = UDim2.fromOffset(16, 68),
		Size = UDim2.new(1, -32, 0, 52),
	})
	label(complete, {
		Text = "Press R to run the tutorial again",
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 175, 95),
		Position = UDim2.fromOffset(16, 134),
		Size = UDim2.new(1, -32, 0, 24),
	})

	gui.Parent = playerGui
	self.gui = gui
	self.t = 0
	return self
end

local function formatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = seconds - mins * 60
	return string.format("%02d:%04.1f", mins, secs)
end

function Hud:Update(ctrl, dt: number, tutorial)
	if not ctrl then
		return
	end
	self.t += dt
	local speed = ctrl.velocity.Magnitude
	self.speed.Text = tostring(math.floor(speed + 0.5))
	self.fill.Size = UDim2.fromScale(ctrl.heat, 1)

	local state
	if ctrl.hurtTimer > Config.HurtInvulnerability - 0.6 then
		state = "OUCH"
	elseif ctrl.homingTarget then
		state = "HOMING ATTACK"
	elseif ctrl.stomping then
		state = "STOMP"
	elseif ctrl.charging then
		state = string.format("CHARGING %d%%", math.floor(ctrl.spinCharge * 100))
	elseif ctrl.boosting then
		state = "BOOST"
	elseif ctrl.rolling then
		state = "ROLLING"
	elseif not ctrl.grounded then
		state = "AIR"
	elseif ctrl.up.Y < Config.SteepSurfaceY then
		state = "WALL RUN"
	else
		state = ""
	end
	self.state.Text = state

	local ready = ctrl.heat >= Config.BoostMinHeat
	self.heatLabel.Text = if ctrl.boosting then "HEAT  >> BOOSTING" elseif ready then "HEAT  (Shift to boost)" else "HEAT"
	local pulse = if ctrl.boosting then 0.5 + 0.5 * math.sin(self.t * 30) else 0
	self.barStroke.Color = Color3.fromRGB(255, 120, 40):Lerp(Color3.fromRGB(255, 245, 200), pulse)

	if tutorial and tutorial:HasCourse() then
		self.courseBox.Visible = true
		self.timerLabel.Text = formatTime(tutorial.elapsed)
		self.cpLabel.Text = string.format("CHECKPOINT %d / %d", tutorial.checkpointIndex, tutorial.totalCheckpoints)

		local showBanner = not tutorial.finished and tutorial.currentTitle ~= ""
		self.banner.Visible = showBanner
		if showBanner then
			self.bannerTitle.Text = tutorial.currentTitle
			self.bannerHint.Text = tutorial.currentHint
		end

		if tutorial.toastText and tutorial.toastTimer > 0 then
			self.toast.Visible = true
			self.toast.Text = tutorial.toastText
			local alpha = math.clamp(tutorial.toastTimer / 0.6, 0, 1)
			self.toast.TextTransparency = 1 - alpha
			self.toast.TextStrokeTransparency = 0.4 + 0.6 * (1 - alpha)
		else
			self.toast.Visible = false
		end

		self.complete.Visible = tutorial.finished
		if tutorial.finished then
			self.completeStats.Text = string.format(
				"TIME: %s\nTOP SPEED: %d STUDS / SEC",
				formatTime(tutorial.elapsed),
				math.floor(tutorial.peakSpeed + 0.5)
			)
		end
	else
		self.courseBox.Visible = false
		self.banner.Visible = false
		self.toast.Visible = false
		self.complete.Visible = false
	end
end

return Hud
]=====])
script(f, 'ModuleScript', 'InputState', [=====[-- Keyboard and gamepad input, collected into one table the controller reads.
--   Move: WASD / arrows / left stick
--   Jump (homing attack / air dash in the air): Space / A
--   Spin-dash & roll (stomp in the air): Q, LeftCtrl or C / X or B
--   Boost: LeftShift or E / R2 or Y
--   Respawn: R / Select

local UserInputService = game:GetService("UserInputService")

local InputState = {}
InputState.__index = InputState

local GAMEPAD = Enum.UserInputType.Gamepad1

local function anyKey(keys)
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function anyButton(buttons)
	for _, button in buttons do
		if UserInputService:IsGamepadButtonDown(GAMEPAD, button) then
			return true
		end
	end
	return false
end

function InputState.new()
	local self = setmetatable({}, InputState)
	self.state = {
		move = Vector2.zero,
		jumpHeld = false,
		jumpPressed = false,
		rollHeld = false,
		rollPressed = false,
		boostHeld = false,
	}
	self.stick = Vector2.zero
	self.respawnRequested = false

	UserInputService.InputBegan:Connect(function(io, processed)
		if processed then
			return
		end
		if io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.ButtonA then
			self.state.jumpPressed = true
		elseif
			io.KeyCode == Enum.KeyCode.Q
			or io.KeyCode == Enum.KeyCode.LeftControl
			or io.KeyCode == Enum.KeyCode.C
			or io.KeyCode == Enum.KeyCode.ButtonX
			or io.KeyCode == Enum.KeyCode.ButtonB
		then
			self.state.rollPressed = true
		elseif io.KeyCode == Enum.KeyCode.R or io.KeyCode == Enum.KeyCode.ButtonSelect then
			self.respawnRequested = true
		end
	end)

	UserInputService.InputChanged:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.Thumbstick1 then
			local p = Vector2.new(io.Position.X, io.Position.Y)
			self.stick = if p.Magnitude > 0.2 then p else Vector2.zero
		end
	end)

	return self
end

function InputState:Update()
	local s = self.state
	if UserInputService:GetFocusedTextBox() then
		s.move = Vector2.zero
		s.jumpHeld, s.rollHeld, s.boostHeld = false, false, false
		return
	end

	local x, y = 0, 0
	if anyKey({ Enum.KeyCode.W, Enum.KeyCode.Up }) then y += 1 end
	if anyKey({ Enum.KeyCode.S, Enum.KeyCode.Down }) then y -= 1 end
	if anyKey({ Enum.KeyCode.D, Enum.KeyCode.Right }) then x += 1 end
	if anyKey({ Enum.KeyCode.A, Enum.KeyCode.Left }) then x -= 1 end
	local move = Vector2.new(x, y)
	if move.Magnitude > 1 then
		move = move.Unit
	end
	if self.stick.Magnitude > move.Magnitude then
		move = self.stick
	end
	s.move = move

	s.jumpHeld = anyKey({ Enum.KeyCode.Space }) or anyButton({ Enum.KeyCode.ButtonA })
	s.rollHeld = anyKey({ Enum.KeyCode.Q, Enum.KeyCode.LeftControl, Enum.KeyCode.C })
		or anyButton({ Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonB })
	s.boostHeld = anyKey({ Enum.KeyCode.LeftShift, Enum.KeyCode.E })
		or anyButton({ Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonY })
end

return InputState
]=====])
script(f, 'ModuleScript', 'LockOn', [=====[-- Lock-on and enemy contact for the local player.
-- Every frame while airborne it picks the best enemy ahead of you (in range,
-- inside a cone around your heading, in line of sight) and puts a reticle on it.
-- Pressing jump then homes in (see Controller:StartHoming).
-- It also handles touching enemies: if you're attacking (curled up, rolling,
-- boosting, stomping, homing) the enemy is defeated, otherwise you get hurt.
--
-- Enemies are any BasePart tagged "HomingTarget" (EnemyService tags each enemy's core).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local TAG = "HomingTarget"

local LockOn = {}
LockOn.__index = LockOn

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function makeReticle(playerGui: PlayerGui)
	local gui = Instance.new("BillboardGui")
	gui.Name = "MomentumLockOn"
	gui.Size = UDim2.fromOffset(84, 84)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local spinner = Instance.new("Frame")
	spinner.Name = "Spinner"
	spinner.AnchorPoint = Vector2.new(0.5, 0.5)
	spinner.Position = UDim2.fromScale(0.5, 0.5)
	spinner.Size = UDim2.fromScale(1, 1)
	spinner.BackgroundTransparency = 1
	spinner.Parent = gui

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.72, 0.72)
	ring.BackgroundTransparency = 1
	ring.Parent = spinner
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke", ring)
	stroke.Color = Color3.fromRGB(255, 70, 40)
	stroke.Thickness = 3

	-- Four ticks pointing in at the target
	for i = 0, 3 do
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Size = UDim2.fromOffset(4, 16)
		tick.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
		tick.BorderSizePixel = 0
		local a = i * math.pi / 2
		tick.Position = UDim2.fromScale(0.5 + 0.47 * math.sin(a), 0.5 - 0.47 * math.cos(a))
		tick.Rotation = math.deg(a)
		tick.Parent = spinner
	end

	gui.Parent = playerGui
	return gui, spinner
end

function LockOn.new(ctrl, playerGui: PlayerGui)
	local self = setmetatable({}, LockOn)
	self.ctrl = ctrl
	self.gui, self.spinner = makeReticle(playerGui)
	self.defeated = {} -- parts we've defeated locally, waiting for the server to remove them
	self.lockedPart = nil
	self.t = 0

	ctrl.onEnemyHit = function(part)
		self:Defeat(part)
	end
	return self
end

function LockOn:IsAlive(part: BasePart): boolean
	return part:IsDescendantOf(Workspace) and not part:GetAttribute("Defeated") and not self.defeated[part]
end

function LockOn:FindTarget(): BasePart?
	local ctrl = self.ctrl
	local pos = ctrl.position
	local heading = flatten(ctrl.velocity)
	if heading.Magnitude < 5 then
		heading = flatten(ctrl.facing)
	end
	heading = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.xAxis

	local best, bestScore = nil, math.huge
	for _, part in CollectionService:GetTagged(TAG) do
		if part:IsA("BasePart") and self:IsAlive(part) then
			local to = part.Position - pos
			local dist = to.Magnitude
			if dist > 1 and dist <= Config.HomingRange then
				local flat = flatten(to)
				-- Straight below you counts as "ahead"
				local dot = if flat.Magnitude > 2 then flat.Unit:Dot(heading) else 1
				if dot >= Config.HomingConeDot then
					local hit = Workspace:Raycast(pos, to, ctrl.rayParams)
					if not hit or hit.Distance >= dist - 3 then
						local score = dist * (1.6 - dot)
						if score < bestScore then
							best, bestScore = part, score
						end
					end
				end
			end
		end
	end
	return best
end

-- Called every frame after the controller has moved.
function LockOn:Update(dt: number)
	local ctrl = self.ctrl
	self.t += dt

	-- Contact with enemies
	for _, part in CollectionService:GetTagged(TAG) do
		if part:IsA("BasePart") and self:IsAlive(part) then
			local reach = Config.EnemyContactRadius + part.Size.X / 2
			if (part.Position - ctrl.position).Magnitude <= reach then
				if ctrl:IsAttacking() then
					self:Defeat(part)
					ctrl:BounceOff()
				else
					ctrl:Hurt(part.Position)
				end
			end
		end
	end

	-- Lock-on (airborne only; keep the current target while homing)
	local target = nil
	if ctrl.homingTarget then
		target = ctrl.homingTarget
	elseif not ctrl.grounded then
		target = self:FindTarget()
	end
	ctrl.lockTarget = if ctrl.homingTarget then nil else target

	if target ~= self.lockedPart then
		self.lockedPart = target
		self.gui.Adornee = target
		if target then
			-- Snap-in: start big and shrink onto the target
			self.spinner.Size = UDim2.fromScale(1.8, 1.8)
			TweenService:Create(self.spinner, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
				Size = UDim2.fromScale(1, 1),
			}):Play()
		end
	end
	self.gui.Enabled = target ~= nil
	self.spinner.Rotation = (self.t * 180) % 360
end

local function burst(position: Vector3)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(255, 140, 40)
	ball.Size = Vector3.one * 2
	ball.Position = position
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Parent = Workspace
	local tween = TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * 12,
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		ball:Destroy()
	end)
end

function LockOn:Defeat(part: BasePart)
	if self.defeated[part] then
		return
	end
	self.defeated[part] = true
	burst(part.Position)

	-- Hide it right away on our screen; the server confirms and respawns it later.
	local model = part:FindFirstAncestorWhichIsA("Model") or part
	local remotes = ReplicatedStorage:FindFirstChild("MomentumRemotes")
	local remote = remotes and remotes:FindFirstChild("DefeatEnemy")
	if remote then
		remote:FireServer(part)
	end
	local parent = model.Parent
	model.Parent = nil
	task.delay(3, function()
		self.defeated[part] = nil
		-- If the server never confirmed (say we were too far away), put it back.
		if model.Parent == nil and not part:GetAttribute("Defeated") and parent and parent.Parent then
			model.Parent = parent
		end
	end)
end

function LockOn:Destroy()
	self.ctrl.onEnemyHit = nil
	self.ctrl.lockTarget = nil
	self.gui:Destroy()
end

return LockOn
]=====])
script(f, 'ModuleScript', 'RunCycle', [=====[-- Procedural, speed-driven run cycle for R15 and R6 characters.
-- Instead of playing a fixed animation, every frame this poses the joints
-- (the Transform of each Motor6D, or AnimationConstraint on newer avatars) from a gait cycle whose cadence, stride and posture all
-- follow the controller's speed:
--   standing  -> idle breathing
--   0-20      -> walk: short stride, relaxed arms, upright
--   20-90     -> run: long stride, high knee lift, pumping arms, forward lean, bounce
--   90+       -> sprint: deep lean, arms snapping forward and back, cadence keeps scaling with speed
--   90-200    -> overdrive: slightly longer stride and a deeper forward tilt above top speed
--   100-150   -> top speed: arms swept back behind the body, torso tipped well forward
-- In the air it blends to a fall pose. Tuning lives in Config (RunCycle* values).

local Config = require(script.Parent.Config)

local RunCycle = {}
RunCycle.__index = RunCycle

local JOINTS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftShoulder = "LeftUpperArm",
	RightShoulder = "RightUpperArm",
	LeftElbow = "LeftLowerArm",
	RightElbow = "RightLowerArm",
	LeftHip = "LeftUpperLeg",
	RightHip = "RightUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightKnee = "RightLowerLeg",
	LeftAnkle = "LeftFoot",
	RightAnkle = "RightFoot",
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.fromEulerAnglesXYZ(x, y, z)
end

-- R6 joints, each with the parent part it lives in
local R6_JOINTS = {
	RootJoint = "HumanoidRootPart",
	Neck = "Torso",
	["Left Shoulder"] = "Torso",
	["Right Shoulder"] = "Torso",
	["Left Hip"] = "Torso",
	["Right Hip"] = "Torso",
}

local function findJoint(parent: Instance?, name: string): Instance?
	local joint = parent and parent:FindFirstChild(name)
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return joint
	end
	return nil
end

-- Works on R15 and R6 rigs. Returns nil for rigs it can't drive, so the caller can fall back.
function RunCycle.new(character: Model)
	local motors = {}
	local r6 = false
	for name, partName in JOINTS do
		local joint = findJoint(character:FindFirstChild(partName), name)
		if not joint then
			motors = nil
			break
		end
		motors[name] = joint
	end
	if not motors then
		-- Try R6: same gait, mapped onto its six joints in Update
		motors = {}
		r6 = true
		for name, partName in R6_JOINTS do
			local joint = findJoint(character:FindFirstChild(partName), name)
			if not (joint and joint:IsA("Motor6D")) then
				return nil
			end
			motors[name] = joint
		end
	end
	local self = setmetatable({}, RunCycle)
	self.motors = motors
	self.r6 = r6
	if r6 then
		-- Each R6 joint's frame is rotated relative to its parts; poses are converted into it
		self.frames = {}
		for name, joint in motors do
			self.frames[name] = joint.C0.Rotation
		end
	end
	self.animator = character:FindFirstChildWhichIsA("Animator", true)
	self.phase = 0
	self.time = 0
	self.air = 0
	self.speed = 0
	self.weight = 0 -- fades the pose in after Reset (e.g. leaving the spin-ball)
	self.bank = 0 -- sideways lean into turns
	return self
end

-- Map the R15 pose onto R6. R6 has one torso part, so it takes the R15 root and
-- waist together, and the hips are countered by the waist so the legs still
-- swing from straight down. There are no knees or elbows, so those drop out.
function RunCycle:ToR6(pose)
	local torso = pose.Root * pose.Waist
	local waistInv = pose.Waist.Rotation:Inverse()
	local r6 = {
		RootJoint = torso,
		Neck = pose.Neck,
		["Left Shoulder"] = pose.LeftShoulder,
		["Right Shoulder"] = pose.RightShoulder,
		["Left Hip"] = waistInv * pose.LeftHip,
		["Right Hip"] = waistInv * pose.RightHip,
	}
	-- Poses are in the parts' own axes; express them in each joint's frame
	for name, cf in r6 do
		local f = self.frames[name]
		r6[name] = f:Inverse() * cf * f
	end
	return r6
end

-- Target pose for every joint, from the gait at this speed.
function RunCycle:Pose(speed: number, grounded: boolean, verticalSpeed: number)
	local C = Config
	local t = self.time
	local pose = {}

	-- Blend weights
	local move = smooth(speed / C.RunCycleWalkSpeed) -- 0 standing, 1 walking
	local run = smooth((speed - C.RunCycleWalkSpeed) / (C.RunCycleRunSpeed - C.RunCycleWalkSpeed))
	local sprint = smooth((speed - C.RunCycleSprintSpeed) / C.RunCycleSprintBlend)
	-- Overdrive: past running top speed (boosts, slopes) the same gait stretches a little
	-- further so it keeps up: longer stride, faster steps and a deeper forward tilt (arms unchanged)
	local od = self:Overdrive(speed)
	local stretch = 1 + C.RunCycleOverdriveStride * od

	local s = math.sin(self.phase)
	local c = math.cos(self.phase)

	-- Cartoon factor: walking stays natural, running and sprinting get pushed further
	local x = lerp(1, C.RunCycleExaggeration, run)

	-- Legs: hips swing opposite each other; the knee folds while that leg swings forward.
	-- The forward swing is bigger than the back swing, for high cartoon knees.
	local hipAmp = (lerp(0.45, 0.95, run) + 0.15 * sprint) * x * stretch
	local kneeAmp = (lerp(0.55, 1.7, run) + 0.3 * sprint) * x * stretch
	local function hip(v: number): number
		return if v > 0 then math.min(1.7, v * lerp(1, 1.3, run)) else v
	end
	local hipL = hip(s * hipAmp) * move
	local hipR = hip(-s * hipAmp) * move
	local kneeL = -math.min(2.6, 0.08 + kneeAmp * math.max(0, c)) * move
	local kneeR = -math.min(2.6, 0.08 + kneeAmp * math.max(0, -c)) * move
	local ankleL = (0.25 * s - 0.2 * run * x * math.max(0, -c)) * move
	local ankleR = (-0.25 * s - 0.2 * run * x * math.max(0, c)) * move

	-- Arms: one thrust forward while the other is flung back, snapping between the two in
	-- time with the stride (they hold each pose and switch quickly), and floating a little
	-- away from the shoulders, cartoon style
	local armAmp = lerp(0.35, 1.1, run) * x * move
	local snap = math.sign(s) * math.abs(s) ^ lerp(1, C.RunCycleArmSnap, run)
	local shoulderLX = -snap * armAmp
	local shoulderRX = snap * armAmp
	local shoulderOut = lerp(0.08, 0.32, run) * move
	local detach = C.RunCycleArmDetach * run * move
	local elbowL = lerp(lerp(0.15, 1.5, run) * move + 0.1, 0.25, sprint) * lerp(1, 1.15, run * (x - 1))
	local elbowR = elbowL

	-- Torso: lean into speed, twist against the hips, bounce on each footfall,
	-- and rock the hips side to side
	local lean = -(lerp(0.04, C.RunCycleRunLean, run) * move + 0.10 * sprint + C.RunCycleOverdriveLean * od) * x
	local twist = 0.18 * s * run * (1 - 0.5 * sprint) * x
	local bounce = (math.abs(c) - 0.5) * lerp(0.08, 0.35, run) * x * x * move
	local sway = 0.08 * s * run * (x - 1) * 2
	local breathe = (1 - move) * 0.03 * math.sin(t * 2.2)

	-- The whole body banks into turns like a bike, more the faster and tighter the turn
	pose.Root = CFrame.new(0, bounce, 0) * rot(0, -twist * 0.5, sway + self.bank * move)
	pose.Waist = rot(lean + breathe, twist, -sway * 0.6)
	pose.Neck = rot(-lean * 0.7 - breathe, -twist * 0.8, 0)
	-- Detached arms slide toward where they point: forward arm out in front, back arm behind
	pose.LeftShoulder = CFrame.new(0, -0.15 * detach, snap * detach) * rot(0, 0, -shoulderOut) * rot(shoulderLX, 0, 0)
	pose.RightShoulder = CFrame.new(0, -0.15 * detach, -snap * detach) * rot(0, 0, shoulderOut) * rot(shoulderRX, 0, 0)
	pose.LeftElbow = rot(elbowL, 0, 0)
	pose.RightElbow = rot(elbowR, 0, 0)
	pose.LeftHip = rot(hipL, 0, 0)
	pose.RightHip = rot(hipR, 0, 0)
	pose.LeftKnee = rot(kneeL, 0, 0)
	pose.RightKnee = rot(kneeR, 0, 0)
	pose.LeftAnkle = rot(ankleL, 0, 0)
	pose.RightAnkle = rot(ankleR, 0, 0)

	-- Air: arms out for balance, one knee tucked, flail a little while falling
	local a = self.air
	if a > 0.001 then
		local falling = math.clamp(-verticalSpeed / 60, 0, 1)
		local flail = 0.15 * falling * math.sin(t * 14)
		local air = {
			Root = CFrame.identity,
			Waist = rot(-0.1, 0, 0),
			Neck = rot(0.15, 0, 0),
			LeftShoulder = rot(0.3 + flail, 0, -1.2),
			RightShoulder = rot(0.3 - flail, 0, 1.2),
			LeftElbow = rot(0.5, 0, 0),
			RightElbow = rot(0.5, 0, 0),
			LeftHip = rot(0.7, 0, 0),
			RightHip = rot(-0.25, 0, 0),
			LeftKnee = rot(-1.2, 0, 0),
			RightKnee = rot(-0.4, 0, 0),
			LeftAnkle = rot(0.2, 0, 0),
			RightAnkle = rot(0.2, 0, 0),
		}
		for name, cf in pose do
			pose[name] = cf:Lerp(air[name], a)
		end
	end

	return pose
end

-- 0 at running top speed, 1 at RunCycleOverdriveSpeed and above
function RunCycle:Overdrive(speed: number): number
	local C = Config
	return smooth((speed - C.TopSpeed) / math.max(1, C.RunCycleOverdriveSpeed - C.TopSpeed))
end

-- Top speed (boosts, slopes): the arms sweep back behind the body and the torso
-- tips further forward, blended in by k (0 = normal run, 1 = full top-speed pose)
function RunCycle:ApplyTopSpeed(pose, k: number)
	local C = Config
	local lean = C.RunCycleTopLean * k
	local back = C.RunCycleTopArmBack + 0.06 * math.sin(self.phase * 2)
	local out = C.RunCycleTopArmOut
	local armL = rot(0, 0, -out) * rot(-back, 0, 0)
	local armR = rot(0, 0, out) * rot(-back, 0, 0)
	if self.r6 then
		-- Poses here are already in each R6 joint's frame
		local function conv(name: string, cf: CFrame): CFrame
			local f = self.frames[name]
			return f:Inverse() * cf * f
		end
		pose.RootJoint = conv("RootJoint", rot(-lean, 0, 0)) * pose.RootJoint
		pose.Neck = conv("Neck", rot(lean * 0.7, 0, 0)) * pose.Neck
		-- The legs hang from the torso, so tip them back the other way to keep them under him
		pose["Left Hip"] = conv("Left Hip", rot(lean, 0, 0)) * pose["Left Hip"]
		pose["Right Hip"] = conv("Right Hip", rot(lean, 0, 0)) * pose["Right Hip"]
		pose["Left Shoulder"] = pose["Left Shoulder"]:Lerp(conv("Left Shoulder", armL), k)
		pose["Right Shoulder"] = pose["Right Shoulder"]:Lerp(conv("Right Shoulder", armR), k)
	else
		pose.Waist = rot(-lean, 0, 0) * pose.Waist
		pose.Neck = rot(lean * 0.7, 0, 0) * pose.Neck
		pose.LeftShoulder = pose.LeftShoulder:Lerp(armL, k)
		pose.RightShoulder = pose.RightShoulder:Lerp(armR, k)
		pose.LeftElbow = pose.LeftElbow:Lerp(rot(0.15, 0, 0), k)
		pose.RightElbow = pose.RightElbow:Lerp(rot(0.15, 0, 0), k)
	end
end

-- turnRate: how fast the heading is turning, radians per second (positive = left)
function RunCycle:Update(dt: number, speed: number, grounded: boolean, verticalSpeed: number, turnRate: number?)
	self.time += dt
	local C = Config
	-- Smooth the speed (not the pose) so gait changes ease in without damping the swing
	self.speed += (speed - self.speed) * (1 - math.exp(-C.RunCycleSmoothing * dt))
	local bank = math.clamp((turnRate or 0) * speed * C.RunCycleBank, -C.RunCycleBankMax, C.RunCycleBankMax)
	self.bank += (bank - self.bank) * (1 - math.exp(-8 * dt))
	speed = self.speed
	-- Cadence scales directly with speed so the animation speeds up in step with movement
	local cadence = math.min(
		C.RunCycleMaxCadence,
		C.RunCycleMinCadence + speed * C.RunCycleCadencePerSpeed
	)
	if grounded and speed > 0.1 then
		self.phase = (self.phase + dt * cadence * 2 * math.pi) % (2 * math.pi)
	end
	self.air += ((if grounded then 0 else 1) - self.air) * (1 - math.exp(-10 * dt))

	-- Anything the Animator is still playing (avatar idles, emotes) would fight us
	if self.animator then
		for _, track in self.animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end

	self.weight += (1 - self.weight) * (1 - math.exp(-10 * dt))
	local pose = self:Pose(speed, grounded, verticalSpeed)
	if self.r6 then
		pose = self:ToR6(pose)
	end
	-- Past normal running speed, blend into the arms-back top-speed pose
	local top = smooth((speed - C.RunCycleTopStart) / (C.RunCycleTopFull - C.RunCycleTopStart)) * (1 - self.air)
	if top > 0.001 then
		self:ApplyTopSpeed(pose, top)
	end
	for name, joint in self.motors do
		joint.Transform = CFrame.identity:Lerp(pose[name], self.weight)
	end
end

-- Clear the pose (e.g. while curled into the spin-ball); it fades back in afterwards.
function RunCycle:Reset()
	self.weight = 0
	for _, joint in self.motors do
		joint.Transform = CFrame.identity
	end
end

return RunCycle
]=====])
script(f, 'ModuleScript', 'TutorialTracker', [=====[-- Client-side tracker for the tutorial level's stage zones, checkpoints,
-- run timer, and finish gate. Uses direct bounding-box checks against the
-- controller's position so fast movement never skips a trigger.

local Workspace = game:GetService("Workspace")

local LEVEL_NAME = "HellTestLevel"
local COLOR_IDLE = Color3.fromRGB(255, 110, 30)
local COLOR_ACTIVE = Color3.fromRGB(30, 220, 255)

local TutorialTracker = {}
TutorialTracker.__index = TutorialTracker

local function insideBox(part: BasePart, point: Vector3): boolean
	local rel = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function collectGlows(container: Instance): { BasePart }
	local list = {}
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("GlowAccent") then
			table.insert(list, d)
		end
	end
	return list
end

local function setGlowColor(glows: { BasePart }, color: Color3)
	for _, p in glows do
		if p.Parent then
			p.Color = color
		end
	end
end

function TutorialTracker.new(ctrl)
	local self = setmetatable({}, TutorialTracker)
	self.ctrl = ctrl
	self.level = nil
	self.zones = {}
	self.checkpoints = {}
	self.goal = nil

	self.started = false
	self.finished = false
	self.elapsed = 0
	self.peakSpeed = 0
	self.checkpointIndex = 0
	self.totalCheckpoints = 0
	self.currentTitle = ""
	self.currentHint = ""
	self.toastText = nil
	self.toastTimer = 0

	self:BindLevel()
	return self
end

function TutorialTracker:BindLevel()
	local level = Workspace:FindFirstChild(LEVEL_NAME)
	if not level or level == self.level then
		return
	end
	self.level = level
	self.zones = {}
	self.checkpoints = {}
	self.goal = nil

	local zonesFolder = level:FindFirstChild("TutorialZones")
	if zonesFolder then
		for _, child in zonesFolder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(self.zones, {
					part = child,
					title = child:GetAttribute("ZoneTitle") or "",
					hint = child:GetAttribute("ZoneHint") or "",
					order = child:GetAttribute("ZoneOrder") or 0,
				})
			end
		end
		table.sort(self.zones, function(a, b)
			return a.order < b.order
		end)
	end

	local cpFolder = level:FindFirstChild("Checkpoints")
	if cpFolder then
		for _, child in cpFolder:GetChildren() do
			local trigger = child:FindFirstChild("Trigger")
			if trigger and trigger:IsA("BasePart") then
				table.insert(self.checkpoints, {
					folder = child,
					trigger = trigger,
					index = child:GetAttribute("CheckpointIndex") or 0,
					label = child:GetAttribute("CheckpointLabel") or "",
					glows = collectGlows(child),
					reached = false,
				})
			end
		end
		table.sort(self.checkpoints, function(a, b)
			return a.index < b.index
		end)
	end
	self.totalCheckpoints = #self.checkpoints

	local goalFolder = level:FindFirstChild("GoalGate")
	if goalFolder then
		local trigger = goalFolder:FindFirstChild("Trigger")
		if trigger and trigger:IsA("BasePart") then
			self.goal = {
				folder = goalFolder,
				trigger = trigger,
				glows = collectGlows(goalFolder),
			}
		end
	end
end

-- Bind again if more zones or checkpoints have streamed in, keeping progress
function TutorialTracker:Rescan()
	local level = self.level
	local zones = level:FindFirstChild("TutorialZones")
	local cps = level:FindFirstChild("Checkpoints")
	local goal = level:FindFirstChild("GoalGate")
	local nCps = 0
	if cps then
		for _, child in cps:GetChildren() do
			if child:FindFirstChild("Trigger") then
				nCps += 1
			end
		end
	end
	local nZones = if zones then #zones:GetChildren() else 0
	local hasGoal = goal ~= nil and goal:FindFirstChild("Trigger") ~= nil
	if nZones == #self.zones and nCps == #self.checkpoints and hasGoal == (self.goal ~= nil) then
		return
	end
	local reached = {}
	for _, cp in self.checkpoints do
		if cp.reached then
			reached[cp.index] = true
		end
	end
	self.level = nil
	self:BindLevel()
	for _, cp in self.checkpoints do
		if reached[cp.index] then
			cp.reached = true
			setGlowColor(cp.glows, COLOR_ACTIVE)
		end
	end
end

function TutorialTracker:HasCourse(): boolean
	return #self.zones > 0 or self.totalCheckpoints > 0 or self.goal ~= nil
end

function TutorialTracker:Update(dt: number)
	if not self.level or not self.level.Parent then
		self.level = nil
		self:BindLevel()
	end
	if not self.level then
		return
	end
	-- With streaming on, parts of the course can arrive after we first bound to it
	self.rescanTimer = (self.rescanTimer or 0) - dt
	if self.rescanTimer <= 0 then
		self.rescanTimer = 1
		self:Rescan()
	end

	local ctrl = self.ctrl
	local pos = ctrl.position
	local speed = ctrl:GetSpeed()

	if not self.finished then
		if not self.started and speed > 2 then
			self.started = true
		end
		if self.started then
			self.elapsed += dt
		end
		if speed > self.peakSpeed then
			self.peakSpeed = speed
		end
	end

	if self.toastTimer > 0 then
		self.toastTimer = math.max(0, self.toastTimer - dt)
		if self.toastTimer == 0 then
			self.toastText = nil
		end
	end

	-- Update active tutorial stage prompt
	for _, z in self.zones do
		if z.part.Parent and insideBox(z.part, pos) then
			self.currentTitle = z.title
			self.currentHint = z.hint
			break
		end
	end

	-- Checkpoints
	for _, cp in self.checkpoints do
		if not cp.reached and cp.trigger.Parent and insideBox(cp.trigger, pos) then
			cp.reached = true
			setGlowColor(cp.glows, COLOR_ACTIVE)
			if cp.index > self.checkpointIndex then
				self.checkpointIndex = cp.index
				local spawnPos = cp.trigger:GetAttribute("SpawnPosition")
				if typeof(spawnPos) ~= "Vector3" then
					spawnPos = cp.trigger.Position
				end
				ctrl:SetCheckpoint(spawnPos, cp.trigger.CFrame.LookVector)
				local suffix = if cp.label ~= "" then " — " .. cp.label else ""
				self.toastText = string.format("CHECKPOINT %d / %d%s", cp.index, self.totalCheckpoints, suffix)
				self.toastTimer = 2.6
			end
		end
	end

	-- Finish gate
	if self.goal and not self.finished and self.goal.trigger.Parent and insideBox(self.goal.trigger, pos) then
		self.finished = true
		setGlowColor(self.goal.glows, COLOR_ACTIVE)
		self.toastText = nil
		self.toastTimer = 0
	end
end

function TutorialTracker:Reset()
	self.started = false
	self.finished = false
	self.elapsed = 0
	self.peakSpeed = 0
	self.checkpointIndex = 0
	self.toastText = nil
	self.toastTimer = 0

	for _, cp in self.checkpoints do
		cp.reached = false
		setGlowColor(cp.glows, COLOR_IDLE)
	end
	if self.goal then
		setGlowColor(self.goal.glows, COLOR_IDLE)
	end

	self.ctrl:ResetToStart()
end

return TutorialTracker
]=====])
end
do local f = put(game:GetService('ServerScriptService'), 'MomentumServer')
script(f, 'ModuleScript', 'AshBuilder', [=====[-- Builds Ash, the playable main character, on the standard Roblox R6 rig
-- (Head, Torso, two arms, two legs), kept simple to match the game's art style.
-- His look comes from colors plus a few small touches:
--   * a bright body color that contrasts with the lava levels (Config.AshBodyColor)
--   * glowing orange circle eyes that change expression (AshFace)
--   * a red scarf knot around the neck (AshFx streams the tail behind him)
--
-- The rig uses the standard R6 part and joint names, so the run cycle (which
-- drives R6 joints too), spin-ball and afterimages work on it.
--
-- Decoration parts are named so the client can find them:
--   AshScarfKnot  the scarf around the neck (the tail hangs off its back)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Momentum = ReplicatedStorage:WaitForChild("Momentum")
local Config = require(Momentum:WaitForChild("Config"))
local AshFace = require(Momentum:WaitForChild("AshFace"))

local AshBuilder = {}

local SCARF = Color3.fromRGB(165, 24, 22)

-- Standard R6 sizes and positions, with the HumanoidRootPart's center at the origin
local BODY = {
	HumanoidRootPart = { Vector3.new(2, 2, 1), Vector3.new(0, 0, 0) },
	Torso = { Vector3.new(2, 2, 1), Vector3.new(0, 0, 0) },
	Head = { Vector3.new(2, 1, 1), Vector3.new(0, 1.5, 0) },
	["Left Arm"] = { Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0) },
	["Right Arm"] = { Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0) },
	["Left Leg"] = { Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0) },
	["Right Leg"] = { Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0) },
}

-- The standard R6 Motor6Ds: name = { parent, child, C0, C1 }
local JOINTS = {
	RootJoint = {
		"HumanoidRootPart", "Torso",
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	},
	Neck = {
		"Torso", "Head",
		CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	},
	["Right Shoulder"] = {
		"Torso", "Right Arm",
		CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	},
	["Left Shoulder"] = {
		"Torso", "Left Arm",
		CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	},
	["Right Hip"] = {
		"Torso", "Right Leg",
		CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	},
	["Left Hip"] = {
		"Torso", "Left Leg",
		CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	},
}

local function bodyPart(name: string, size: Vector3, center: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(center)
	p.Color = Config.AshBodyColor
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	return p
end

-- A small decoration welded onto a body part. cf is relative to that part.
local function deco(body: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, neon: boolean?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = body.CFrame * cf
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = not neon
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	p.Parent = body
	return p
end

local function addLooks(parts)
	local head, torso = parts.Head, parts.Torso

	-- Classic R6 head shape
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head

	-- Orange circle eyes (expressions are driven on the client by AshFx)
	AshFace.Build(head)

	-- Red scarf knot around the neck
	deco(torso, "AshScarfKnot", Vector3.new(1.3, 0.3, 1.1), CFrame.new(0, 0.92, 0), SCARF)
end

-- Returns a fresh Ash model, ready to be used as StarterPlayer.StarterCharacter.
function AshBuilder.Build(): Model
	local model = Instance.new("Model")
	model.Name = "StarterCharacter"

	local parts = {}
	for name, spec in BODY do
		local p = bodyPart(name, spec[1], spec[2])
		parts[name] = p
		p.Parent = model
	end
	local root = parts.HumanoidRootPart
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root

	for name, spec in JOINTS do
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = parts[spec[1]]
		motor.Part1 = parts[spec[2]]
		motor.C0 = spec[3]
		motor.C1 = spec[4]
		motor.Parent = parts[spec[1]]
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	addLooks(parts)

	model:SetAttribute("AshCharacter", true)
	return model
end

return AshBuilder
]=====])
script(f, 'Script', 'AshCharacter', [=====[-- Makes Ash the character everyone plays as: builds him once at server start,
-- installs him as StarterPlayer.StarterCharacter, and (re)spawns anyone who
-- loaded in before he was ready.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local AshBuilder = require(script.Parent:WaitForChild("AshBuilder"))

local old = StarterPlayer:FindFirstChild("StarterCharacter")
if old then
	old:Destroy()
end
local ash = AshBuilder.Build()
ash.Parent = StarterPlayer

-- Anyone who spawned as their own avatar before Ash existed gets respawned as him
for _, player in Players:GetPlayers() do
	local character = player.Character
	if character and not character:GetAttribute("AshCharacter") then
		player:LoadCharacter()
	end
end
]=====])
script(f, 'Script', 'BuildTestLevel', [=====[-- Builds the test level when the server starts, unless one is already in Workspace
-- (for example because you generated it in Edit mode to look at or tweak).
require(script.Parent:WaitForChild("LevelBuilder")).Build()
]=====])
script(f, 'Script', 'EnemyService', [=====[-- Spawns enemies ("Cinder Imps": floating horned embers) at every part named
-- "EnemySpawn" in the level, bobs and patrols them, and handles defeats.
-- Each imp's "Core" part is tagged "HomingTarget", which is what the client's
-- lock-on looks for. Defeated imps respawn after a few seconds.
--
-- EnemySpawn attributes (all optional):
--   Patrol (Vector3): the imp drifts back and forth by this offset
--   PatrolSpeed (number): radians per second of the patrol swing

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local TAG = "HomingTarget"
local RESPAWN_SECONDS = 8
local MAX_HIT_DISTANCE = 45 -- generous, to allow for network lag at high speed

local remotes = ReplicatedStorage:FindFirstChild("MomentumRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "MomentumRemotes"
	remotes.Parent = ReplicatedStorage
end
local defeatRemote = remotes:FindFirstChild("DefeatEnemy") or Instance.new("RemoteEvent")
defeatRemote.Name = "DefeatEnemy"
defeatRemote.Parent = remotes

local folder = Instance.new("Folder")
folder.Name = "Enemies"
folder.Parent = Workspace

local function piece(model: Model, props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false -- the controller's ray and sphere casts ignore enemies
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Parent = model
	return p
end

local function buildImp(): Model
	local model = Instance.new("Model")
	model.Name = "CinderImp"

	local core = piece(model, {
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3.6,
		Material = Enum.Material.Basalt,
		Color = Color3.fromRGB(60, 24, 20),
	})
	model.PrimaryPart = core
	local cf = core.CFrame

	-- Molten eye, horns, little bat wings
	piece(model, {
		Name = "Eye",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.5,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 150, 40),
		CFrame = cf * CFrame.new(0, 0.3, -1.25),
	})
	for _, side in { -1, 1 } do
		piece(model, {
			Name = "Horn",
			Size = Vector3.new(0.5, 1.6, 0.5),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(200, 40, 20),
			CFrame = cf * CFrame.new(0.9 * side, 1.7, 0) * CFrame.Angles(0, 0, -0.45 * side),
		})
		piece(model, {
			Name = "Wing",
			Size = Vector3.new(2.6, 0.2, 1.5),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(90, 20, 20),
			CFrame = cf * CFrame.new(2.4 * side, 0.4, 0.4) * CFrame.Angles(0, 0, 0.35 * side),
		})
	end

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 110, 40)
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = core

	CollectionService:AddTag(core, TAG)
	return model
end

local enemies = {} -- [core] = enemy record

local function spawnAt(marker: BasePart)
	local model = buildImp()
	local enemy = {
		model = model,
		core = model.PrimaryPart,
		origin = marker.Position,
		patrol = marker:GetAttribute("Patrol") or Vector3.zero,
		patrolSpeed = marker:GetAttribute("PatrolSpeed") or 1,
		seed = math.random() * 10,
		alive = true,
	}
	model:PivotTo(CFrame.new(enemy.origin))
	model.Parent = folder
	enemies[enemy.core] = enemy
end

local function spawnAll()
	local level = Workspace:WaitForChild("HellTestLevel", 30)
	if not level then
		warn("[Momentum] no HellTestLevel found; no enemies spawned")
		return
	end
	for _, d in level:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "EnemySpawn" then
			spawnAt(d)
		end
	end
end

defeatRemote.OnServerEvent:Connect(function(player: Player, core)
	if typeof(core) ~= "Instance" then
		return
	end
	local enemy = enemies[core]
	if not enemy or not enemy.alive then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - core.Position).Magnitude > MAX_HIT_DISTANCE then
		return
	end

	enemy.alive = false
	core:SetAttribute("Defeated", true)
	enemy.model.Parent = ServerStorage
	task.delay(RESPAWN_SECONDS, function()
		core:SetAttribute("Defeated", false)
		enemy.alive = true
		enemy.model.Parent = folder
	end)
end)

-- Hover, bob and patrol
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, enemy in enemies do
		if enemy.alive then
			local swing = math.sin(t * enemy.patrolSpeed + enemy.seed)
			local bob = math.sin(t * 2.3 + enemy.seed) * 0.6
			local pos = enemy.origin + enemy.patrol * swing + Vector3.new(0, bob, 0)
			-- Face along the patrol (or slowly spin if it doesn't patrol)
			local heading
			if enemy.patrol.Magnitude > 0.1 then
				local vel = enemy.patrol * math.cos(t * enemy.patrolSpeed + enemy.seed)
				heading = if vel.Magnitude > 0.05 then vel.Unit else enemy.patrol.Unit
			else
				local a = t * 0.8 + enemy.seed
				heading = Vector3.new(math.sin(a), 0, math.cos(a))
			end
			local flat = Vector3.new(heading.X, 0, heading.Z)
			if flat.Magnitude < 0.05 then
				flat = Vector3.zAxis
			end
			enemy.model:PivotTo(CFrame.lookAt(pos, pos + flat))
		end
	end
end)

spawnAll()
]=====])
script(f, 'ModuleScript', 'LevelBuilder', [=====[-- Procedurally builds "Circle 0: The Descent Gate", the tutorial level: a long,
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
				newPart(folder, deco({
					Name = "Cliff",
					Size = Vector3.new(THICK, height, SPACING + 10),
					CFrame = cf,
					Color = if rng:NextNumber() < 0.5 then COLOR.rock else COLOR.pillar,
				}))
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
	buildScenery(level, minC - Vector3.new(pad, 0, pad), maxC + Vector3.new(pad, 0, pad), routePts, floorY)
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
]=====])
script(f, 'Script', 'PlayerSetup', [=====[-- Server side of the momentum controller: characters go in a collision group that
-- doesn't physically collide with the world (the client controller does its own
-- collision with sphere and ray casts), and shift-lock is turned off so Shift can boost.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage:WaitForChild("Momentum"):WaitForChild("Config"))
local GROUP = Config.CollisionGroup

pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP)
end)
PhysicsService:CollisionGroupSetCollidable(GROUP, "Default", false)
PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)

StarterPlayer.EnableMouseLockOption = false

local function tag(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = GROUP
	end
end

local function onCharacter(character: Model)
	for _, d in character:GetDescendants() do
		tag(d)
	end
	character.DescendantAdded:Connect(tag)
end

local function onPlayer(player: Player)
	player.DevEnableMouseLock = false
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
]=====])
end
do local f = put(game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts'), 'MomentumClient')
script(f, 'LocalScript', 'MomentumClient', [=====[-- Boots the momentum controller for the local player's character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Momentum = ReplicatedStorage:WaitForChild("Momentum")
local Controller = require(Momentum:WaitForChild("Controller"))
local ChaseCamera = require(Momentum:WaitForChild("ChaseCamera"))
local Hud = require(Momentum:WaitForChild("Hud"))
local CharacterFx = require(Momentum:WaitForChild("CharacterFx"))
local InputState = require(Momentum:WaitForChild("InputState"))
local LockOn = require(Momentum:WaitForChild("LockOn"))
local TutorialTracker = require(Momentum:WaitForChild("TutorialTracker"))

local player = Players.LocalPlayer

-- Turn off the default movement controls if the classic PlayerModule is present.
-- (Our Humanoid sits in the Physics state, so default input can't move it anyway.)
local function disableDefaultControls()
	task.spawn(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
		if not playerModule then
			return
		end
		local ok, err = pcall(function()
			require(playerModule):GetControls():Disable()
		end)
		if not ok then
			warn("[Momentum] could not disable default controls:", err)
		end
	end)
end

local input = InputState.new()
local hud = Hud.new(player:WaitForChild("PlayerGui"))
local camera = ChaseCamera.new()
local active = nil

local function stop()
	if active then
		active.fx:Destroy()
		active.lockOn:Destroy()
		active = nil
	end
end

-- Characters don't always spawn facing the way their SpawnLocation points, so
-- start the controller (and camera) looking down the spawn's front instead.
local function nearestSpawn(position: Vector3): SpawnLocation?
	local best, bestDist = nil, 30
	for _, d in Workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and d.Enabled then
			local dist = (d.Position - position).Magnitude
			if dist < bestDist then
				best, bestDist = d, dist
			end
		end
	end
	return best
end

local function onCharacter(character: Model)
	stop()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	if not character:IsDescendantOf(Workspace) then
		character.AncestryChanged:Wait()
	end
	task.wait() -- let the spawn position settle

	disableDefaultControls()
	for _, state in Enum.HumanoidStateType:GetEnumItems() do
		if
			state ~= Enum.HumanoidStateType.Physics
			and state ~= Enum.HumanoidStateType.Dead
			and state ~= Enum.HumanoidStateType.None
		then
			pcall(humanoid.SetStateEnabled, humanoid, state, false)
		end
	end
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	local ctrl = Controller.new(character, humanoid, root)
	ctrl.input = input.state
	local spawn = nearestSpawn(root.Position)
	if spawn then
		ctrl:SetFacing(spawn.CFrame.LookVector)
	end
	local fx = CharacterFx.new(character, humanoid, root, ctrl)
	ctrl:AddIgnore(fx.ball)
	camera:Attach(ctrl, { character, fx.ball })

	local lockOn = LockOn.new(ctrl, player:WaitForChild("PlayerGui"))
	local tutorial = TutorialTracker.new(ctrl)

	active = { ctrl = ctrl, fx = fx, lockOn = lockOn, tutorial = tutorial, character = character }
	humanoid.Died:Connect(function()
		if active and active.character == character then
			stop()
		end
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- Simulation runs right before physics so the root CFrame we write is what renders.
local preSimulation = RunService.PreSimulation or RunService.Stepped
preSimulation:Connect(function(a, b)
	local dt = if typeof(b) == "number" then b else a
	if not active then
		return
	end
	input:Update()
	local ctrl = active.ctrl
	if input.respawnRequested then
		input.respawnRequested = false
		if active.tutorial and active.tutorial.finished then
			active.tutorial:Reset()
		else
			ctrl:Respawn()
		end
	end
	local cam = Workspace.CurrentCamera
	ctrl:Step(dt, if cam then cam.CFrame else CFrame.new())
	active.lockOn:Update(dt)
	active.tutorial:Update(dt)
	ctrl:Apply()
	active.fx:UpdatePose(dt)
end)

RunService:BindToRenderStep("MomentumCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not active then
		return
	end
	camera:Update(dt)
	active.fx:Update(dt)
	hud:Update(active.ctrl, dt, active.tutorial)
end)
]=====])
end
print('[Momentum] installed. Press Play (F5) to test.')
