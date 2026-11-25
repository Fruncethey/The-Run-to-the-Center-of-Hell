-- Spawns enemies ("Cinder Imps": floating horned embers) at every part named
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
