-- Makes Ash the character everyone plays as: builds him once at server start,
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
