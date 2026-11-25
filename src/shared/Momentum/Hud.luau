-- Speedometer, heat meter and a controls hint.

local Config = require(script.Parent.Config)

local Hud = {}
Hud.__index = Hud

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.fromRGB(255, 235, 210)
	l.TextStrokeTransparency = 0.4
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function Hud.new(playerGui: PlayerGui)
	local self = setmetatable({}, Hud)

	local old = playerGui:FindFirstChild("MomentumHud")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MomentumHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local panel = Instance.new("Frame")
	panel.BackgroundTransparency = 1
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 24, 1, -24)
	panel.Size = UDim2.fromOffset(340, 110)
	panel.Parent = gui

	self.speed = label(panel, { Text = "0", TextSize = 48, Size = UDim2.new(1, 0, 0, 50) })
	label(panel, {
		Text = "STUDS / SEC",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 16),
	})
	self.state = label(panel, {
		Text = "",
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 16),
		TextColor3 = Color3.fromRGB(255, 160, 80),
	})

	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 0, 1, -22)
	bar.Size = UDim2.new(1, 0, 0, 22)
	bar.BackgroundColor3 = Color3.fromRGB(35, 12, 10)
	bar.BorderSizePixel = 0
	bar.Parent = panel
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke", bar)
	stroke.Color = Color3.fromRGB(255, 120, 40)
	stroke.Thickness = 2
	self.barStroke = stroke

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)
	local gradient = Instance.new("UIGradient", fill)
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 20, 10)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 110, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 160)),
	})
	self.fill = fill

	-- Marker showing the minimum heat needed to start a boost
	local mark = Instance.new("Frame")
	mark.Size = UDim2.new(0, 2, 1, 0)
	mark.Position = UDim2.fromScale(Config.BoostMinHeat, 0)
	mark.BackgroundColor3 = Color3.fromRGB(255, 240, 200)
	mark.BackgroundTransparency = 0.3
	mark.BorderSizePixel = 0
	mark.Parent = bar

	self.heatLabel = label(bar, {
		Text = "HEAT",
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	})

	label(gui, {
		Text = "WASD move   Space jump   Hold Q spin-dash / roll   Shift boost   Right-drag camera   R respawn",
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(16, 52),
		Size = UDim2.new(1, -32, 0, 18),
		TextTransparency = 0.15,
	})

	gui.Parent = playerGui
	self.gui = gui
	self.t = 0
	return self
end

function Hud:Update(ctrl, dt: number)
	if not ctrl then
		return
	end
	self.t += dt
	local speed = ctrl.velocity.Magnitude
	self.speed.Text = tostring(math.floor(speed + 0.5))
	self.fill.Size = UDim2.fromScale(ctrl.heat, 1)

	local state
	if ctrl.charging then
		state = string.format("CHARGING %d%%", math.floor(ctrl.spinCharge * 100))
	elseif ctrl.boosting then
		state = "BOOST"
	elseif ctrl.rolling then
		state = "ROLLING"
	elseif not ctrl.grounded then
		state = "AIR"
	elseif ctrl.up.Y < Config.SteepSurfaceY then
		state = "WALL RUN"
	else
		state = ""
	end
	self.state.Text = state

	local ready = ctrl.heat >= Config.BoostMinHeat
	self.heatLabel.Text = if ctrl.boosting then "HEAT  >> BOOSTING" elseif ready then "HEAT  (Shift to boost)" else "HEAT"
	local pulse = if ctrl.boosting then 0.5 + 0.5 * math.sin(self.t * 30) else 0
	self.barStroke.Color = Color3.fromRGB(255, 120, 40):Lerp(Color3.fromRGB(255, 245, 200), pulse)
end

return Hud
