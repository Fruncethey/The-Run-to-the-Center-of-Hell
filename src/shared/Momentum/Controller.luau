-- Momentum character controller.
-- Replaces Humanoid movement with our own velocity, slope physics, ground snapping
-- and surface alignment, so the character can run up walls and around loops.
-- The Humanoid is kept in the Physics state; every frame we write the root CFrame
-- and velocity ourselves (the client owns its character, so this replicates).

local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local WORLD_UP = Vector3.yAxis

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function projectOnPlane(v: Vector3, n: Vector3): Vector3
	return v - n * v:Dot(n)
end

local function safeUnit(v: Vector3, fallback)
	local m = v.Magnitude
	if m > 1e-5 then
		return v / m
	end
	return fallback
end

-- Rotate unit vector `dir` toward `target` around `normal`, by at most `maxAngle` radians.
local function rotateToward(dir: Vector3, target: Vector3, normal: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(dir:Dot(target), -1, 1))
	if angle <= maxAngle then
		return target
	end
	local axis = if dir:Cross(target):Dot(normal) >= 0 then normal else -normal
	return CFrame.fromAxisAngle(axis, maxAngle) * dir
end

-- How fast running can turn: sharp when slow, wide arcs at top speed.
local function runTurnRate(speed: number): number
	local t = math.clamp(speed / Config.TopSpeed, 0, 1)
	return Config.TurnRateSlow + (Config.TurnRateFast - Config.TurnRateSlow) * t
end

local function towards(a: Vector3, b: Vector3, t: number): Vector3
	if a:Dot(b) < -0.95 then
		a = (a + Vector3.new(0.1, 0, 0.05)).Unit
	end
	return safeUnit(a:Lerp(b, t), b)
end

local Controller = {}
Controller.__index = Controller

function Controller.new(character: Model, humanoid: Humanoid, root: BasePart)
	local self = setmetatable({}, Controller)
	self.character = character
	self.humanoid = humanoid
	self.root = root

	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		self.hipHeight = root.Size.Y / 2 + 2
	else
		self.hipHeight = humanoid.HipHeight + root.Size.Y / 2
	end

	self.position = root.Position
	self.velocity = Vector3.zero
	self.up = WORLD_UP
	self.visualUp = WORLD_UP
	self.facing = safeUnit(flatten(root.CFrame.LookVector), Vector3.xAxis)
	self.grounded = false
	self.groundPart = nil
	self.airGrace = 0

	self.jumping = false
	self.jumpNormal = WORLD_UP
	self.ball = false -- curled up after a jump
	self.rolling = false
	self.charging = false
	self.spinCharge = 0
	self.boosting = false
	self.heat = 0

	-- Air moves and homing attack
	self.airDashed = false
	self.stomping = false
	self.airTime = 0
	self.homingTarget = nil -- BasePart we're flying at
	self.homingTime = 0
	self.lockTarget = nil -- set each frame by the lock-on system
	self.attackTimer = 0 -- brief window after an attack where touching an enemy still defeats it
	self.hurtTimer = 0
	self.onEnemyHit = nil -- callback(part) when a homing attack connects

	self.spawnPosition = root.Position
	self.spawnFacing = self.facing

	self.input = {
		move = Vector2.zero,
		jumpHeld = false,
		jumpPressed = false,
		rollHeld = false,
		rollPressed = false,
		boostHeld = false,
	}

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	self.rayParams = params

	return self
end

function Controller:SetFacing(look: Vector3)
	local f = safeUnit(flatten(look), nil)
	if f then
		self.facing = f
		self.spawnFacing = f
	end
end

function Controller:AddIgnore(instance: Instance)
	local list = self.rayParams.FilterDescendantsInstances
	table.insert(list, instance)
	self.rayParams.FilterDescendantsInstances = list
end

function Controller:GetSpeed(): number
	return self.velocity.Magnitude
end

