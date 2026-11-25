-- Visuals for the local character: a speed-driven procedural run cycle (R15;
-- R6 falls back to the default run/idle/fall animations), a molten spin-ball while jumping, rolling or charging, and a fire trail
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
