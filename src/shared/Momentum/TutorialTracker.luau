-- Client-side tracker for the tutorial level's stage zones, checkpoints,
-- run timer, and finish gate. Uses direct bounding-box checks against the
-- controller's position so fast movement never skips a trigger.

local Workspace = game:GetService("Workspace")

local LEVEL_NAME = "HellTestLevel"
local COLOR_IDLE = Color3.fromRGB(255, 110, 30)
local COLOR_ACTIVE = Color3.fromRGB(30, 220, 255)

local TutorialTracker = {}
TutorialTracker.__index = TutorialTracker

local function insideBox(part: BasePart, point: Vector3): boolean
	local rel = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function collectGlows(container: Instance): { BasePart }
	local list = {}
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("GlowAccent") then
			table.insert(list, d)
		end
	end
	return list
end

local function setGlowColor(glows: { BasePart }, color: Color3)
	for _, p in glows do
		if p.Parent then
			p.Color = color
		end
	end
end

function TutorialTracker.new(ctrl)
	local self = setmetatable({}, TutorialTracker)
	self.ctrl = ctrl
	self.level = nil
	self.zones = {}
	self.checkpoints = {}
	self.goal = nil

	self.started = false
	self.finished = false
	self.elapsed = 0
	self.peakSpeed = 0
	self.checkpointIndex = 0
	self.totalCheckpoints = 0
	self.currentTitle = ""
	self.currentHint = ""
	self.toastText = nil
	self.toastTimer = 0

	self:BindLevel()
	return self
end

function TutorialTracker:BindLevel()
	local level = Workspace:FindFirstChild(LEVEL_NAME)
	if not level or level == self.level then
		return
	end
	self.level = level
	self.zones = {}
	self.checkpoints = {}
	self.goal = nil

	local zonesFolder = level:FindFirstChild("TutorialZones")
	if zonesFolder then
		for _, child in zonesFolder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(self.zones, {
					part = child,
					title = child:GetAttribute("ZoneTitle") or "",
					hint = child:GetAttribute("ZoneHint") or "",
					order = child:GetAttribute("ZoneOrder") or 0,
				})
			end
		end
		table.sort(self.zones, function(a, b)
			return a.order < b.order
		end)
	end

	local cpFolder = level:FindFirstChild("Checkpoints")
	if cpFolder then
		for _, child in cpFolder:GetChildren() do
			local trigger = child:FindFirstChild("Trigger")
			if trigger and trigger:IsA("BasePart") then
				table.insert(self.checkpoints, {
					folder = child,
					trigger = trigger,
					index = child:GetAttribute("CheckpointIndex") or 0,
					label = child:GetAttribute("CheckpointLabel") or "",
					glows = collectGlows(child),
					reached = false,
				})
			end
		end
		table.sort(self.checkpoints, function(a, b)
			return a.index < b.index
		end)
	end
	self.totalCheckpoints = #self.checkpoints

	local goalFolder = level:FindFirstChild("GoalGate")
	if goalFolder then
		local trigger = goalFolder:FindFirstChild("Trigger")
		if trigger and trigger:IsA("BasePart") then
			self.goal = {
				folder = goalFolder,
				trigger = trigger,
				glows = collectGlows(goalFolder),
			}
		end
	end
end

-- Bind again if more zones or checkpoints have streamed in, keeping progress
function TutorialTracker:Rescan()
	local level = self.level
	local zones = level:FindFirstChild("TutorialZones")
	local cps = level:FindFirstChild("Checkpoints")
	local goal = level:FindFirstChild("GoalGate")
	local nCps = 0
	if cps then
		for _, child in cps:GetChildren() do
			if child:FindFirstChild("Trigger") then
				nCps += 1
			end
		end
	end
	local nZones = if zones then #zones:GetChildren() else 0
	local hasGoal = goal ~= nil and goal:FindFirstChild("Trigger") ~= nil
	if nZones == #self.zones and nCps == #self.checkpoints and hasGoal == (self.goal ~= nil) then
		return
	end
	local reached = {}
	for _, cp in self.checkpoints do
		if cp.reached then
			reached[cp.index] = true
		end
	end
	self.level = nil
	self:BindLevel()
	for _, cp in self.checkpoints do
		if reached[cp.index] then
			cp.reached = true
			setGlowColor(cp.glows, COLOR_ACTIVE)
		end
	end
end

function TutorialTracker:HasCourse(): boolean
	return #self.zones > 0 or self.totalCheckpoints > 0 or self.goal ~= nil
end

function TutorialTracker:Update(dt: number)
	if not self.level or not self.level.Parent then
		self.level = nil
		self:BindLevel()
	end
	if not self.level then
		return
	end
	-- With streaming on, parts of the course can arrive after we first bound to it
	self.rescanTimer = (self.rescanTimer or 0) - dt
	if self.rescanTimer <= 0 then
		self.rescanTimer = 1
		self:Rescan()
	end

	local ctrl = self.ctrl
	local pos = ctrl.position
	local speed = ctrl:GetSpeed()

	if not self.finished then
		if not self.started and speed > 2 then
			self.started = true
		end
		if self.started then
			self.elapsed += dt
		end
		if speed > self.peakSpeed then
			self.peakSpeed = speed
		end
	end

	if self.toastTimer > 0 then
		self.toastTimer = math.max(0, self.toastTimer - dt)
		if self.toastTimer == 0 then
			self.toastText = nil
		end
	end

	-- Update active tutorial stage prompt
	for _, z in self.zones do
		if z.part.Parent and insideBox(z.part, pos) then
			self.currentTitle = z.title
			self.currentHint = z.hint
			break
		end
	end

	-- Checkpoints
	for _, cp in self.checkpoints do
		if not cp.reached and cp.trigger.Parent and insideBox(cp.trigger, pos) then
			cp.reached = true
			setGlowColor(cp.glows, COLOR_ACTIVE)
			if cp.index > self.checkpointIndex then
				self.checkpointIndex = cp.index
				local spawnPos = cp.trigger:GetAttribute("SpawnPosition")
				if typeof(spawnPos) ~= "Vector3" then
					spawnPos = cp.trigger.Position
				end
				ctrl:SetCheckpoint(spawnPos, cp.trigger.CFrame.LookVector)
				local suffix = if cp.label ~= "" then " — " .. cp.label else ""
				self.toastText = string.format("CHECKPOINT %d / %d%s", cp.index, self.totalCheckpoints, suffix)
				self.toastTimer = 2.6
			end
		end
	end

	-- Finish gate
	if self.goal and not self.finished and self.goal.trigger.Parent and insideBox(self.goal.trigger, pos) then
		self.finished = true
		setGlowColor(self.goal.glows, COLOR_ACTIVE)
		self.toastText = nil
		self.toastTimer = 0
	end
end

function TutorialTracker:Reset()
	self.started = false
	self.finished = false
	self.elapsed = 0
	self.peakSpeed = 0
	self.checkpointIndex = 0
	self.toastText = nil
	self.toastTimer = 0

	for _, cp in self.checkpoints do
		cp.reached = false
		setGlowColor(cp.glows, COLOR_IDLE)
	end
	if self.goal then
		setGlowColor(self.goal.glows, COLOR_IDLE)
	end

	self.ctrl:ResetToStart()
end

return TutorialTracker
