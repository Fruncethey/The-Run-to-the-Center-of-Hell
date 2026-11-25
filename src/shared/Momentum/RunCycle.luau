-- Procedural, speed-driven run cycle for R15 and R6 characters.
-- Instead of playing a fixed animation, every frame this poses the joints
-- (the Transform of each Motor6D, or AnimationConstraint on newer avatars) from a gait cycle whose cadence, stride and posture all
-- follow the controller's speed:
--   standing  -> idle breathing
--   0-20      -> walk: short stride, relaxed arms, upright
--   20-90     -> run: long stride, high knee lift, pumping arms, forward lean, bounce
--   90+       -> sprint: deep lean, arms snapping forward and back, cadence keeps scaling with speed
--   90-200    -> overdrive: slightly longer stride and a deeper forward tilt above top speed
--   100-150   -> top speed: arms swept back behind the body, torso tipped well forward
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

-- R6 joints, each with the parent part it lives in
local R6_JOINTS = {
	RootJoint = "HumanoidRootPart",
	Neck = "Torso",
	["Left Shoulder"] = "Torso",
	["Right Shoulder"] = "Torso",
	["Left Hip"] = "Torso",
	["Right Hip"] = "Torso",
}

local function findJoint(parent: Instance?, name: string): Instance?
	local joint = parent and parent:FindFirstChild(name)
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return joint
	end
	return nil
end

-- Works on R15 and R6 rigs. Returns nil for rigs it can't drive, so the caller can fall back.
function RunCycle.new(character: Model)
	local motors = {}
	local r6 = false
	for name, partName in JOINTS do
		local joint = findJoint(character:FindFirstChild(partName), name)
		if not joint then
			motors = nil
			break
		end
		motors[name] = joint
	end
	if not motors then
		-- Try R6: same gait, mapped onto its six joints in Update
		motors = {}
		r6 = true
		for name, partName in R6_JOINTS do
			local joint = findJoint(character:FindFirstChild(partName), name)
			if not (joint and joint:IsA("Motor6D")) then
				return nil
			end
			motors[name] = joint
		end
	end
	local self = setmetatable({}, RunCycle)
	self.motors = motors
	self.r6 = r6
	if r6 then
		-- Each R6 joint's frame is rotated relative to its parts; poses are converted into it
		self.frames = {}
		for name, joint in motors do
			self.frames[name] = joint.C0.Rotation
		end
	end
	self.animator = character:FindFirstChildWhichIsA("Animator", true)
	self.phase = 0
	self.time = 0
	self.air = 0
	self.speed = 0
	self.weight = 0 -- fades the pose in after Reset (e.g. leaving the spin-ball)
	self.bank = 0 -- sideways lean into turns
	return self
end

-- Map the R15 pose onto R6. R6 has one torso part, so it takes the R15 root and
-- waist together, and the hips are countered by the waist so the legs still
-- swing from straight down. There are no knees or elbows, so those drop out.
function RunCycle:ToR6(pose)
	local torso = pose.Root * pose.Waist
	local waistInv = pose.Waist.Rotation:Inverse()
	local r6 = {
		RootJoint = torso,
		Neck = pose.Neck,
		["Left Shoulder"] = pose.LeftShoulder,
		["Right Shoulder"] = pose.RightShoulder,
		["Left Hip"] = waistInv * pose.LeftHip,
		["Right Hip"] = waistInv * pose.RightHip,
	}
	-- Poses are in the parts' own axes; express them in each joint's frame
	for name, cf in r6 do
		local f = self.frames[name]
		r6[name] = f:Inverse() * cf * f
	end
	return r6
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
	-- Overdrive: past running top speed (boosts, slopes) the same gait stretches a little
	-- further so it keeps up: longer stride, faster steps and a deeper forward tilt (arms unchanged)
	local od = self:Overdrive(speed)
	local stretch = 1 + C.RunCycleOverdriveStride * od

	local s = math.sin(self.phase)
	local c = math.cos(self.phase)

	-- Cartoon factor: walking stays natural, running and sprinting get pushed further
	local x = lerp(1, C.RunCycleExaggeration, run)

	-- Legs: hips swing opposite each other; the knee folds while that leg swings forward.
	-- The forward swing is bigger than the back swing, for high cartoon knees.
	local hipAmp = (lerp(0.45, 0.95, run) + 0.15 * sprint) * x * stretch
	local kneeAmp = (lerp(0.55, 1.7, run) + 0.3 * sprint) * x * stretch
	local function hip(v: number): number
		return if v > 0 then math.min(1.7, v * lerp(1, 1.3, run)) else v
	end
	local hipL = hip(s * hipAmp) * move
	local hipR = hip(-s * hipAmp) * move
	local kneeL = -math.min(2.6, 0.08 + kneeAmp * math.max(0, c)) * move
	local kneeR = -math.min(2.6, 0.08 + kneeAmp * math.max(0, -c)) * move
	local ankleL = (0.25 * s - 0.2 * run * x * math.max(0, -c)) * move
	local ankleR = (-0.25 * s - 0.2 * run * x * math.max(0, c)) * move

	-- Arms: one thrust forward while the other is flung back, snapping between the two in
	-- time with the stride (they hold each pose and switch quickly), and floating a little
	-- away from the shoulders, cartoon style
	local armAmp = lerp(0.35, 1.1, run) * x * move
	local snap = math.sign(s) * math.abs(s) ^ lerp(1, C.RunCycleArmSnap, run)
	local shoulderLX = -snap * armAmp
	local shoulderRX = snap * armAmp
	local shoulderOut = lerp(0.08, 0.32, run) * move
	local detach = C.RunCycleArmDetach * run * move
	local elbowL = lerp(lerp(0.15, 1.5, run) * move + 0.1, 0.25, sprint) * lerp(1, 1.15, run * (x - 1))
	local elbowR = elbowL

	-- Torso: lean into speed, twist against the hips, bounce on each footfall,
	-- and rock the hips side to side
	local lean = -(lerp(0.04, C.RunCycleRunLean, run) * move + 0.10 * sprint + C.RunCycleOverdriveLean * od) * x
	local twist = 0.18 * s * run * (1 - 0.5 * sprint) * x
	local bounce = (math.abs(c) - 0.5) * lerp(0.08, 0.35, run) * x * x * move
	local sway = 0.08 * s * run * (x - 1) * 2
	local breathe = (1 - move) * 0.03 * math.sin(t * 2.2)

	-- The whole body banks into turns like a bike, more the faster and tighter the turn
	pose.Root = CFrame.new(0, bounce, 0) * rot(0, -twist * 0.5, sway + self.bank * move)
	pose.Waist = rot(lean + breathe, twist, -sway * 0.6)
	pose.Neck = rot(-lean * 0.7 - breathe, -twist * 0.8, 0)
	-- Detached arms slide toward where they point: forward arm out in front, back arm behind
	pose.LeftShoulder = CFrame.new(0, -0.15 * detach, snap * detach) * rot(0, 0, -shoulderOut) * rot(shoulderLX, 0, 0)
	pose.RightShoulder = CFrame.new(0, -0.15 * detach, -snap * detach) * rot(0, 0, shoulderOut) * rot(shoulderRX, 0, 0)
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