-- Camera-relative input, worked out on flat ground and then tilted onto the
-- surface we're standing on. Tilting (instead of projecting the camera onto the
-- surface) keeps "forward" meaning "keep going" on walls, loops and ceilings.
function Controller:GetWishDirection(camCF: CFrame, up: Vector3): Vector3
	local mv = self.input.move
	local amount = math.min(mv.Magnitude, 1)
	if amount < 0.1 then
		return Vector3.zero
	end
	local fwd = safeUnit(flatten(camCF.LookVector), nil)
		or safeUnit(flatten(camCF.UpVector), nil)
		or safeUnit(flatten(self.facing), Vector3.xAxis)
	local right = fwd:Cross(WORLD_UP)
	local wish = safeUnit(fwd * mv.Y + right * mv.X, Vector3.zero)

	if up.Y < 0.999 then
		local axis = WORLD_UP:Cross(up)
		local angle = math.acos(math.clamp(up.Y, -1, 1))
		if axis.Magnitude < 1e-3 then
			-- Upside down: flip over the axis we're travelling around
			axis = safeUnit(self.facing:Cross(up), Vector3.zAxis)
		end
		wish = projectOnPlane(CFrame.fromAxisAngle(axis.Unit, angle) * wish, up)
		wish = safeUnit(wish, Vector3.zero)
	end
	return wish * amount
end

function Controller:Step(dt: number, camCF: CFrame)
	dt = math.min(dt, 1 / 20)
	local input = self.input
	self.airGrace = math.max(0, self.airGrace - dt)
	self.attackTimer = math.max(0, self.attackTimer - dt)
	self.airTime = if self.grounded then 0 else self.airTime + dt
	self.hurtTimer = math.max(0, self.hurtTimer - dt)

	local planeUp = if self.grounded then self.up else WORLD_UP
	local wish = self:GetWishDirection(camCF, planeUp)

	-- Jump, or rev the spin-dash while charging. In the air: homing attack if an
	-- enemy is locked on, otherwise a one-time air dash.
	if input.jumpPressed then
		input.jumpPressed = false
		if self.charging then
			self.spinCharge = math.min(1, self.spinCharge + Config.SpinRevBonus)
		elseif self.grounded then
			self:Jump()
		elseif not self.homingTarget then
			if self.lockTarget then
				self:StartHoming(self.lockTarget)
			elseif not self.airDashed then
				self:AirDash(wish)
			end
		end
	end
	if input.rollPressed then
		input.rollPressed = false
		if
			not self.grounded
			and not self.homingTarget
			and not self.stomping
			and self.airTime >= Config.StompMinAirTime
		then
			self:Stomp()
		end
	end
	if self.jumping then
		local along = self.velocity:Dot(self.jumpNormal)
		if not input.jumpHeld then
			if along > Config.JumpCutSpeed then
				self.velocity -= self.jumpNormal * (along - Config.JumpCutSpeed)
			end
			self.jumping = false
		elseif along <= 0 then
			self.jumping = false
		end
	end

	self:UpdateRollAndCharge(dt, wish)
	self:UpdateBoostAndHeat(dt)

	if self.homingTarget then
		self:UpdateHoming(dt)
	elseif self.grounded then
		self:GroundMovement(dt, wish)
	else
		self:AirMovement(dt, wish)
	end

	local speed = self.velocity.Magnitude
	if speed > Config.MaxSpeed then
		self.velocity *= Config.MaxSpeed / speed
	end

	-- Integrate in substeps so high speeds never skip through geometry
	local distance = self.velocity.Magnitude * dt
	local steps = math.clamp(math.ceil(distance / Config.MaxStepDistance), 1, 16)
	local sdt = dt / steps
	for _ = 1, steps do
		self:MoveAndCollide(self.velocity * sdt)
		if self.grounded then
			self:ProbeGround(sdt)
		else
			self:ProbeLanding(sdt)
		end
		if self.homingTarget then
			self:CheckHomingHit()
		end
	end

	-- Facing follows velocity on the current plane
	local ref = if self.grounded then self.up else WORLD_UP
	local planar = projectOnPlane(self.velocity, ref)
	if planar.Magnitude > 2 and not self.charging then
		self.facing = planar.Unit
	end

	local targetUp = if self.grounded then self.up else WORLD_UP
	self.visualUp = towards(self.visualUp, targetUp, 1 - math.exp(-Config.VisualUpRate * dt))

	local killY = Workspace:GetAttribute("MomentumKillY")
	if typeof(killY) == "number" and self.position.Y < killY then
		self:Respawn()
	end
