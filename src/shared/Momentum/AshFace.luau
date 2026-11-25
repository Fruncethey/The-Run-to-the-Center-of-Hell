-- Ash's cartoon face: two big eyes (whites, pupils, eyelids), eyebrows and a mouth,
-- drawn with a SurfaceGui on a thin invisible plate in front of the R6 head.
--
-- The server builds it (AshFace.Build) so everyone sees his resting face. On your own
-- screen AshFx drives it every frame (AshFace.new + Update), switching expression
-- with what you're doing:
--   idle        relaxed smile, blinks every few seconds
--   determined  narrowed eyes, brows down, flat mouth (running, jumping)
--   grin        big open grin (above top speed, boosting, homing)
--   falling     wide eyes, tiny pupils, raised brows, "O" mouth
--   wince       eyes squeezed shut > <, gritted teeth (just got hit)

local Config = require(script.Parent.Config)

local AshFace = {}
AshFace.__index = AshFace

local W, H = 120, 90 -- canvas pixels (plate is 1.2 x 0.9 studs at 100 px per stud)
local EYE_W, EYE_H = 24, 32
local EYE_Y = 38
local EYE_X = { Left = 40, Right = 80 }
local MOUTH_Y = 68
local INK = Color3.fromRGB(35, 14, 28)
local WHITE = Color3.fromRGB(255, 255, 255)

local function frame(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, round: boolean?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color
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
	gui.LightInfluence = 0.4
	gui.Brightness = 1.2
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false
	gui.Parent = plate

	for side, x in EYE_X do
		-- Open eye: white, pupil, and a skin-colored lid that slides down over it
		local eye = frame(gui, side .. "Eye", px(EYE_W, EYE_H), px(x, EYE_Y), WHITE, true)
		eye.ClipsDescendants = true
		frame(eye, "Pupil", px(10, 14), UDim2.new(0.5, 0, 0.5, 2), INK, true)
		local lid = frame(eye, "Lid", UDim2.new(1, 4, 0, 0), UDim2.new(0.5, 0, 0, 0), Config.AshBodyColor)
		lid.AnchorPoint = Vector2.new(0.5, 0)
		-- Squeezed shut: two strokes making > (left eye) or < (right eye)
		local shut = Instance.new("Frame")
		shut.Name = side .. "Shut"
		shut.BackgroundTransparency = 1
		shut.AnchorPoint = Vector2.new(0.5, 0.5)
		shut.Size = px(EYE_W, EYE_H)
		shut.Position = px(x, EYE_Y)
		shut.Visible = false
		shut.Parent = gui
		local dir = if side == "Left" then 1 else -1
		frame(shut, "Top", px(20, 5), UDim2.new(0.5, 0, 0.5, -5), INK).Rotation = 28 * dir
		frame(shut, "Bottom", px(20, 5), UDim2.new(0.5, 0, 0.5, 5), INK).Rotation = -28 * dir
		frame(gui, side .. "Brow", px(24, 5), px(x, EYE_Y - 23), INK, false)
	end

	-- Mouths (one is shown at a time)

	-- Smile / frown: half of an outlined ring, clipped
	local smile = frame(gui, "Smile", px(30, 10), px(W / 2, MOUTH_Y + 4), INK)
	smile.BackgroundTransparency = 1
	smile.ClipsDescendants = true
	local ring = frame(smile, "Ring", px(26, 18), UDim2.new(0.5, 0, 0, -1), INK, true)
	ring.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 3.5
	stroke.Parent = ring

	-- Flat, determined line
	frame(gui, "Flat", px(22, 5), px(W / 2, MOUTH_Y), INK, false).Visible = false

	-- Big D-shaped grin with a row of teeth
	local grin = frame(gui, "Grin", px(44, 18), px(W / 2, MOUTH_Y + 6), INK)
	grin.BackgroundTransparency = 1
	grin.ClipsDescendants = true
	grin.Visible = false
	local d = frame(grin, "Shape", px(44, 36), UDim2.new(0.5, 0, 0, 0), INK, true)
	frame(d, "Teeth", UDim2.new(0.8, 0, 0, 6), UDim2.new(0.5, 0, 0.5, 3), WHITE, false)

	-- Little "O" of surprise
	frame(gui, "O", px(13, 17), px(W / 2, MOUTH_Y + 2), INK, true).Visible = false

	-- Gritted teeth
	local grit = frame(gui, "Grit", px(28, 10), px(W / 2, MOUTH_Y + 2), WHITE, false)
	grit.Visible = false
	grit.Rotation = -6
	local gs = Instance.new("UIStroke")
	gs.Color = INK
	gs.Thickness = 3
	gs.Parent = grit
	frame(grit, "Line", UDim2.new(1, 0, 0, 2), UDim2.fromScale(0.5, 0.5), INK, false)

	return plate
end

-- Expression targets. open: how far the lids are up (1 = wide open). scale: eye size.
-- pupil: pupil size. brow: inner-end-down angle in degrees. browY: pixels down from rest.
local EXPRESSIONS = {
	idle = { open = 0.95, scale = 1, pupil = 1, brow = 0, browY = 0, mouth = "Smile", shut = false },
	determined = { open = 0.62, scale = 1, pupil = 1, brow = 20, browY = 4, mouth = "Flat", shut = false },
	grin = { open = 0.7, scale = 1, pupil = 1.05, brow = 16, browY = 3, mouth = "Grin", shut = false },
	falling = { open = 1, scale = 1.22, pupil = 0.55, brow = -14, browY = -5, mouth = "O", shut = false },
	wince = { open = 0, scale = 1, pupil = 1, brow = 24, browY = 5, mouth = "Grit", shut = true },
}
local MOUTHS = { "Smile", "Flat", "Grin", "O", "Grit" }

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
	self.state = table.clone(EXPRESSIONS.idle)
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
		return "grin"
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
	for _, key in { "open", "scale", "pupil", "brow", "browY" } do
		s[key] += (target[key] - s[key]) * k
	end

	-- Blink every few seconds (not while squeezed shut)
	self.blinkIn -= dt
	if self.blinkIn <= 0 then
		self.blink = 0.13
		self.blinkIn = 2 + math.random() * 3
	end
	self.blink = math.max(0, self.blink - dt)
	local open = if self.blink > 0 then 0 else s.open

	for side, x in EYE_X do
		local eye = gui[side .. "Eye"]
		eye.Visible = not target.shut
		gui[side .. "Shut"].Visible = target.shut
		eye.Size = px(EYE_W * s.scale, EYE_H * s.scale)
		eye.Pupil.Size = px(10 * s.pupil, 14 * s.pupil)
		eye.Lid.Size = UDim2.new(1, 4, 1 - open, 0)
		local dir = if side == "Left" then 1 else -1
		local brow = gui[side .. "Brow"]
		brow.Rotation = s.brow * dir
		brow.Position = px(x, EYE_Y - 23 * s.scale + s.browY)
	end
	for _, m in MOUTHS do
		gui[m].Visible = m == target.mouth
	end
end

return AshFace
