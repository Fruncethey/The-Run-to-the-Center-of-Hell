-- Chase camera: swings in behind your direction of travel, pulls back and widens
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
