-- Procedural, speed-driven run cycle for R15 characters.
-- Instead of playing a fixed animation, every frame this poses the joints
-- (the Transform of each Motor6D, or AnimationConstraint on newer avatars) from a gait cycle whose cadence, stride and posture all
-- follow the controller's speed:
--   standing  -> idle breathing
--   0-20      -> walk: short stride, relaxed arms, upright
--   20-90     -> run: long stride, high knee lift, pumping arms, forward lean, bounce
--   90+       -> sprint: arms swept back, deep lean, legs at full cadence
-- In the air it blends to a fall pose. Tuning lives in Config (RunCycle* values).

local Config = require(script.Parent.Config)

local RunCycle = {}
RunCycle.__index = RunCycle

local JOINTS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftShoulder = "LeftUpperArm",
	RightShoulder = "RightUpperArm",
	LeftElbow = "LeftLowerArm",
	RightElbow = "RightLowerArm",
	LeftHip = "LeftUpperLeg",
	RightHip = "RightUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightKnee = "RightLowerLeg",
	LeftAnkle = "LeftFoot",
	RightAnkle = "RightFoot",
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.fromEulerAnglesXYZ(x, y, z)
end

-- Returns nil for rigs it can't drive (R6), so the caller can fall back.
function RunCycle.new(character: Model)
	local motors = {}
	for name, partName in JOINTS do
		local part = character:FindFirstChild(partName)
		local joint = part and part:FindFirstChild(name)
		if not (joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint"))) then
			return nil
		end
		motors[name] = joint
	end
	local self = setmetatable({}, RunCycle)
	self.motors = motors
	self.animator = character:FindFirstChildWhichIsA("Animator", true)
	self.phase = 0
	self.time = 0
	self.air = 0
	self.speed = 0
	self.weight = 0 -- fades the pose in after Reset (e.g. leaving the spin-ball)
	return self
end

-- Target pose for every joint, from the gait at this speed.
function RunCycle:Pose(speed: number, grounded: boolean, verticalSpeed: number)
	local C = Config
	local t = self.time
	local pose = {}

	-- Blend weights
	local move = smooth(speed / C.RunCycleWalkSpeed) -- 0 standing, 1 walking
	local run = smooth((speed - C.RunCycleWalkSpeed) / (C.RunCycleRunSpeed - C.RunCycleWalkSpeed))
	local sprint = smooth((speed - C.RunCycleSprintSpeed) / C.RunCycleSprintBlend)

	local s = math.sin(self.phase)
	local c = math.cos(self.phase)

	-- Cartoon factor: walking stays natural, running and sprinting get pushed further
	local x = lerp(1, C.RunCycleExaggeration, run)

	-- Legs: hips swing opposite each other; the knee folds while that leg swings forward.
	-- The forward swing is bigger than the back swing, for high cartoon knees.
	local hipAmp = (lerp(0.45, 0.95, run) + 0.15 * sprint) * x
	local kneeAmp = (lerp(0.55, 1.7, run) + 0.3 * sprint) * x
	local function hip(v: number): number
		return if v > 0 then math.min(1.7, v * lerp(1, 1.3, run)) else v
	end
	local hipL = hip(s * hipAmp) * move
	local hipR = hip(-s * hipAmp) * move
	local kneeL = -math.min(2.6, 0.08 + kneeAmp * math.max(0, c)) * move
	local kneeR = -math.min(2.6, 0.08 + kneeAmp * math.max(0, -c)) * move
	local ankleL = (0.25 * s - 0.2 * run * x * math.max(0, -c)) * move
	local ankleR = (-0.25 * s - 0.2 * run * x * math.max(0, c)) * move

	-- Arms: big pumping counter-swing at run, swept far back at sprint
	local armAmp = lerp(0.35, 0.9, run) * x * move
	local swingL = -s * armAmp
	local swingR = s * armAmp
	local sweptBack = -1.15 - 0.35 * (x - 1)
	local shoulderLX = lerp(swingL, sweptBack + 0.1 * x * s, sprint)
	local shoulderRX = lerp(swingR, sweptBack - 0.1 * x * s, sprint)
	local shoulderOut = lerp(0.05, 0.2, sprint) * x
	local elbowL = lerp(lerp(0.15, 1.5, run) * move + 0.1, 0.25, sprint) * lerp(1, 1.15, run * (x - 1))
	local elbowR = elbowL

	-- Torso: lean into speed, twist against the hips, bounce on each footfall,
	-- and rock the hips side to side
	local lean = -(lerp(0.04, 0.28, run) * move + 0.22 * sprint) * x
	local twist = 0.18 * s * run * (1 - 0.5 * sprint) * x
	local bounce = (math.abs(c) - 0.5) * lerp(0.08, 0.35, run) * x * x * move
	local sway = 0.08 * s * run * (x - 1) * 2
	local breathe = (1 - move) * 0.03 * math.sin(t * 2.2)

	pose.Root = CFrame.new(0, bounce, 0) * rot(0, -twist * 0.5, sway)
	pose.Waist = rot(lean + breathe, twist, -sway * 0.6)
	pose.Neck = rot(-lean * 0.7 - breathe, -twist * 0.8, 0)
	pose.LeftShoulder = rot(shoulderLX, 0, -shoulderOut)
	pose.RightShoulder = rot(shoulderRX, 0, shoulderOut)
	pose.LeftElbow = rot(elbowL, 0, 0)
	pose.RightElbow = rot(elbowR, 0, 0)
	pose.LeftHip = rot(hipL, 0, 0)
	pose.RightHip = rot(hipR, 0, 0)
	pose.LeftKnee = rot(kneeL, 0, 0)
	pose.RightKnee = rot(kneeR, 0, 0)
	pose.LeftAnkle = rot(ankleL, 0, 0)
	pose.RightAnkle = rot(ankleR, 0, 0)

	-- Air: arms out for balance, one knee tucked, flail a little while falling
	local a = self.air
	if a > 0.001 then
		local falling = math.clamp(-verticalSpeed / 60, 0, 1)
		local flail = 0.15 * falling * math.sin(t * 14)
		local air = {
			Root = CFrame.identity,
			Waist = rot(-0.1, 0, 0),
			Neck = rot(0.15, 0, 0),
			LeftShoulder = rot(0.3 + flail, 0, -1.2),
			RightShoulder = rot(0.3 - flail, 0, 1.2),
			LeftElbow = rot(0.5, 0, 0),
			RightElbow = rot(0.5, 0, 0),
			LeftHip = rot(0.7, 0, 0),
			RightHip = rot(-0.25, 0, 0),
			LeftKnee = rot(-1.2, 0, 0),
			RightKnee = rot(-0.4, 0, 0),
			LeftAnkle = rot(0.2, 0, 0),
			RightAnkle = rot(0.2, 0, 0),
		}
		for name, cf in pose do
			pose[name] = cf:Lerp(air[name], a)
		end
	end

	return pose
end

function RunCycle:Update(dt: number, speed: number, grounded: boolean, verticalSpeed: number)
	self.time += dt
	local C = Config
	-- Smooth the speed (not the pose) so gait changes ease in without damping the swing
	self.speed += (speed - self.speed) * (1 - math.exp(-C.RunCycleSmoothing * dt))
	speed = self.speed
	-- Cadence rises quickly at first, then levels off so top speeds don't strobe
	local cadence = C.RunCycleMinCadence
		+ (C.RunCycleMaxCadence - C.RunCycleMinCadence) * (1 - math.exp(-speed / C.RunCycleCadenceSpeed))
	if grounded then
		self.phase = (self.phase + dt * cadence * 2 * math.pi) % (2 * math.pi)
	end
	self.air += ((if grounded then 0 else 1) - self.air) * (1 - math.exp(-10 * dt))

	-- Anything the Animator is still playing (avatar idles, emotes) would fight us
	if self.animator then
		for _, track in self.animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end

	self.weight += (1 - self.weight) * (1 - math.exp(-10 * dt))
	local pose = self:Pose(speed, grounded, verticalSpeed)
	for name, joint in self.motors do
		joint.Transform = CFrame.identity:Lerp(pose[name], self.weight)
	end
end

-- Clear the pose (e.g. while curled into the spin-ball); it fades back in afterwards.
function RunCycle:Reset()
	self.weight = 0
	for _, joint in self.motors do
		joint.Transform = CFrame.identity
	end
end

return RunCycle
