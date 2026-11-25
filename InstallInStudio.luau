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
	rc:Update(dt, v.Magnitude, ctrl.grounded, v.Y)
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
	SlopeFactor = 0.55, -- share of gravity that pushes you along slopes
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
	RollSlopeDown = 2.0, -- rolling downhill gains twice the speed running does
	RollSlopeUp = 0.5, -- and loses half as much going uphill
	RunOverspeedDrag = 25, -- running above TopSpeed (not boosting) bleeds back down to it
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

	-- Procedural run cycle (R15)
	RunCycleWalkSpeed = 20, -- full walk stride by this speed
	RunCycleRunSpeed = 60, -- full run (knee lift, arm pump, lean) by this speed
	RunCycleSprintSpeed = 100, -- arms start sweeping back here
	RunCycleSprintBlend = 50, -- ...and are fully back this much faster
	RunCycleMinCadence = 1.4, -- steps cycles per second at walking pace
	RunCycleMaxCadence = 5, -- cap so the legs don't strobe at 300 speed
	RunCycleCadenceSpeed = 70, -- how quickly cadence climbs toward the cap
	RunCycleSmoothing = 8, -- how fast the gait follows speed changes
	RunCycleArmSpread = 0.5, -- radians the arms splay out to the sides while running
	RunCycleExaggeration = 1.5, -- cartoon factor for the run and sprint (1 = realistic, 2 = very rubbery)

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
	return Config.TurnRateSlow + (Config.TurnRateFast - Config.TurnRateSlow) * t
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

	return self
end

function Controller:SetFacing(look: Vector3)
	local f = safeUnit(flatten(look), nil)
	if f then
		self.facing = f
		self.spawnFacing = f
	end
end

function Controller:AddIgnore(instance: Instance)
	local list = self.rayParams.FilterDescendantsInstances
	table.insert(list, instance)
	self.rayParams.FilterDescendantsInstances = list
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
	local slope = Config.SlopeFactor
	if self.rolling then
		slope *= if gTan:Dot(vel) > 0 then Config.RollSlopeDown else Config.RollSlopeUp
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

	-- Running can't hold onto speed past TopSpeed the way a roll can
	if not self.rolling and not self.charging and not self.boosting and speed > Config.TopSpeed then
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

	gui.Parent = playerGui
	self.gui = gui
	self.t = 0
	return self
end

function Hud:Update(ctrl, dt: number)
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
--   90+       -> sprint: arms swept back, deep lean, legs at full cadence
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

	local s = math.sin(self.phase)
	local c = math.cos(self.phase)

	-- Cartoon factor: walking stays natural, running and sprinting get pushed further
	local x = lerp(1, C.RunCycleExaggeration, run)

	-- Legs: hips swing opposite each other; the knee folds while that leg swings forward.
	-- The forward swing is bigger than the back swing, for high cartoon knees.
	local hipAmp = (lerp(0.45, 0.95, run) + 0.15 * sprint) * x
	local kneeAmp = (lerp(0.55, 1.7, run) + 0.3 * sprint) * x
	local function hip(v: number): number
		return if v > 0 then math.min(1.7, v * lerp(1, 1.3, run)) else v
	end
	local hipL = hip(s * hipAmp) * move
	local hipR = hip(-s * hipAmp) * move
	local kneeL = -math.min(2.6, 0.08 + kneeAmp * math.max(0, c)) * move
	local kneeR = -math.min(2.6, 0.08 + kneeAmp * math.max(0, -c)) * move
	local ankleL = (0.25 * s - 0.2 * run * x * math.max(0, -c)) * move
	local ankleR = (-0.25 * s - 0.2 * run * x * math.max(0, c)) * move

	-- Arms: big pumping counter-swing at run, swept far back at sprint
	local armAmp = lerp(0.35, 0.9, run) * x * move
	local swingL = -s * armAmp
	local swingR = s * armAmp
	local sweptBack = -1.15 - 0.35 * (x - 1)
	local shoulderLX = lerp(swingL, sweptBack + 0.1 * x * s, sprint)
	local shoulderRX = lerp(swingR, sweptBack - 0.1 * x * s, sprint)
	-- Arms splay out to the sides as well as swinging, flaring wider at each end of the swing
	local spread = lerp(0.05, C.RunCycleArmSpread, run) * move
	local shoulderOut = (spread + 0.2 * math.abs(s) * run + 0.1 * sprint) * x
	local elbowL = lerp(lerp(0.15, 1.5, run) * move + 0.1, 0.25, sprint) * lerp(1, 1.15, run * (x - 1))
	local elbowR = elbowL

	-- Torso: lean into speed, twist against the hips, bounce on each footfall,
	-- and rock the hips side to side
	local lean = -(lerp(0.04, 0.28, run) * move + 0.22 * sprint) * x
	local twist = 0.18 * s * run * (1 - 0.5 * sprint) * x
	local bounce = (math.abs(c) - 0.5) * lerp(0.08, 0.35, run) * x * x * move
	local sway = 0.08 * s * run * (x - 1) * 2
	local breathe = (1 - move) * 0.03 * math.sin(t * 2.2)

	pose.Root = CFrame.new(0, bounce, 0) * rot(0, -twist * 0.5, sway)
	pose.Waist = rot(lean + breathe, twist, -sway * 0.6)
	pose.Neck = rot(-lean * 0.7 - breathe, -twist * 0.8, 0)
	-- Swing first, then splay the whole swing outward, so spreading doesn't shrink the swing
	pose.LeftShoulder = rot(0, 0, -shoulderOut) * rot(shoulderLX, 0, 0)
	pose.RightShoulder = rot(0, 0, shoulderOut) * rot(shoulderRX, 0, 0)
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

