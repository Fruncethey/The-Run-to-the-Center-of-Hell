-- Visuals for the local character: a speed-driven procedural run cycle (R15;
-- R6 falls back to the default run/idle/fall animations), a molten spin-ball while jumping, rolling or charging, and a fire trail
-- plus glow while boosting. Everything here is local-only presentation.

local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)
local RunCycle = require(script.Parent.RunCycle)

local CharacterFx = {}
CharacterFx.__index = CharacterFx

local BALL_SIZE = 4.6

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

	return self
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
	self.trail:Destroy()
	self.light:Destroy()
end

return CharacterFx
