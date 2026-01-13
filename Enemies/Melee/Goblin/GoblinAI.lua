local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")

local HitboxModule = require(game.ReplicatedStorage.modules.HitboxModule)

-- Config values
local LOCK_ON_RANGE = 50
local MAX_TIME_OUT_OF_VISION = 3
local TIME_BETWEEN_TARGET_SWITCHES = 10
local MOVE_UPDATE_RATE = 0.25

local ATTACK_RANGE = 4
local ATTACK_DAMAGE = 10
local ATTACK_SPEED = 2.5
local HITBOX_SIZE = Vector3.new(3, 4, 3)

local dormant = script.Parent:GetAttribute("Dormant")
local target = nil

-- Timer values
local timeSinceLastSeenTarget = 0
local timeSinceLastTargetSwitch = 0
local timeSinceLastAttack = ATTACK_SPEED
local timeSinceLastMoveUpdate = 0

local lastWalkToTime = 0
local lastTargetPos = nil

local humanoid: Humanoid = script.Parent:FindFirstChild("Humanoid")
local initialHealth = humanoid.Health
humanoid.Changed:Connect(function()
	-- Become active if the humanoid is damaged
	if dormant and humanoid.Health ~= initialHealth then
		script.Parent:SetAttribute("Dormant", false)
	end
	-- Destroy on death
	if humanoid.Health == 0 then
		task.wait(3)
		script.Parent:Destroy()
	end
end)

-- Change in-script value when the Dormant attribute changes
script.Parent:GetAttributeChangedSignal("Dormant"):Connect(function()
	dormant = script.Parent:GetAttribute("Dormant")
end)

-- Create a path to a given position
local function getPath(destination)
	local path = PathfindingService:CreatePath()
	path:ComputeAsync(script.Parent.HumanoidRootPart.Position, destination)
	return path
end

-- Pathfinds toward the current target
function WalkToTarget()
	if not humanoid then return end
	
	-- Create a path to just in front of the target
	local path = getPath(target.PrimaryPart.Position - ((target.PrimaryPart.Position - script.Parent.HumanoidRootPart.Position).Unit * (ATTACK_RANGE - 2)))
	local myLastWalkToTime = os.clock()
	lastWalkToTime = myLastWalkToTime
	
	if path.Status == Enum.PathStatus.Success then
		-- Move to every waypoint
		for i, waypoint in ipairs(path:GetWaypoints()) do
			if not target or dormant or lastWalkToTime ~= myLastWalkToTime then break end
			lastWalkToTime = os.clock()
			myLastWalkToTime = lastWalkToTime
			
			-- Jump if needed
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			
			humanoid:MoveTo(waypoint.Position)
			humanoid.MoveToFinished:Wait()
		end
	else
		warn("Failed to pathfind.")
	end
end

-- Clears the current target
function ClearTarget()
	target = nil
	timeSinceLastSeenTarget = 0
	lastTargetPos = nil
end

-- Verifies a target's validity
function VerifyTargetValidity(target, dt)
	if not target then return false end
	
	-- Ensure they are within range
	local distance = (script.Parent.HumanoidRootPart.Position - target.PrimaryPart.Position).Magnitude
	if distance > LOCK_ON_RANGE then
		return false
	end
	
	-- Check if they can be seen by the enemy
	local hrp = target.PrimaryPart
	local rayOrigin = script.Parent.HumanoidRootPart.Position
	local rayDirection = hrp.Position - rayOrigin
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {script.Parent}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	if raycastResult and raycastResult.Instance:IsDescendantOf(target) then
		timeSinceLastSeenTarget = 0
	else
		if dt then
			-- Increase the out of sight timer
			timeSinceLastSeenTarget += dt
			if timeSinceLastSeenTarget > MAX_TIME_OUT_OF_VISION then
				return false
			end
		else
			return false
		end
	end
	
	return true
end

-- Searches for a new valid target
function SearchForNewTarget()
	local potentialTargets = CollectionService:GetTagged("EnemyTarget")
	local closestValidTarget = nil
	local closestValidDistance = 100000
	
	-- Go through all potential targets and verify their validity
	for _, potentialTarget in potentialTargets do
		local distance = (potentialTarget.PrimaryPart.Position - script.Parent.HumanoidRootPart.Position).Magnitude
		if distance < closestValidDistance and VerifyTargetValidity(potentialTarget) then
			closestValidTarget = potentialTarget
			closestValidDistance = distance
		end
	end
	
	-- If there is a closest target, then set it as the current target
	if closestValidTarget then
		ClearTarget()
		target = closestValidTarget
	end
end

-- Attempts to attack the current target
function AttemptAttack()
	if timeSinceLastAttack < ATTACK_SPEED then return end
	
	-- Check if target is within distance
	local diff = script.Parent.HumanoidRootPart.Position - target.PrimaryPart.Position
	local distance = diff.Magnitude
	
	
	if distance <= ATTACK_RANGE then
		-- Face the character toward the target
		script.Parent.HumanoidRootPart.CFrame = CFrame.lookAt(
			script.Parent.HumanoidRootPart.Position, 
			Vector3.new(target.PrimaryPart.Position.X, script.Parent.HumanoidRootPart.Position.Y, target.PrimaryPart.Position.Z))
		
		timeSinceLastAttack = 0
		-- Create hitbox in front of HumanidRootPart
		HitboxModule.SummonOneShotHitbox(script.Parent.HumanoidRootPart.CFrame + (script.Parent.HumanoidRootPart.CFrame.LookVector * 3), HITBOX_SIZE, ATTACK_DAMAGE, 0, {script.Parent})
		return true
	end
	return false
end

game["Run Service"].Heartbeat:Connect(function(dt)
	if dormant or humanoid.Health == 0 then return end
	
	if target then
		-- Ensure target is still valid, and if not, clear it
		local valid = VerifyTargetValidity(target, dt)
		if not valid then
			ClearTarget()
			return
		end
		
		-- Periodically switch targets so we're not hard-locking onto one person
		if timeSinceLastSeenTarget >= TIME_BETWEEN_TARGET_SWITCHES then
			timeSinceLastSeenTarget = 0
			SearchForNewTarget()
		end
		
		timeSinceLastAttack += dt
		local attackSuccessful = AttemptAttack()
		
		if not attackSuccessful then
			if not lastTargetPos or lastTargetPos ~= target.PrimaryPart.Position then
				task.spawn(WalkToTarget)
				lastTargetPos = target.PrimaryPart.Position
			end
		end
	else
		SearchForNewTarget()
	end
end)