end

function Controller:Jump()
	local n = self.up
	self.velocity += n * Config.JumpPower
	self.position += n * 0.1
	self.grounded = false
	self.groundPart = nil
	self.jumping = true
	self.jumpNormal = n
	self.ball = true
	self.rolling = false
	self.airGrace = 0.1
end

function Controller:UpdateRollAndCharge(dt: number, wish: Vector3)
	if not self.grounded then
		self.charging = false
		self.spinCharge = 0
		return
	end

	if self.charging then
		if self.input.rollHeld then
			self.spinCharge = math.min(1, self.spinCharge + dt / Config.SpinChargeTime)
			self.velocity *= math.max(0, 1 - 12 * dt)
			if wish.Magnitude > 0.1 then
				self.facing = wish.Unit
			end
		else
			local dir = safeUnit(projectOnPlane(self.facing, self.up), nil)
			if dir then
				local power = Config.SpinDashMin + (Config.SpinDashMax - Config.SpinDashMin) * self.spinCharge
				self.velocity = dir * power
			end
			self.charging = false
			self.spinCharge = 0
			self.rolling = true
		end
		return
	end

	if self.input.rollHeld and not self.rolling and not self.boosting then
		local speed = self.velocity.Magnitude
		if speed < Config.SpinDashMaxStartSpeed then
			self.charging = true
			self.spinCharge = 0
		elseif speed >= Config.RollMinSpeed then
			self.rolling = true
		end
	end
end

function Controller:UpdateBoostAndHeat(dt: number)
	local speed = self.velocity.Magnitude
	local want = self.input.boostHeld
		and not self.charging
		and not self.stomping
		and self.homingTarget == nil
		and self.heat > 0
	if want and not self.boosting and self.heat < Config.BoostMinHeat then
		want = false
	end
	self.boosting = want

	if self.boosting then
		self.heat = math.max(0, self.heat - Config.BoostDrain * dt)
		self.rolling = false
		if self.grounded then
			local dir = (if speed > 1 then self.velocity / speed else nil)
				or safeUnit(projectOnPlane(self.facing, self.up), nil)
			if dir and speed < Config.BoostSpeed then
				self.velocity = dir * math.min(Config.BoostSpeed, speed + Config.BoostAccel * dt)
			end
		else
			-- Air boost pushes along your horizontal heading. Flying straight up
			-- (off the top of a wall) has no real heading, so it only slows the fall.
			local h = flatten(self.velocity)
			local hs = h.Magnitude
			if hs > 20 and hs < Config.BoostSpeed then
				h = (h / hs) * math.min(Config.BoostSpeed, hs + Config.BoostAccel * dt)
			end
			local vy = self.velocity.Y
			if vy < 0 then
				vy *= math.max(0, 1 - Config.BoostAirHold * dt)
			end
			self.velocity = Vector3.new(h.X, vy, h.Z)
		end
	else
		local over = speed - Config.HeatSpeedThreshold
		if over > 0 then
			self.heat = math.min(1, self.heat + over / Config.HeatSpeedRange * Config.HeatFillRate * dt)
		else
			self.heat = math.max(0, self.heat - Config.HeatCoolRate * dt)
		end
	end
end

