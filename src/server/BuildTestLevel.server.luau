-- Builds the test level when the server starts, unless one is already in Workspace
-- (for example because you generated it in Edit mode to look at or tweak).
require(script.Parent:WaitForChild("LevelBuilder")).Build()
