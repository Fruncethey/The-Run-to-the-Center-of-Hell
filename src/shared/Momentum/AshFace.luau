-- Ash's face: two glowing orange circle eyes and nothing else (no mouth, pupils or
-- brows), drawn with a SurfaceGui on a thin invisible plate in front of the R6 head.
--
-- The server builds it (AshFace.Build) so everyone sees his resting eyes. On your own
-- screen AshFx drives it every frame (AshFace.new + Update), and the eyes alone show
-- his expression:
--   idle        round circles, blinking every few seconds
--   determined  squashed and tilted inward (running, jumping)
--   happy       ^ ^ arcs (above top speed, boosting, homing)
--   falling     bigger circles
--   wince       > < squeezed shut (just got hit)

local Config = require(script.Parent.Config)

local AshFace = {}
AshFace.__index = AshFace

local W, H = 120, 90 -- canvas pixels (plate is 1.2 x 0.9 studs at 100 px per stud)
local EYE = 24 -- circle diameter in pixels
local EYE_Y = 42
local EYE_X = { Left = 40, Right = 80 }
local ORANGE = Color3.fromRGB(255, 140, 30)

local function frame(parent: Instance, name: string, size: UDim2, pos: UDim2, round: boolean?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = ORANGE
	f.BorderSizePixel = 0
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function px(x: number, y: number): UDim2
	return UDim2.fromOffset(x, y)
end

-- Builds the face plate and its gui on an R6 head. Returns the plate.
function AshFace.Build(head: BasePart): BasePart
	local plate = Instance.new("Part")
	plate.Name = "AshFacePlate"
	plate.Size = Vector3.new(W / 100, H / 100, 0.05)
	plate.CFrame = head.CFrame * CFrame.new(0, 0.02, -0.6)
	plate.Transparency = 1
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.Massless = true
	plate.CastShadow = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = plate
	weld.Parent = plate
	plate.Parent = head

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0 -- the eyes glow
	gui.Brightness = 2
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false
	gui.Parent = plate

	for side, x in EYE_X do
		local dir = if side == "Left" then 1 else -1

		-- The circle (squashed, tilted and resized for expressions)
		frame(gui, side .. "Eye", px(EYE, EYE), px(x, EYE_Y), true)

		-- Happy: the top half of an orange ring, like ^
		local happy = frame(gui, side .. "Happy", px(EYE + 4, EYE / 2), px(x, EYE_Y), false)
		happy.BackgroundTransparency = 1
		happy.ClipsDescendants = true
		happy.Visible = false
		local ring = frame(happy, "Ring", px(EYE, EYE), UDim2.new(0.5, 0, 1, 2), true)
		ring.BackgroundTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = ORANGE
		stroke.Thickness = 5
		stroke.Parent = ring

		-- Squeezed shut: > (left eye) or < (right eye)
		local shut = Instance.new("Frame")
		shut.Name = side .. "Shut"
		shut.BackgroundTransparency = 1
		shut.AnchorPoint = Vector2.new(0.5, 0.5)
		shut.Size = px(EYE, EYE)
		shut.Position = px(x, EYE_Y)
		shut.Visible = false
		shut.Parent = gui
		frame(shut, "Top", px(20, 5), UDim2.new(0.5, 0, 0.5, -5)).Rotation = 28 * dir
		frame(shut, "Bottom", px(20, 5), UDim2.new(0.5, 0, 0.5, 5)).Rotation = -28 * dir
	end

	return plate
end

-- Expression targets. w, h: eye size as a share of the circle. tilt: degrees, inner
-- corners down. shape: which drawing to show ("Eye", "Happy" or "Shut").
local EXPRESSIONS = {
	idle = { w = 1, h = 1, tilt = 0, shape = "Eye" },
	determined = { w = 1.1, h = 0.62, tilt = 14, shape = "Eye" },
	happy = { w = 1, h = 1, tilt = 0, shape = "Happy" },
	falling = { w = 1.3, h = 1.3, tilt = 0, shape = "Eye" },
	wince = { w = 1, h = 1, tilt = 0, shape = "Shut" },
}
local SHAPES = { "Eye", "Happy", "Shut" }

-- Client side: drive an existing face. Returns nil if the character has none.
function AshFace.new(character: Model)
	local plate = character:FindFirstChild("AshFacePlate", true)
	local gui = plate and plate:FindFirstChild("Face")
	if not gui then
		return nil
	end
	local self = setmetatable({}, AshFace)
	self.gui = gui
	self.expression = "idle"
	self.state = { w = 1, h = 1, tilt = 0 }
	self.blinkIn = 2 + math.random() * 2
	self.blink = 0
	return self
end

function AshFace:Choose(ctrl, speed: number): string
	local C = Config
	if ctrl.hurtTimer and ctrl.hurtTimer > C.HurtInvulnerability - 0.6 then
		return "wince"
	end
	if not ctrl.grounded and ctrl.velocity.Y < -45 and not ctrl.homingTarget and not ctrl.stomping then
		return "falling"
	end
	if ctrl.boosting or ctrl.homingTarget or speed > C.TopSpeed + 15 then
		return "happy"
	end
	if speed > 20 or not ctrl.grounded then
		return "determined"
	end
	return "idle"
end

function AshFace:Update(dt: number, ctrl, speed: number, hidden: boolean)
	local gui = self.gui
	if not gui.Parent then
		return
	end
	gui.Enabled = not hidden
	if hidden then
		return
	end

	local name = self:Choose(ctrl, speed)
	self.expression = name
	local target = EXPRESSIONS[name]
	local s = self.state
	local k = 1 - math.exp(-14 * dt)
	for _, key in { "w", "h", "tilt" } do
		s[key] += (target[key] - s[key]) * k
	end

	-- Blink every few seconds: the circles squash flat for a moment
	self.blinkIn -= dt
	if self.blinkIn <= 0 then
		self.blink = 0.12
		self.blinkIn = 2 + math.random() * 3
	end
	self.blink = math.max(0, self.blink - dt)
	local h = if self.blink > 0 then 0.12 else s.h

	for side in EYE_X do
		local dir = if side == "Left" then 1 else -1
		local eye = gui[side .. "Eye"]
		eye.Size = px(EYE * s.w, math.max(3, EYE * h))
		eye.Rotation = s.tilt * dir
		for _, shape in SHAPES do
			gui[side .. shape].Visible = shape == target.shape
		end
	end
end

return AshFace