function RunCycle:Update(dt: number, speed: number, grounded: boolean, verticalSpeed: number)
	self.time += dt
	local C = Config
	-- Smooth the speed (not the pose) so gait changes ease in without damping the swing
	self.speed += (speed - self.speed) * (1 - math.exp(-C.RunCycleSmoothing * dt))
	speed = self.speed
	-- Cadence rises quickly at first, then levels off so top speeds don't strobe
	local cadence = C.RunCycleMinCadence
		+ (C.RunCycleMaxCadence - C.RunCycleMinCadence) * (1 - math.exp(-speed / C.RunCycleCadenceSpeed))
	if grounded then
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
script(f, 'ModuleScript', 'LevelBuilder', [=====[-- Procedurally builds "Circle 0: The Test Pit", a small course for the momentum
-- controller: a starting drop, a hill, a loop, a launch ramp, a long wall-run
-- quarter pipe on the left, and a big quarter pipe at the end. It also places
-- invisible "EnemySpawn" markers that EnemyService fills with enemies.
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

-- Invisible marker; EnemyService spawns an enemy here. Move these around in Studio.
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

	-- 7. Enemies
	do
		local spawns = Instance.new("Folder")
		spawns.Name = "EnemySpawns"
		spawns.Parent = level
		-- Ground imps after the drop: roll, boost or jump through them, don't just run in
		enemySpawn(spawns, W(160, 4, -6), Vector3.new(0, 0, 6), 1.2)
		enemySpawn(spawns, W(178, 4, 6), Vector3.new(0, 0, -6), 1.2)
		-- One hovering over the hill top: jump and home in
		enemySpawn(spawns, W(280, 32, 0))
		-- Homing chain off the launch ramp: home, bounce, home, bounce...
		enemySpawn(spawns, W(625, 30, 16))
		enemySpawn(spawns, W(660, 38, 16))
		enemySpawn(spawns, W(695, 32, 16))
		-- Guards in front of the quarter pipe
		enemySpawn(spawns, W(735, 4, 0), Vector3.new(0, 0, 14), 0.8)
		-- Along the wall run, for homing off the wall
		enemySpawn(spawns, W(420, 34, -78), Vector3.new(20, 0, 0), 0.6)
		enemySpawn(spawns, W(540, 40, -78), Vector3.new(20, 0, 0), 0.6)
		sign(level, W(625, 44, 16), "HOMING CHAIN: jump off the ramp, tap jump on each imp")
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

	active = { ctrl = ctrl, fx = fx, lockOn = lockOn, character = character }
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
		ctrl:Respawn()
	end
	local cam = Workspace.CurrentCamera
	ctrl:Step(dt, if cam then cam.CFrame else CFrame.new())
	active.lockOn:Update(dt)
	ctrl:Apply()
	active.fx:UpdatePose(dt)
end)

RunService:BindToRenderStep("MomentumCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not active then
		return
	end
	camera:Update(dt)
	active.fx:Update(dt)
	hud:Update(active.ctrl, dt)
end)
]=====])
end
print('[Momentum] installed. Press Play (F5) to test.')
