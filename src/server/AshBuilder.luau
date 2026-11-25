-- Builds Ash, the playable main character, as a chunky low-poly R15 rig made of
-- plain parts: a slim charcoal runner with glowing orange cracks, blank glowing
-- white eyes, swept-back ash spikes for hair, a tattered red scarf (the knot is
-- here; the streaming tail is drawn by AshFx on the client) and flame-wrapped sneakers.
--
-- The rig uses the standard R15 part and joint names, so the procedural run
-- cycle, spin-ball and afterimages work on it unchanged.
--
-- Decoration parts are named so the client can find them:
--   AshCrack      glowing crack strips (brightened with speed by AshFx)
--   AshScarfKnot  the scarf around the neck (the tail hangs off its back)
--   AshFlame      attachments on the sneakers holding the flame emitters

local AshBuilder = {}

local CHARCOAL = Color3.fromRGB(44, 42, 46)
local CHARCOAL_DARK = Color3.fromRGB(28, 26, 29)
local EMBER = Color3.fromRGB(255, 120, 30)
local EYE = Color3.fromRGB(255, 250, 235)
local SCARF = Color3.fromRGB(165, 24, 22)

-- Body layout, in studs, with the HumanoidRootPart's center at the origin.
-- Feet touch the ground at Y = -3.4, so HipHeight is 2.4.
local GROUND_Y = -3.4
local BODY = {
	-- name = { size, center }
	HumanoidRootPart = { Vector3.new(2, 2, 1), Vector3.new(0, 0, 0) },
	LowerTorso = { Vector3.new(1.3, 0.45, 0.72), Vector3.new(0, -0.6, 0) },
	UpperTorso = { Vector3.new(1.55, 1.3, 0.78), Vector3.new(0, 0.275, 0) },
	Head = { Vector3.new(1.15, 1.1, 1.1), Vector3.new(0, 1.5, 0) },
	LeftUpperArm = { Vector3.new(0.42, 1.0, 0.42), Vector3.new(-0.99, 0.3, 0) },
	LeftLowerArm = { Vector3.new(0.38, 0.95, 0.38), Vector3.new(-0.99, -0.675, 0) },
	LeftHand = { Vector3.new(0.42, 0.35, 0.42), Vector3.new(-0.99, -1.325, 0) },
	RightUpperArm = { Vector3.new(0.42, 1.0, 0.42), Vector3.new(0.99, 0.3, 0) },
	RightLowerArm = { Vector3.new(0.38, 0.95, 0.38), Vector3.new(0.99, -0.675, 0) },
	RightHand = { Vector3.new(0.42, 0.35, 0.42), Vector3.new(0.99, -1.325, 0) },
	LeftUpperLeg = { Vector3.new(0.52, 1.15, 0.52), Vector3.new(-0.38, -1.375, 0) },
	LeftLowerLeg = { Vector3.new(0.46, 1.1, 0.46), Vector3.new(-0.38, -2.5, 0) },
	LeftFoot = { Vector3.new(0.58, 0.35, 1.0), Vector3.new(-0.38, -3.225, -0.15) },
	RightUpperLeg = { Vector3.new(0.52, 1.15, 0.52), Vector3.new(0.38, -1.375, 0) },
	RightLowerLeg = { Vector3.new(0.46, 1.1, 0.46), Vector3.new(0.38, -2.5, 0) },
	RightFoot = { Vector3.new(0.58, 0.35, 1.0), Vector3.new(0.38, -3.225, -0.15) },
}

-- Joints: name = { parent part, child part, joint position }
local JOINTS = {
	Root = { "HumanoidRootPart", "LowerTorso", Vector3.new(0, -0.6, 0) },
	Waist = { "LowerTorso", "UpperTorso", Vector3.new(0, -0.375, 0) },
	Neck = { "UpperTorso", "Head", Vector3.new(0, 0.95, 0) },
	LeftShoulder = { "UpperTorso", "LeftUpperArm", Vector3.new(-0.99, 0.75, 0) },
	LeftElbow = { "LeftUpperArm", "LeftLowerArm", Vector3.new(-0.99, -0.2, 0) },
	LeftWrist = { "LeftLowerArm", "LeftHand", Vector3.new(-0.99, -1.15, 0) },
	RightShoulder = { "UpperTorso", "RightUpperArm", Vector3.new(0.99, 0.75, 0) },
	RightElbow = { "RightUpperArm", "RightLowerArm", Vector3.new(0.99, -0.2, 0) },
	RightWrist = { "RightLowerArm", "RightHand", Vector3.new(0.99, -1.15, 0) },
	LeftHip = { "LowerTorso", "LeftUpperLeg", Vector3.new(-0.38, -0.8, 0) },
	LeftKnee = { "LeftUpperLeg", "LeftLowerLeg", Vector3.new(-0.38, -1.95, 0) },
	LeftAnkle = { "LeftLowerLeg", "LeftFoot", Vector3.new(-0.38, -3.05, 0) },
	RightHip = { "LowerTorso", "RightUpperLeg", Vector3.new(0.38, -0.8, 0) },
	RightKnee = { "RightUpperLeg", "RightLowerLeg", Vector3.new(0.38, -1.95, 0) },
	RightAnkle = { "RightLowerLeg", "RightFoot", Vector3.new(0.38, -3.05, 0) },
}

