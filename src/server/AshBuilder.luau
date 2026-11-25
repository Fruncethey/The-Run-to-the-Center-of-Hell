-- Builds Ash, the playable main character, on the standard Roblox R6 rig
-- (Head, Torso, two arms, two legs), kept simple to match the game's art style.
-- His look comes from colors plus a few small touches:
--   * a bright body color that contrasts with the lava levels (Config.AshBodyColor)
--   * glowing orange circle eyes that change expression (AshFace)
--   * a glowing orange crack across the chest
--   * a red scarf knot around the neck (AshFx streams the tail behind him)
--
-- The rig uses the standard R6 part and joint names, so the run cycle (which
-- drives R6 joints too), spin-ball and afterimages work on it.
--
-- Decoration parts are named so the client can find them:
--   AshCrack      glowing parts (brightened with speed by AshFx)
--   AshScarfKnot  the scarf around the neck (the tail hangs off its back)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Momentum = ReplicatedStorage:WaitForChild("Momentum")
local Config = require(Momentum:WaitForChild("Config"))
local AshFace = require(Momentum:WaitForChild("AshFace"))

local AshBuilder = {}

local EMBER = Color3.fromRGB(255, 120, 30)
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

	-- One jagged glowing crack across the chest
	local crack = { { -0.55, 0.65 }, { -0.15, 0.2 }, { -0.4, -0.15 }, { 0.3, -0.7 } }
	for i = 1, #crack - 1 do
		local a = Vector3.new(crack[i][1], crack[i][2], -0.5)
		local b = Vector3.new(crack[i + 1][1], crack[i + 1][2], -0.5)
		local cf = CFrame.lookAt((a + b) / 2 - Vector3.new(0, 0, 0.01), b - Vector3.new(0, 0, 0.01), -Vector3.zAxis)
		deco(torso, "AshCrack", Vector3.new(0.12, 0.04, (b - a).Magnitude + 0.06), cf, EMBER, true)
	end

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