function Controller:GroundMovement(dt: number, wish: Vector3)
	local n = self.up
	local vel = projectOnPlane(self.velocity, n)

	-- Gravity along the slope: this is what makes momentum matter
	local gTan = projectOnPlane(Vector3.new(0, -Config.Gravity, 0), n)
	local slope = Config.SlopeFactor
	if self.rolling then
		slope *= if gTan:Dot(vel) > 0 then Config.RollSlopeDown else Config.RollSlopeUp
	end
	if not self.charging then
		vel += gTan * slope * dt
	end

	local speed = vel.Magnitude
	local dir = if speed > 0.05 then vel / speed else nil
	local amount = wish.Magnitude
	local w = if amount > 0.05 then wish / amount else nil

	if self.charging then
		-- braking handled in UpdateRollAndCharge
	elseif self.rolling then
		-- No acceleration, a weak brake and a third of the steering, but very little friction
		if w and dir then
			if w:Dot(dir) < -0.5 then
				speed = math.max(0, speed - Config.RollBrake * amount * dt)
			else
				dir = rotateToward(dir, w, n, runTurnRate(speed) * Config.RollTurnFactor * amount * dt)
			end
		end
		speed = math.max(0, speed - Config.RollFriction * dt)
		if speed < Config.RollEndSpeed then
			self.rolling = false
		end
	elseif w then
		if not dir or speed < 3 then
			dir = w
			speed += Config.Accel * amount * dt
		else
			local along = w:Dot(dir)
			if along < -0.5 and not self.boosting then
				speed = math.max(0, speed - Config.Decel * dt)
			else
				dir = rotateToward(dir, w, n, runTurnRate(speed) * dt)
				if speed < Config.TopSpeed and not self.boosting then
					speed = math.min(Config.TopSpeed, speed + Config.Accel * amount * dt)
				end
			end
		end
	elseif not self.boosting then
		speed = math.max(0, speed - Config.Friction * dt)
	end

	-- Running can't hold onto speed past TopSpeed the way a roll can
	if not self.rolling and not self.charging and not self.boosting and speed > Config.TopSpeed then
		speed = math.max(Config.TopSpeed, speed - Config.RunOverspeedDrag * dt)
	end

	if dir then
		vel = safeUnit(projectOnPlane(dir, n), dir) * speed
	else
		vel = Vector3.zero
	end

	-- Guide surfaces (loops, corkscrews): lock direction to the part's LookVector
	local part = self.groundPart
	if part and part:GetAttribute("MomentumGuide") and vel.Magnitude > 1 then
		local look = safeUnit(projectOnPlane(part.CFrame.LookVector, n), nil)
		if look then
			local sign = if vel:Dot(look) >= 0 then 1 else -1
			vel = look * sign * vel.Magnitude
		end
	end

	self.velocity = vel
end

-- Air control: bend your flight path toward the stick (limited turn rate, so
-- speed carries you), speed up to TopSpeed, brake by pulling back, and bleed off
-- a little extra speed above TopSpeed.
function Controller:AirMovement(dt: number, wish: Vector3)
	local vel = self.velocity + Vector3.new(0, -Config.Gravity * dt, 0)
	if self.stomping then
		self.velocity = vel
		return
	end

	local h = flatten(vel)
	local hs = h.Magnitude
	local amount = wish.Magnitude
	if amount > 0.05 then
		local w = flatten(wish) / amount
		if hs > 5 then
			local dir = h / hs
			if w:Dot(dir) < -0.5 then
				hs = math.max(0, hs - Config.AirBrake * amount * dt)
			else
				dir = rotateToward(dir, w, WORLD_UP, Config.AirTurnRate * amount * dt)
				if hs < Config.TopSpeed then
					hs = math.min(Config.TopSpeed, hs + Config.AirAccel * amount * dt)
				end
			end
			h = dir * hs
		else
			h += w * Config.AirAccel * amount * dt
		end
	end

	hs = h.Magnitude
	if hs > Config.TopSpeed and not self.boosting then
		h *= math.max(Config.TopSpeed, hs - Config.AirDrag * dt) / hs
	end

	vel = Vector3.new(h.X, math.max(vel.Y, -Config.TerminalVelocity), h.Z)
	self.velocity = vel
end

function Controller:AirDash(wish: Vector3)
	local dir = safeUnit(flatten(wish), nil)
		or safeUnit(flatten(self.velocity), nil)
		or safeUnit(flatten(self.facing), Vector3.xAxis)
	local speed = math.max(flatten(self.velocity).Magnitude, Config.AirDashSpeed)
	self.velocity = dir * speed + Vector3.new(0, Config.AirDashLift, 0)
	self.facing = dir
	self.airDashed = true
	self.ball = true
	self.jumping = false
	self.attackTimer = 0.3
end

function Controller:Stomp()
	self.velocity = Vector3.new(0, -Config.StompSpeed, 0)
	self.stomping = true
	self.ball = true
	self.jumping = false
	self.boosting = false
