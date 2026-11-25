-- Lock-on and enemy contact for the local player.
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