local function bodyPart(name: string, size: Vector3, center: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(center)
	p.Color = CHARCOAL
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = true
	return p
end

-- A decoration welded onto a body part. cf is relative to that part.
local function deco(body: BasePart, name: string, class: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new(class) :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = body.CFrame * cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = material ~= Enum.Material.Neon
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	p.Parent = body
	return p
end

-- A jagged crack across one face of a body part. points are {x, y} pairs on that
-- face, from -0.5 to 0.5 of its width and height. face is "Front", "Back", "Left" or "Right".
local function crack(body: BasePart, face: string, points)
	local size = body.Size
	local function toLocal(pt): Vector3
		local x, y = pt[1], pt[2]
		if face == "Front" then
			return Vector3.new(x * size.X, y * size.Y, -size.Z / 2)
		elseif face == "Back" then
			return Vector3.new(-x * size.X, y * size.Y, size.Z / 2)
		elseif face == "Left" then
			return Vector3.new(-size.X / 2, y * size.Y, x * size.Z)
		else
			return Vector3.new(size.X / 2, y * size.Y, -x * size.Z)
		end
	end
	for i = 1, #points - 1 do
		local a, b = toLocal(points[i]), toLocal(points[i + 1])
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		-- Lie flat on the face: long axis along the segment, thin axis along the face normal
		local normal = if face == "Front" then -Vector3.zAxis
			elseif face == "Back" then Vector3.zAxis
			elseif face == "Left" then -Vector3.xAxis
			else Vector3.xAxis
		local along = (b - a).Unit
		local side = along:Cross(normal).Unit
		local cf = CFrame.fromMatrix(mid + normal * 0.01, side, normal, -along)
		deco(body, "AshCrack", "Part", Vector3.new(0.09, 0.04, len + 0.05), cf, EMBER, Enum.Material.Neon)
	end
end

local function addLooks(parts)
	local head = parts.Head
	local hs = head.Size

	-- Blank glowing eyes, angled into a determined look
	for _, side in { -1, 1 } do
		deco(head, "AshEye", "Part", Vector3.new(0.3, 0.15, 0.05),
			CFrame.new(0.24 * side, 0.06, -hs.Z / 2 - 0.01) * CFrame.Angles(0, 0, 0.18 * side), EYE, Enum.Material.Neon)
	end
	-- Swept-back ash spikes, ember-tipped
	for _, spec in { { -0.3, 0.75 }, { 0, 0.95 }, { 0.3, 0.75 } } do
		local x, len = spec[1], spec[2]
		local spike = deco(head, "AshSpike", "WedgePart", Vector3.new(0.32, 0.45, len),
			CFrame.new(x, hs.Y / 2 + 0.05, 0.2) * CFrame.Angles(0.35, 0, 0), CHARCOAL_DARK)
		deco(spike, "AshCrack", "Part", Vector3.new(0.3, 0.05, 0.18),
			CFrame.new(0, -0.18, len / 2 - 0.1), EMBER, Enum.Material.Neon)
	end
	crack(head, "Right", { { -0.3, 0.3 }, { -0.05, 0.05 }, { 0.15, 0.15 } })

	-- Scarf knot around the neck (AshFx streams the tail behind it)
	deco(parts.UpperTorso, "AshScarfKnot", "Part", Vector3.new(1.0, 0.32, 0.92),
		CFrame.new(0, 0.62, 0), SCARF)
	deco(parts.UpperTorso, "AshScarfFold", "WedgePart", Vector3.new(0.5, 0.35, 0.3),
		CFrame.new(0.2, 0.42, -0.42) * CFrame.Angles(0, 0, math.rad(180)), SCARF)

	-- Glowing cracks across the body
	crack(parts.UpperTorso, "Front", { { -0.35, 0.3 }, { -0.1, 0.05 }, { -0.2, -0.15 }, { 0.15, -0.4 } })
	crack(parts.UpperTorso, "Front", { { 0.3, 0.25 }, { 0.15, 0.05 } })
	crack(parts.UpperTorso, "Back", { { 0.3, 0.35 }, { 0.05, 0.1 }, { 0.2, -0.1 }, { -0.25, -0.35 } })
	crack(parts.LowerTorso, "Front", { { -0.3, 0.3 }, { 0.1, -0.2 } })
	for _, side in { "Left", "Right" } do
		local s = if side == "Left" then -1 else 1
		crack(parts[side .. "UpperArm"], side, { { 0.1, 0.35 }, { -0.15, 0.05 }, { 0.1, -0.3 } })
		crack(parts[side .. "LowerArm"], side, { { -0.1, 0.3 }, { 0.15, -0.1 } })
		crack(parts[side .. "UpperLeg"], "Front", { { 0.2 * s, 0.35 }, { -0.1 * s, 0.05 }, { 0.15 * s, -0.35 } })
		crack(parts[side .. "LowerLeg"], side, { { 0.15, 0.3 }, { -0.1, 0 }, { 0.1, -0.3 } })
	end

	-- Flame-wrapped sneakers: dark shoe, glowing sole, flame shapes up the sides
	for _, side in { "Left", "Right" } do
		local foot = parts[side .. "Foot"]
		local fs = foot.Size
		foot.Color = CHARCOAL_DARK
		deco(foot, "AshCrack", "Part", Vector3.new(fs.X + 0.04, 0.08, fs.Z + 0.04),
			CFrame.new(0, -fs.Y / 2 + 0.03, 0), EMBER, Enum.Material.Neon)
		deco(foot, "AshToe", "Part", Vector3.new(fs.X + 0.02, fs.Y * 0.6, 0.28),
			CFrame.new(0, -0.05, -fs.Z / 2 + 0.13), Color3.fromRGB(230, 225, 215))
		for _, s in { -1, 1 } do
			-- Two flame tongues licking up from the heel along each side
			deco(foot, "AshCrack", "WedgePart", Vector3.new(0.03, 0.32, 0.45),
				CFrame.new(s * (fs.X / 2 + 0.01), 0.02, 0.18), EMBER, Enum.Material.Neon)
			deco(foot, "AshCrack", "WedgePart", Vector3.new(0.03, 0.22, 0.3),
				CFrame.new(s * (fs.X / 2 + 0.01), -0.03, -0.12), EMBER, Enum.Material.Neon)
		end
		local att = Instance.new("Attachment")
		att.Name = "AshFlame"
		att.Position = Vector3.new(0, -0.05, 0.35)
		att.Parent = foot
		local fire = Instance.new("ParticleEmitter")
		fire.Name = "Flames"
		fire.Texture = "rbxasset://textures/particles/fire_main.dds"
		fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(220, 40, 10))
		fire.LightEmission = 1
		fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) })
		fire.Transparency = NumberSequence.new(0.2, 1)
		fire.Lifetime = NumberRange.new(0.2, 0.35)
		fire.Speed = NumberRange.new(1.5, 3)
		fire.SpreadAngle = Vector2.new(25, 25)
		fire.Acceleration = Vector3.new(0, 8, 0)
		fire.Rate = 12
		fire.Parent = att
	end

	-- Hands and lower legs a shade darker, like gloves and wraps
	for _, name in { "LeftHand", "RightHand" } do
		parts[name].Color = CHARCOAL_DARK
	end
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

	-- Rig attachments at each joint, then let the Humanoid build the Motor6Ds
	for jointName, spec in JOINTS do
		local parent, child, at = parts[spec[1]], parts[spec[2]], spec[3]
		for _, p in { parent, child } do
			local a = Instance.new("Attachment")
			a.Name = jointName .. "RigAttachment"
			a.CFrame = p.CFrame:ToObjectSpace(CFrame.new(at))
			a.Parent = p
		end
	end
	-- Attachments that accessories and effects expect on R15 rigs
	local neckTop = Instance.new("Attachment")
	neckTop.Name = "NeckAttachment"
	neckTop.Position = Vector3.new(0, parts.UpperTorso.Size.Y / 2, 0)
	neckTop.Parent = parts.UpperTorso

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = -GROUND_Y - root.Size.Y / 2
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	humanoid:BuildRigFromAttachments()

	addLooks(parts)

	model:SetAttribute("AshCharacter", true)
	return model
end

return AshBuilder
