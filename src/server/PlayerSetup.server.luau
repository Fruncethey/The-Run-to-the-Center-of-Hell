-- Server side of the momentum controller: characters go in a collision group that
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