end

function Controller:StartHoming(target: BasePart)
	self.homingTarget = target
	self.homingTime = 0
	self.ball = true
	self.jumping = false
	self.stomping = false
end

function Controller:CancelHoming()
	self.homingTarget = nil
	self.attackTimer = 0.2
end

local function targetAlive(part: BasePart?): boolean
	return part ~= nil and part.Parent ~= nil and part:IsDescendantOf(Workspace) and not part:GetAttribute("Defeated")
end

function Controller:UpdateHoming(dt: number)
	local target = self.homingTarget
	self.homingTime += dt
	if not targetAlive(target) or self.homingTime > Config.HomingMaxTime then
		self:CancelHoming()
		return
	end
	local to = target.Position - self.position
	local dir = safeUnit(to, nil)
	if dir then
		self.velocity = dir * Config.HomingSpeed
		self.facing = safeUnit(flatten(dir), self.facing)
	end
end

function Controller:CheckHomingHit()
	local target = self.homingTarget
	if target and (target.Position - self.position).Magnitude <= Config.HomingHitRadius then
		self:HomingHit(target)
	end
end

function Controller:HomingHit(target: BasePart)
	local side = safeUnit(flatten(target.Position - self.position), Vector3.zero)
	self.homingTarget = nil
	self.velocity = WORLD_UP * Config.HomingBounce + side * 12
	self.grounded = false
	self.groundPart = nil
	self.airDashed = false
	self.stomping = false
	self.ball = true
	self.attackTimer = 0.25
	self.airGrace = 0.1
	if self.onEnemyHit then
		self.onEnemyHit(target)
	end
end

-- True while touching an enemy should defeat it rather than hurt you.
function Controller:IsAttacking(): boolean
	return self.ball
		or self.rolling
		or self.charging
		or self.boosting
		or self.stomping
		or self.homingTarget ~= nil
		or self.attackTimer > 0
end

-- Defeated an enemy by touching it (jumping, rolling, boosting into it).
function Controller:BounceOff()
	if not self.grounded then
		self.velocity = Vector3.new(self.velocity.X, math.max(self.velocity.Y, Config.HomingBounce * 0.8), self.velocity.Z)
		self.airDashed = false
		self.stomping = false
	end
end

-- An enemy hit you: get knocked away and lose some heat.
function Controller:Hurt(from: Vector3)
	if self.hurtTimer > 0 then
		return
	end
	local away = safeUnit(flatten(self.position - from), nil) or -safeUnit(flatten(self.facing), Vector3.xAxis)
	self.velocity = away * Config.EnemyKnockback + WORLD_UP * 30
	self.position += WORLD_UP * 0.3
	self.grounded = false
	self.groundPart = nil
	self.rolling = false
	self.charging = false
	self.boosting = false
	self.ball = false
	self.homingTarget = nil
	self.airGrace = 0.2
	self.hurtTimer = Config.HurtInvulnerability
	self.heat = math.max(0, self.heat - Config.EnemyHeatLoss)
end

-- Sweep the body sphere along `motion`, sliding along walls and climbing onto
-- surfaces that are close enough in angle to the one we're on.
function Controller:MoveAndCollide(motion: Vector3)
	for _ = 1, 4 do
		local len = motion.Magnitude
		if len < 1e-4 then
			return
		end
		local up = if self.grounded then self.up else WORLD_UP
		local center = self.position + up * Config.BodyOffset
		local hit = Workspace:Spherecast(center, Config.BodyRadius, motion, self.rayParams)
		if not hit then
			self.position += motion
			return
		end

		local dir = motion / len
		local travel = math.max(0, hit.Distance - Config.Skin)
		self.position += dir * travel
		local rest = motion - dir * travel
		local nrm = hit.Normal

		if self.grounded and nrm:Dot(self.up) >= Config.TransitionMinDot then
			self:SetGround(nrm, hit.Instance)
			rest = safeUnit(projectOnPlane(rest, nrm), Vector3.zero) * rest.Magnitude
		elseif not self.grounded and nrm.Y >= Config.LandMinNormalY and self.velocity:Dot(nrm) < 0 then
			self:Land(nrm, hit.Instance)
			rest = projectOnPlane(rest, nrm)
		else
			local into = self.velocity:Dot(nrm)
			if into < 0 then
				self.velocity -= nrm * into
			end
			rest = projectOnPlane(rest, nrm)
			self.position += nrm * Config.Skin
		end
		motion = rest
	end
