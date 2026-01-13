local HitboxModule = {}

-- Creates a hitbox part
function HitboxModule.SummonHitbox(cframe: CFrame, size: Vector3, touchedCallback, debugDisplay: boolean)
	-- Create the hitbox part
	local hitbox = script.Hitbox:Clone()
	hitbox.CFrame = cframe
	hitbox.Size = size
	hitbox.Transparency = debugDisplay and 0.5 or 1
	hitbox.Parent = workspace
	
	-- Attach a touched event even if they don't provide a callback so that GetTouchingParts can work later
	local touchedConnection = hitbox.Touched:Connect(function(prt)
		if touchedCallback then
			touchedCallback(prt)
		end
	end)
	
	local function destroy()
		if touchedConnection then
			touchedConnection:Disconnect()
		end
		if hitbox and hitbox.Parent then
			hitbox:Destroy()
		end
	end
	
	return hitbox, destroy
end

-- Summons a one shot hitbox that sticks around for 1 tick that damages anything in it
function HitboxModule.SummonOneShotHitbox(cframe: CFrame, size: Vector3, damage: number, damageDelay: number, ignore, debugDisplay: boolean)
	-- CFrame is required
	if not cframe then
		warn("CFrame was not passed into HitboxModule:SummonDamagingHitbox")
		return
	end
	
	-- Default values if not provided
	damage = damage or 1
	damageDelay = damageDelay or 0
	ignore = ignore or {}
	
	-- Create the hitbox part
	local hitbox, destroyHitbox = HitboxModule.SummonHitbox(cframe, size, nil, debugDisplay)
	
	task.spawn(function()
		if damageDelay > 0 then task.wait(damageDelay) else task.wait() end
		
		if not hitbox or not hitbox.Parent then return end
		
		local hitboxTouchingParts = hitbox:GetTouchingParts()
		local hitHumanoids = {}
		
		for _, touching in ipairs(hitboxTouchingParts) do
			local ignored = false
			-- Ensure we aren't ignoring the parent of this part
			for _, ignoring in ipairs(ignore) do
				if touching == ignoring or touching:IsDescendantOf(ignoring) then
					ignored = true
					break
				end
			end
			if ignored then
				continue
			end
			
			-- Damage humanoid
			local model = touching:FindFirstAncestorOfClass("Model")
			local humanoid = model and model:FindFirstChildOfClass("Humanoid")
			if humanoid and not hitHumanoids[humanoid] then
				humanoid:TakeDamage(damage)
				hitHumanoids[humanoid] = true
			end
		end
		
		destroyHitbox()
	end)
	
	
	
	return hitbox
end

-- Summons an Area of Effect hitbox that damages anything in it multiple times over the course of a given duration
function HitboxModule.SummonAoEDamageHitbox(cframe: CFrame, size: Vector3, damage: number, damageDelay: number, ignore, duration: number, timeBetweenDamage: number, debugDisplay: boolean)
	-- CFrame is required
	if not cframe then
		warn("CFrame was not passed into HitboxModule:SummonDamagingHitbox")
		return
	end

	-- Default values if not provided
	damage = damage or 1
	damageDelay = damageDelay or 0
	ignore = ignore or {}
	duration = duration or 1
	timeBetweenDamage = timeBetweenDamage or 0.5

	-- Create the hitbox part
	local hitbox, destroyHitbox = HitboxModule.SummonHitbox(cframe, size, nil, debugDisplay)

	task.spawn(function()
		local timeExisted = 0
		local lastTime = os.clock()
		
		if damageDelay > 0 then task.wait(damageDelay) else task.wait() end

		if not hitbox or not hitbox.Parent then return end

		local hitHumanoids = {}
		while timeExisted < duration do
			-- Increase time existed time
			local now = os.clock()
			timeExisted += now - lastTime
			lastTime = now
			
			local hitboxTouchingParts = hitbox:GetTouchingParts()

			for _, touching in ipairs(hitboxTouchingParts) do
				local ignored = false
				-- Ensure we aren't ignoring the parent of this part
				for _, ignoring in ipairs(ignore) do
					if touching == ignoring or touching:IsDescendantOf(ignoring) then
						ignored = true
						break
					end
				end
				if ignored then
					continue
				end

				-- Damage humanoid
				local model = touching:FindFirstAncestorOfClass("Model")
				local humanoid = model and model:FindFirstChildOfClass("Humanoid")
				if humanoid then
					-- Ensure all humanoids have the same time between damage
					local lastHit = hitHumanoids[humanoid]
					if not lastHit or now - lastHit >= timeBetweenDamage then
						humanoid:TakeDamage(damage)
						hitHumanoids[humanoid] = now
					end
				end
			end
			
			-- Only wait 1 tick since humanoids have individual cooldowns
			task.wait()
		end

		destroyHitbox()
	end)

	return hitbox
end

return HitboxModule
