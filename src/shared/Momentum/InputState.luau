-- Keyboard and gamepad input, collected into one table the controller reads.
--   Move: WASD / arrows / left stick
--   Jump (homing attack / air dash in the air): Space / A
--   Spin-dash & roll (stomp in the air): Q, LeftCtrl or C / X or B
--   Boost: LeftShift or E / R2 or Y
--   Respawn: R / Select

local UserInputService = game:GetService("UserInputService")

local InputState = {}
InputState.__index = InputState

local GAMEPAD = Enum.UserInputType.Gamepad1

local function anyKey(keys)
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function anyButton(buttons)
	for _, button in buttons do
		if UserInputService:IsGamepadButtonDown(GAMEPAD, button) then
			return true
		end
	end
	return false
end

function InputState.new()
	local self = setmetatable({}, InputState)
	self.state = {
		move = Vector2.zero,
		jumpHeld = false,
		jumpPressed = false,
		rollHeld = false,
		rollPressed = false,
		boostHeld = false,
	}
	self.stick = Vector2.zero
	self.respawnRequested = false

	UserInputService.InputBegan:Connect(function(io, processed)
		if processed then
			return
		end
		if io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.ButtonA then
			self.state.jumpPressed = true
		elseif
			io.KeyCode == Enum.KeyCode.Q
			or io.KeyCode == Enum.KeyCode.LeftControl
			or io.KeyCode == Enum.KeyCode.C
			or io.KeyCode == Enum.KeyCode.ButtonX
			or io.KeyCode == Enum.KeyCode.ButtonB
		then
			self.state.rollPressed = true
		elseif io.KeyCode == Enum.KeyCode.R or io.KeyCode == Enum.KeyCode.ButtonSelect then
			self.respawnRequested = true
		end
	end)

	UserInputService.InputChanged:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.Thumbstick1 then
			local p = Vector2.new(io.Position.X, io.Position.Y)
			self.stick = if p.Magnitude > 0.2 then p else Vector2.zero
		end
	end)

	return self
end

function InputState:Update()
	local s = self.state
	if UserInputService:GetFocusedTextBox() then
		s.move = Vector2.zero
		s.jumpHeld, s.rollHeld, s.boostHeld = false, false, false
		return
	end

	local x, y = 0, 0
	if anyKey({ Enum.KeyCode.W, Enum.KeyCode.Up }) then y += 1 end
	if anyKey({ Enum.KeyCode.S, Enum.KeyCode.Down }) then y -= 1 end
	if anyKey({ Enum.KeyCode.D, Enum.KeyCode.Right }) then x += 1 end
	if anyKey({ Enum.KeyCode.A, Enum.KeyCode.Left }) then x -= 1 end
	local move = Vector2.new(x, y)
	if move.Magnitude > 1 then
		move = move.Unit
	end
	if self.stick.Magnitude > move.Magnitude then
		move = self.stick
	end
	s.move = move

	s.jumpHeld = anyKey({ Enum.KeyCode.Space }) or anyButton({ Enum.KeyCode.ButtonA })
	s.rollHeld = anyKey({ Enum.KeyCode.Q, Enum.KeyCode.LeftControl, Enum.KeyCode.C })
		or anyButton({ Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonB })
	s.boostHeld = anyKey({ Enum.KeyCode.LeftShift, Enum.KeyCode.E })
		or anyButton({ Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonY })
end

return InputState