end

function Controller:ProbeGround(dt: number)
	local n = self.up
	local reach = self.hipHeight + Config.SnapDistance + self.velocity.Magnitude * dt * 0.5
	local hit = Workspace:Raycast(self.position + n, -n * (reach + 1), self.rayParams)
	if hit and hit.Normal:Dot(n) >= Config.SnapMinDot then
		self.position = hit.Position + hit.Normal * self.hipHeight
		self:SetGround(hit.Normal, hit.Instance)
		if self.up.Y < Config.SteepSurfaceY and self.velocity.Magnitude < Config.MinWallSpeed then
			self:Detach(true)
		end
	else
		self:Detach(false)
	end
end

function Controller:ProbeLanding(dt: number)
	if self.airGrace > 0 then
		return
	end
	local fall = math.max(0, -self.velocity.Y) * dt
	local hit = Workspace:Raycast(self.position + WORLD_UP, -WORLD_UP * (1 + self.hipHeight + fall + 0.05), self.rayParams)
	if hit and hit.Normal.Y >= Config.LandMinNormalY and self.velocity:Dot(hit.Normal) <= 0 then
		self.position = hit.Position + hit.Normal * self.hipHeight
		self:Land(hit.Normal, hit.Instance)
	end
end

-- Move onto a new ground surface keeping our speed (Sonic-style surface transitions).
function Controller:SetGround(n: Vector3, part: Instance?)
	if n ~= self.up then
		local speed = self.velocity.Magnitude
		self.velocity = safeUnit(projectOnPlane(self.velocity, n), Vector3.zero) * speed
	end
	self.up = n
	self.groundPart = part
	self.grounded = true
end

-- Touch down from the air: the part of our velocity going into the surface is lost.
function Controller:Land(n: Vector3, part: Instance?)
	self.velocity = projectOnPlane(self.velocity, n)
	self.up = n
	self.groundPart = part
	self.grounded = true
	self.jumping = false
	self.ball = false
	self.airDashed = false
	if self.stomping or self.homingTarget then
		self.attackTimer = 0.15 -- a stomp still flattens whatever you land next to
	end
	self.stomping = false
	self.homingTarget = nil
	self.rolling = self.input.rollHeld and self.velocity.Magnitude >= Config.RollMinSpeed
end

function Controller:Detach(pushOff: boolean)
	if pushOff then
		self.velocity += self.up * Config.DetachPush
		self.position += self.up * 0.2
	end
	self.grounded = false
	self.groundPart = nil
	self.airGrace = 0.15
	self.rolling = false
end

function Controller:Respawn()
	self.position = self.spawnPosition + Vector3.new(0, 2, 0)
	self.velocity = Vector3.zero
	self.facing = self.spawnFacing
	self.up = WORLD_UP
	self.visualUp = WORLD_UP
	self.grounded = false
	self.groundPart = nil
	self.rolling = false
	self.charging = false
	self.boosting = false
	self.ball = false
	self.airDashed = false
	self.stomping = false
	self.homingTarget = nil
	self.heat = 0
	self.respawnCount = (self.respawnCount or 0) + 1
end

-- Write our simulated state to the character. Called every frame before physics.
function Controller:Apply()
	local up = self.visualUp
	local fwd = safeUnit(projectOnPlane(self.facing, up), nil)
		or safeUnit(projectOnPlane(self.root.CFrame.LookVector, up), nil)
		or safeUnit(projectOnPlane(Vector3.xAxis, up), Vector3.zAxis)
	local right = fwd:Cross(up).Unit
	self.root.CFrame = CFrame.fromMatrix(self.position, right, up, -fwd)
	self.root.AssemblyLinearVelocity = self.velocity
	self.root.AssemblyAngularVelocity = Vector3.zero
end

return Controller
