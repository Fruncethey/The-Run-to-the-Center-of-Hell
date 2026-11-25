-- Tuning values for the momentum controller, camera and heat meter.
-- Units are studs and seconds. Tweak freely while playtesting.

local Config = {
	-- Core movement
	Gravity = 110,
	TerminalVelocity = 220,
	Accel = 55, -- ground acceleration while holding a direction
	Decel = 160, -- braking when holding against your velocity
	Friction = 35, -- ground slowdown with no input
	TopSpeed = 90, -- the fastest you can get by running on flat ground
	MaxSpeed = 320, -- hard cap (slopes, spin-dash and boost can exceed TopSpeed)
	SlopeFactor = 0.55, -- share of gravity that pushes you along slopes
	TurnRateSlow = 9, -- radians/sec when standing still
	TurnRateFast = 1.4, -- radians/sec at top speed and above

	-- Air movement
	AirAccel = 45, -- speeding up in the air (only up to TopSpeed)
	AirTurnRate = 2.2, -- radians/sec you can bend your flight path
	AirBrake = 70, -- slowdown when holding against your direction in the air
	AirDrag = 4, -- slowdown above TopSpeed while airborne (not while boosting)
	AirDashSpeed = 110, -- jump again in the air with no target locked
	AirDashLift = 8,
	StompSpeed = 170, -- roll button in the air slams you down
	StompMinAirTime = 0.25, -- so pressing roll as you crest a small bump doesn't stomp

	-- Jump
	JumpPower = 55, -- launched along the surface normal
	JumpCutSpeed = 25, -- releasing jump early caps upward speed to this

	-- Surfaces
	MinWallSpeed = 25, -- below this you peel off walls, ceilings and loop tops
	SteepSurfaceY = 0.5, -- a surface whose normal.Y is below this counts as a wall
	LandMinNormalY = 0.55, -- from the air you only land on surfaces flatter than this
	SnapDistance = 2.5, -- how far below your feet the ground probe reaches
	SnapMinDot = 0.5, -- largest surface angle change (60 deg) the ground snap follows
	TransitionMinDot = 0.64, -- largest angle change (50 deg) you can run straight into
	DetachPush = 6,
	BodyRadius = 1.2,
	BodyOffset = 0.5,
	Skin = 0.05,
	MaxStepDistance = 2, -- physics substeps so fast movement never tunnels
	VisualUpRate = 12,

	-- Rolling and spin-dash
	-- Rolling keeps momentum better than running but steers and brakes worse,
	-- and holding forward doesn't speed you up: slopes are your engine.
	RollMinSpeed = 20, -- hold the roll button above this speed to curl up
	RollEndSpeed = 8, -- uncurl below this speed
	RollFriction = 4, -- running sheds speed above TopSpeed much faster (RunOverspeedDrag)
	RollTurnFactor = 0.35, -- share of running's turn rate you keep while rolling
	RollBrake = 30, -- holding back while rolling (running brakes at Decel)
	RollSlopeDown = 2.0, -- rolling downhill gains twice the speed running does
	RollSlopeUp = 0.5, -- and loses half as much going uphill
	RunOverspeedDrag = 25, -- running above TopSpeed (not boosting) bleeds back down to it
	SpinDashMaxStartSpeed = 20,
	SpinChargeTime = 0.9, -- seconds of holding for a full charge
	SpinRevBonus = 0.25, -- each jump tap while charging adds this much charge
	SpinDashMin = 60,
	SpinDashMax = 160,

	-- Heat meter and boost
	HeatSpeedThreshold = 50, -- heat builds above this speed
	HeatSpeedRange = 100,
	HeatFillRate = 0.35,
	HeatCoolRate = 0.03,
	BoostDrain = 0.3, -- heat per second while boosting
	BoostMinHeat = 0.15, -- heat needed to start a boost
	BoostSpeed = 170,
	BoostAccel = 500,
	BoostAirHold = 4, -- boosting in the air slows your fall

	-- Chase camera
	CamDistance = 14,
	CamMaxDistance = 28,
	CamHeight = 3,
	CamPitch = -0.25,
	CamSpeedForMax = 200,
	CamFollowRate = 3,
	CamFollowMinSpeed = 12,
	CamManualHold = 1.2, -- seconds the auto-follow waits after you move the camera
	CamSensitivity = 0.004,
	GamepadCamSpeed = 3,
	FovBase = 70,
	FovMax = 95,
	FovBoostKick = 8,

	-- Homing attack and enemies
	HomingRange = 75, -- how far away an enemy can be locked onto
	HomingConeDot = 0.2, -- how far off your heading it can be (cosine of the angle)
	HomingSpeed = 190,
	HomingHitRadius = 4.5,
	HomingMaxTime = 1.0, -- give up if the target hasn't been reached by then
	HomingBounce = 55, -- upward pop after a hit, so you can chain to the next one
	EnemyContactRadius = 2.6, -- added to the enemy's own radius
	EnemyKnockback = 45,
	EnemyHeatLoss = 0.25, -- heat lost when an enemy hits you
	HurtInvulnerability = 1.2, -- seconds you can't be hit again

	-- Procedural run cycle (R15)
	RunCycleWalkSpeed = 20, -- full walk stride by this speed
	RunCycleRunSpeed = 60, -- full run (knee lift, arm pump, lean) by this speed
	RunCycleSprintSpeed = 100, -- arms start sweeping back here
	RunCycleSprintBlend = 50, -- ...and are fully back this much faster
	RunCycleMinCadence = 1.4, -- steps cycles per second at walking pace
	RunCycleMaxCadence = 5, -- cap so the legs don't strobe at 300 speed
	RunCycleCadenceSpeed = 70, -- how quickly cadence climbs toward the cap
	RunCycleSmoothing = 8, -- how fast the gait follows speed changes

	CollisionGroup = "MomentumPlayer",
}

return Config
