-- Boots the momentum controller for the local player's character.

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