-- 0 at running top speed, 1 at RunCycleOverdriveSpeed and above
function RunCycle:Overdrive(speed: number): number
	local C = Config
	return smooth((speed - C.TopSpeed) / math.max(1, C.RunCycleOverdriveSpeed - C.TopSpeed))
end

-- Top speed (boosts, slopes): the arms sweep back behind the body and the torso
-- tips further forward, blended in by k (0 = normal run, 1 = full top-speed pose)
function RunCycle:ApplyTopSpeed(pose, k: number)
	local C = Config
	local lean = C.RunCycleTopLean * k
	local back = C.RunCycleTopArmBack + 0.06 * math.sin(self.phase * 2)
	local out = C.RunCycleTopArmOut
	local armL = rot(0, 0, -out) * rot(-back, 0, 0)
	local armR = rot(0, 0, out) * rot(-back, 0, 0)
	if self.r6 then
		-- Poses here are already in each R6 joint's frame
		local function conv(name: string, cf: CFrame): CFrame
			local f = self.frames[name]
			return f:Inverse() * cf * f
		end
		pose.RootJoint = conv("RootJoint", rot(-lean, 0, 0)) * pose.RootJoint
		pose.Neck = conv("Neck", rot(lean * 0.7, 0, 0)) * pose.Neck
		-- The legs hang from the torso, so tip them back the other way to keep them under him
		pose["Left Hip"] = conv("Left Hip", rot(lean, 0, 0)) * pose["Left Hip"]
		pose["Right Hip"] = conv("Right Hip", rot(lean, 0, 0)) * pose["Right Hip"]
		pose["Left Shoulder"] = pose["Left Shoulder"]:Lerp(conv("Left Shoulder", armL), k)
		pose["Right Shoulder"] = pose["Right Shoulder"]:Lerp(conv("Right Shoulder", armR), k)
	else
		pose.Waist = rot(-lean, 0, 0) * pose.Waist
		pose.Neck = rot(lean * 0.7, 0, 0) * pose.Neck
		pose.LeftShoulder = pose.LeftShoulder:Lerp(armL, k)
		pose.RightShoulder = pose.RightShoulder:Lerp(armR, k)
		pose.LeftElbow = pose.LeftElbow:Lerp(rot(0.15, 0, 0), k)
		pose.RightElbow = pose.RightElbow:Lerp(rot(0.15, 0, 0), k)
	end
end

-- turnRate: how fast the heading is turning, radians per second (positive = left)
function RunCycle:Update(dt: number, speed: number, grounded: boolean, verticalSpeed: number, turnRate: number?)
	self.time += dt
	local C = Config
	-- Smooth the speed (not the pose) so gait changes ease in without damping the swing
	self.speed += (speed - self.speed) * (1 - math.exp(-C.RunCycleSmoothing * dt))
	local bank = math.clamp((turnRate or 0) * speed * C.RunCycleBank, -C.RunCycleBankMax, C.RunCycleBankMax)
	self.bank += (bank - self.bank) * (1 - math.exp(-8 * dt))
	speed = self.speed
	-- Cadence scales directly with speed so the animation speeds up in step with movement
	local cadence = math.min(
		C.RunCycleMaxCadence,
		C.RunCycleMinCadence + speed * C.RunCycleCadencePerSpeed
	)
	if grounded and speed > 0.1 then
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
	if self.r6 then
		pose = self:ToR6(pose)
	end
	-- Past normal running speed, blend into the arms-back top-speed pose
	local top = smooth((speed - C.RunCycleTopStart) / (C.RunCycleTopFull - C.RunCycleTopStart)) * (1 - self.air)
	if top > 0.001 then
		self:ApplyTopSpeed(pose, top)
	end
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
