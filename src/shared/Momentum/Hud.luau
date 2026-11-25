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
		Text = "WASD move   Space jump (in air: homing attack on a locked imp, or air dash)   Hold Q spin-dash / roll (in air: stomp)   Shift boost   Right-drag camera   R respawn",
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(16, 52),
		Size = UDim2.new(1, -32, 0, 18),
		TextTransparency = 0.15,
	})

	-- Tutorial stage prompt banner (top center, auto-hidden when no tutorial zone is active)
	local banner = Instance.new("Frame")
	banner.Name = "TutorialBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 78)
	banner.Size = UDim2.fromOffset(640, 56)
	banner.BackgroundColor3 = Color3.fromRGB(24, 10, 10)
	banner.BackgroundTransparency = 0.25
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = gui
	Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 8)
	local bannerStroke = Instance.new("UIStroke", banner)
	bannerStroke.Color = Color3.fromRGB(255, 115, 35)
	bannerStroke.Thickness = 1.5
	bannerStroke.Transparency = 0.25

	self.banner = banner
	self.bannerTitle = label(banner, {
		Text = "",
		TextSize = 15,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 175, 85),
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 20),
	})
	self.bannerHint = label(banner, {
		Text = "",
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 240, 225),
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -24, 0, 22),
	})

	-- Run timer & checkpoint counter (top right)
	local courseBox = Instance.new("Frame")
	courseBox.Name = "CourseStats"
	courseBox.AnchorPoint = Vector2.new(1, 0)
	courseBox.Position = UDim2.new(1, -24, 0, 78)
	courseBox.Size = UDim2.fromOffset(168, 56)
	courseBox.BackgroundColor3 = Color3.fromRGB(24, 10, 10)
	courseBox.BackgroundTransparency = 0.3
	courseBox.BorderSizePixel = 0
	courseBox.Visible = false
	courseBox.Parent = gui
	Instance.new("UICorner", courseBox).CornerRadius = UDim.new(0, 8)
	local courseStroke = Instance.new("UIStroke", courseBox)
	courseStroke.Color = Color3.fromRGB(255, 115, 35)
	courseStroke.Thickness = 1.5
	courseStroke.Transparency = 0.35

	self.courseBox = courseBox
	self.timerLabel = label(courseBox, {
		Text = "00:00.0",
		TextSize = 24,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 28),
	})
	self.cpLabel = label(courseBox, {
		Text = "CP 0 / 0",
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(120, 225, 255),
		Position = UDim2.fromOffset(10, 34),
		Size = UDim2.new(1, -20, 0, 16),
	})

	-- Checkpoint toast (below banner)
	self.toast = label(gui, {
		Text = "",
		TextSize = 20,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(80, 230, 255),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 144),
		Size = UDim2.fromOffset(560, 28),
		Visible = false,
	})

	-- Completion overlay (shown after crossing the Descent Gate)
	local complete = Instance.new("Frame")
	complete.Name = "TutorialComplete"
	complete.AnchorPoint = Vector2.new(0.5, 0.5)
	complete.Position = UDim2.fromScale(0.5, 0.42)
	complete.Size = UDim2.fromOffset(440, 176)
	complete.BackgroundColor3 = Color3.fromRGB(18, 10, 14)
	complete.BackgroundTransparency = 0.14
	complete.BorderSizePixel = 0
	complete.Visible = false
	complete.Parent = gui
	Instance.new("UICorner", complete).CornerRadius = UDim.new(0, 12)
	local completeStroke = Instance.new("UIStroke", complete)
	completeStroke.Color = Color3.fromRGB(50, 225, 255)
	completeStroke.Thickness = 2.5

	self.complete = complete
	label(complete, {
		Text = "TUTORIAL COMPLETE!",
		TextSize = 30,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(80, 230, 255),
		Position = UDim2.fromOffset(16, 18),
		Size = UDim2.new(1, -32, 0, 38),
	})
	self.completeStats = label(complete, {
		Text = "",
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 235, 210),
		Position = UDim2.fromOffset(16, 68),
		Size = UDim2.new(1, -32, 0, 52),
	})
	label(complete, {
		Text = "Press R to run the tutorial again",
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 175, 95),
		Position = UDim2.fromOffset(16, 134),
		Size = UDim2.new(1, -32, 0, 24),
	})

	gui.Parent = playerGui
	self.gui = gui
	self.t = 0
	return self
end

local function formatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = seconds - mins * 60
	return string.format("%02d:%04.1f", mins, secs)
end

function Hud:Update(ctrl, dt: number, tutorial)
	if not ctrl then
		return
	end
	self.t += dt
	local speed = ctrl.velocity.Magnitude
	self.speed.Text = tostring(math.floor(speed + 0.5))
	self.fill.Size = UDim2.fromScale(ctrl.heat, 1)

	local state
	if ctrl.hurtTimer > Config.HurtInvulnerability - 0.6 then
		state = "OUCH"
	elseif ctrl.homingTarget then
		state = "HOMING ATTACK"
	elseif ctrl.stomping then
		state = "STOMP"
	elseif ctrl.charging then
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

	if tutorial and tutorial:HasCourse() then
		self.courseBox.Visible = true
		self.timerLabel.Text = formatTime(tutorial.elapsed)
		self.cpLabel.Text = string.format("CHECKPOINT %d / %d", tutorial.checkpointIndex, tutorial.totalCheckpoints)

		local showBanner = not tutorial.finished and tutorial.currentTitle ~= ""
		self.banner.Visible = showBanner
		if showBanner then
			self.bannerTitle.Text = tutorial.currentTitle
			self.bannerHint.Text = tutorial.currentHint
		end

		if tutorial.toastText and tutorial.toastTimer > 0 then
			self.toast.Visible = true
			self.toast.Text = tutorial.toastText
			local alpha = math.clamp(tutorial.toastTimer / 0.6, 0, 1)
			self.toast.TextTransparency = 1 - alpha
			self.toast.TextStrokeTransparency = 0.4 + 0.6 * (1 - alpha)
		else
			self.toast.Visible = false
		end

		self.complete.Visible = tutorial.finished
		if tutorial.finished then
			self.completeStats.Text = string.format(
				"TIME: %s\nTOP SPEED: %d STUDS / SEC",
				formatTime(tutorial.elapsed),
				math.floor(tutorial.peakSpeed + 0.5)
			)
		end
	else
		self.courseBox.Visible = false
		self.banner.Visible = false
		self.toast.Visible = false
		self.complete.Visible = false
	end
end

return Hud
