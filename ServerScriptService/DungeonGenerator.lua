local ServerStorage = game:GetService("ServerStorage")

local DungeonGenerator = {}
DungeonGenerator.__index = DungeonGenerator

-- Helper function to check if two boxes overlap
local function boxesOverlap(partA, partB, sizeCheck)
	local cfA, sizeA = partA.CFrame, partA.Size
	local cfB, sizeB = partB.CFrame, partB.Size
	
	if sizeCheck then
		-- Check if the distance between the centers of the parts is greater than half the sum of their sizes
		local diff = (cfA.Position - cfB.Position).Magnitude
		local saX = math.max(sizeA.X, sizeB.X)
		local saY = math.max(sizeA.Y, sizeB.Y)
		local saZ = math.max(sizeA.Z, sizeB.Z)

		local biggestAmount = math.max(saX, saY)
		biggestAmount = math.max(biggestAmount, saZ)

		-- If that's the case, don't bother checking
		if diff > biggestAmount then
			return false
		end
	end

	-- Checks overlap along a single axis using the Separating Axis Theorem
	local function overlapOnAxis(axis)
		-- Projects a box onto the given axis
		local function project(cf, size)
			return math.abs(cf.RightVector:Dot(axis)) * size.X / 2
				+ math.abs(cf.UpVector:Dot(axis)) * size.Y / 2
				+ math.abs(cf.LookVector:Dot(axis)) * size.Z / 2
		end

		-- Distance between box centers projected onto the axis
		local distance = math.abs((cfB.Position - cfA.Position):Dot(axis))
		
		-- Check is projections overlap
		return distance <= project(cfA, sizeA) + project(cfB, sizeB) - 0.05
	end

	local axes = {
		cfA.RightVector,
		cfA.UpVector,
		cfA.LookVector,
		cfB.RightVector,
		cfB.UpVector,
		cfB.LookVector,
	}

	for _, a in ipairs({
		cfA.RightVector,
		cfA.UpVector,
		cfA.LookVector
	}) do
		for _, b in ipairs({
			cfB.RightVector,
			cfB.UpVector,
			cfB.LookVector
		}) do
			local axis = a:Cross(b)
			-- Ignore near-zero vectors 
			if axis.Magnitude > 1e-4 then
				table.insert(axes, axis.Unit)
			end
		end
	end

	-- Test overlap on every separating axis
	for _, axis in ipairs(axes) do
		if not overlapOnAxis(axis) then
			return false
		end
	end

	return true
end

-- Create a new DungeonGenerator object
function DungeonGenerator.new(dungeonType)
	local metaTable = {
		WorldFolder = ServerStorage.DungeonRooms[dungeonType],
		PlacedRooms = {},
		OpenExits = {},
		RoomCount = 0,
		-- TODO: Replace with actual dungeon data
		Quota = 75,
		MaxRooms = 150,
	}
	local self = setmetatable(metaTable, DungeonGenerator)
	
	self.GeneratedFolder = Instance.new("Folder")
	self.GeneratedFolder.Name = "GeneratedDungeon"
	self.GeneratedFolder.Parent = workspace
	
	self.EnemiesFolder = Instance.new("Folder")
	self.EnemiesFolder.Name = "Enemies"
	self.EnemiesFolder.Parent = workspace
	
	return self
end

-- Generate dungeon with given data
function DungeonGenerator:Generate(spawnPlayersOnCompletion: boolean)
	-- Clear out any existing generated data
	table.clear(self.PlacedRooms)
	table.clear(self.OpenExits)
	self.RoomCount = 0
	self.GeneratedFolder:ClearAllChildren()
	
	self:SpawnStartRoom()
	
	-- Generate rooms until quota is reached or no more exits are available
	while self.RoomCount < self.MaxRooms do
		if #self:GetPotentialExits() == 0 then
			return false
		end
		self:AttachRoom()
		-- Check if we've reached the quota and decide if generation should end early
		if self.RoomCount >= self.Quota and math.random() <= 0.1 then
			print("Reached quota and decided to end generation early")
			break
		end
		
		-- Ensure script execution time isn't exhausted
		if self.RoomCount % 100 == 0 then
			print(self.RoomCount)
			task.wait(0.1)
		end
	end
	
	-- Try to spawn the boss room, and if failed, return a fail
	local successfulBossRoom = self:PlaceBossRoom()
	if not successfulBossRoom then
		print("Failed to find position for boss room.")
		return false
	end
	self:FinalizeExits()
	
	-- Close off all unused exits
	for _, exit in ipairs(self.OpenExits) do
		self:CloseExit(exit)
	end
	
	if spawnPlayersOnCompletion then
		self:SpawnPlayers()
	end
	
	return true
end

-- Spawns the start room
function DungeonGenerator:SpawnStartRoom()
	local startRoom = self.WorldFolder.Start:GetChildren()[1]:Clone()
	startRoom:PivotTo(CFrame.new(0, 0, 0))
	
	self:FinalizeRoom(startRoom)
	
	local exits = table.clone(self.OpenExits)
	for _, exitData in ipairs(exits) do
		self:AttachHall(exitData)
	end
end

-- Registers all exits in a given room
function DungeonGenerator:RegisterExits(room: Model)
	-- Find the exits folder
	local exitsFolder = room:FindFirstChild("Exits")
	if not exitsFolder then return end
	
	-- Go through all the exits in the room and add them to the list of open exits
	for _, exit in ipairs(exitsFolder:GetChildren()) do
		exit.Transparency = 1
		table.insert(self.OpenExits, {
			ExitPart = exit,
			ParentRoom = room,
			Used = false
		})
	end
end

-- Attaches a new room to a random open exit
function DungeonGenerator:AttachRoom()
	if #self.OpenExits == 0 then return end
	
	-- Try to get a random exit that is not already used
	local exitData = self:GetNextExit()
	if not exitData then
		return
	end
	exitData.Used = true
	local exitPart = exitData.ExitPart
	
	local roomTemplates = self.WorldFolder.Normal:GetChildren()
	
	local availableRooms = table.clone(roomTemplates)
	
	-- 50% chance to force spawn a hallway, otherwise add them to the list of possible next rooms
	if math.random(100) < 50 then
		exitPart = self:AttachHall(exitData)
		if not exitPart then return end
		
		for _, eD in ipairs(self.OpenExits) do
			if eD.ExitPart == exitPart then
				exitData = eD
				break
			end
		end
		exitData.Used = true
	else
		for _, hall in ipairs(self.WorldFolder.Halls:GetChildren()) do
			table.insert(availableRooms, hall)
		end
	end
	
	local newRoom
	local cf
	local size
	
	-- While the amount of rooms left to try isn't 0
	while #availableRooms > 0 do
		-- Clone a random room and remove it from the list of available rooms
		newRoom = table.remove(availableRooms, math.random(#availableRooms)):Clone()
		newRoom.PrimaryPart = newRoom.PrimaryPart or newRoom:FindFirstChildWhichIsA("BasePart")
		
		-- Get exit
		local newRoomExit = newRoom.Exits:GetChildren()[1]
		newRoom:PivotTo(exitPart.CFrame)
		
		-- If the bounding box is colliding with another bounding box, remove the room and try again
		local bounds = newRoom.Generation.BoundingBox
		if not self:CanPlaceRoom(bounds) then
			newRoom:Destroy()
			newRoom = nil
			continue
		end
		
		break
	end
	-- If we failed to find a room to place, return
	if #availableRooms == 0 or not newRoom then
		return
	end
	
	-- Hide snap parts
	exitPart.Transparency = 1
	if newRoom.PrimaryPart then
		newRoom.PrimaryPart.Transparency = 1
	end
	-- Remove the exit from the list of open exits to ensure it can't be used again
	local removed = table.remove(self.OpenExits, table.find(self.OpenExits, exitData))
	
	self:FinalizeRoom(newRoom)
end

-- Attach a new hall to a given exit
function DungeonGenerator:AttachHall(exitData)
	local exit = exitData.ExitPart
	
	local hallTemplates = self.WorldFolder.Halls:GetChildren()
	
	local availableHalls = table.clone(hallTemplates)
	
	local newHall
	local cf
	local size

	-- While the amount of halls left to try isn't 0
	while #availableHalls > 0 do
		-- Clone a random hall and remove it from the list of available halls
		newHall = table.remove(availableHalls, math.random(#availableHalls)):Clone()
		newHall.PrimaryPart = newHall.PrimaryPart or newHall:FindFirstChildWhichIsA("BasePart")

		-- Get exit
		local newRoomExit = newHall.Exits:GetChildren()[1]
		newHall:PivotTo(exit.CFrame)

		-- If the bounding box is colliding with another bounding box, remove the room and try again
		local bounds = newHall.Generation.BoundingBox
		if not self:CanPlaceRoom(bounds) then
			newHall:Destroy()
			newHall = nil
			continue
		end

		break
	end
	-- If we failed to find a hall to place, return
	if #availableHalls == 0 or not newHall then
		return
	end
	
	-- Remove the exit from the list of open exits to ensure it can't be used again
	local removed = table.remove(self.OpenExits, table.find(self.OpenExits, exitData))

	-- Hide snap part/s
	if newHall.PrimaryPart then
		newHall.PrimaryPart.Transparency = 1
	end
	
	self:FinalizeRoom(newHall)
	return newHall.Exits:GetChildren()[1]
end

-- Common code to finalize a room's generation
function DungeonGenerator:FinalizeRoom(room)
	room.Parent = self.GeneratedFolder
	
	-- Add the room to the list of placed rooms
	local bounds = room.Generation.BoundingBox
	table.insert(self.PlacedRooms, {Bounding = bounds, Room = room})
	
	self.RoomCount += 1
	self:RegisterExits(room)
	
	self:SpawnEnemiesInRoom(room)
end

-- Places the boss room
function DungeonGenerator:PlaceBossRoom()
	if #self.OpenExits == 0 then return end
	
	local success = false
	-- While the amount of open exits is greater than 0
	while #self:GetPotentialExits() > 0 do
		-- Try to get a random open exit
		local exitData = self:GetNextExit()
		if not exitData then
			return false
		end
		exitData.Used = true
		
		-- Create the boss room object and place it in its ideal position
		local bossRoom = self.WorldFolder.Boss:GetChildren()[1]:Clone()
		local bounds = bossRoom.Generation.BoundingBox
		bossRoom:PivotTo(exitData.ExitPart.CFrame)
		
		-- If the bounding box is colliding with another bounding box, remove the room and try again
		if not self:CanPlaceRoom(bounds) then
			bossRoom:Destroy()
			continue
		end
		
		bossRoom.Parent = self.GeneratedFolder

		local bossExit = bossRoom.Exits:GetChildren()[1]

		success = true
		break
	end
	
	return success
end

-- Goes through all the left open exits and checks if they can be connected to another open exit
function DungeonGenerator:FinalizeExits()
	-- List of exits that were successfully connected to another exit
	local upForRemoval = {}
	-- List of exits that have already been checked
	local checked = {}	

	-- Go through all the open exits
	for i, exitData in ipairs(self.OpenExits) do
		checked[exitData] = {}
		-- Go through all the open exits again
		for j, exitData2 in ipairs(self.OpenExits) do
			-- Check if this combination has already been checked or if we're checking the same exit
			if (checked[exitData] and checked[exitData][exitData2]) or (checked[exitData2] and checked[exitData2][exitData]) or exitData == exitData2 then
				continue
			end
			checked[exitData][exitData2] = true
			
			-- If the position difference between the two is less than 0.1 and the random chance is less than 0.4, connect the exits
			local diff = (exitData.ExitPart.Position - exitData2.ExitPart.Position).Magnitude
			local rand = math.random()
			if diff <= 0.1 and rand <= 0.4 then
				-- Check if exits are facing each other
				local dot = exitData.ExitPart.CFrame.LookVector:Dot(exitData2.ExitPart.CFrame.LookVector)
				if dot < -0.95 then
					upForRemoval[exitData] = true
					upForRemoval[exitData2] = true
				end
			end
			
			-- Ensure script does not exhaust allowed execution time
			if j % 100 == 0 then
				task.wait(0.1)
			end
		end
		
		-- Ensure script does not exhaust allowed execution time
		if i % 100 == 0 then
			task.wait(0.1)
		end
	end
	
	-- Go through all the successfully connected exits and remove them from the OpenExits list
	for exitData in pairs(upForRemoval) do
		exitData.ExitPart.Transparency = 1
		local idx = table.find(self.OpenExits, exitData)
		if idx then
			table.remove(self.OpenExits, idx)
		end
	end
end

-- Closes a given exit
function DungeonGenerator:CloseExit(exit)
	-- TODO
	exit.ExitPart.Transparency = 0.5
end

-- Spawns enemies at all spawnpoints in a given room
function DungeonGenerator:SpawnEnemiesInRoom(room: Model)
	local spawns = room:FindFirstChild("Spawnpoints")
	if not spawns then return end
	
	local spawnedEnemies = {}
	for _, spawnPoint in ipairs(spawns:GetChildren()) do
		-- Spawnpoint has to be a part
		if not spawnPoint:IsA("BasePart") then continue end
		-- Hide spawnpoint incase it's still visible
		spawnPoint.Transparency = 1
		
		-- Get all enemy attributes
		local enemyType = spawnPoint:GetAttribute("Type") or "Melee"
		local enemy = spawnPoint:GetAttribute("Enemy")
		local amount = spawnPoint:GetAttribute("Amount") or 1
		local weight = spawnPoint:GetAttribute("Weight") or 1
		if enemy == "" then
			enemy = nil
		end
		
		-- Random chance to not spawn
		local rand = math.random()
		if rand > weight then
			continue
		end
		
		-- Spawn the enemy
		local newEnemy = self:SpawnEnemy(enemyType, spawnPoint.CFrame, enemy)
		table.insert(spawnedEnemies, newEnemy)
	end
	
	-- When a player enters the room, make all enemies inside active
	local triggered = false
	room.Generation.BoundingBox.Touched:Connect(function(prt)
		if not triggered and game.Players:GetPlayerFromCharacter(prt.Parent) then
			triggered = true
			
			for _, enemy in ipairs(spawnedEnemies) do
				enemy:SetAttribute("Dormant", false)
			end
		end
	end)
end

-- Spawn a random or given enemy at a given location
function DungeonGenerator:SpawnEnemy(enemyType, cf, enemyName)
	-- Get folder for enemy type
	local folder = ServerStorage.Enemies:FindFirstChild(enemyType)
	if not folder then return end
	
	-- If enemyName is given, then spawn that enemy
	-- Else, spawn a random one from the folder
	local enemy
	if enemyName then
		enemy = ServerStorage.Enemies:FindFirstChild(enemyName):Clone()
	else
		local enemies = folder:GetChildren()
		if #enemies == 0 then return end
		
		enemy = enemies[math.random(#enemies)]:Clone()
	end
	
	enemy:PivotTo(cf)
	enemy.Parent = self.EnemiesFolder
	
	-- Make the enemy dormant to be activated later
	enemy:SetAttribute("Dormant", true)
	
	return enemy
end

-- Checks if a room can be placed in a position
function DungeonGenerator:CanPlaceRoom(bounding)
	-- Loops through all the placed rooms and checks if the bounding box overlaps with any of them
	for _, room in ipairs(self.PlacedRooms) do
		if boxesOverlap(bounding, room.Bounding, true --[[self.RoomCount >= 500]]) then
			return false
		end
	end
	return true
end

-- Loads all the player characters
function DungeonGenerator:SpawnPlayers()
	print("spawning players")
	for _, v in ipairs(game.Players:GetPlayers()) do
		v:LoadCharacterAsync()
	end
end

-- Gets all possible exits that haven't had generation attempted on them
function DungeonGenerator:GetPotentialExits()
	local potentialExits = {}
	
	-- Add all the unattempted exits to the list of potential exits
	for _, v in ipairs(self.OpenExits) do
		if not v.Used then
			table.insert(potentialExits, v)
		end
	end
	
	return potentialExits
end

-- Gets a random open exit that hasn't had generation attempted on it
function DungeonGenerator:GetNextExit()
	local possibleExits = {}
	
	-- Add all the unattempted exits to the list of possible exits
	for _, v in ipairs(self.OpenExits) do
		if not v.Used then
			table.insert(possibleExits, v)
		end
	end
	
	-- If there are no possible exits, return nothing
	if #possibleExits == 0 then
		return nil
	end
	
	-- Return a random exit from the list of possible exits
	return possibleExits[math.random(#possibleExits)]
end

return DungeonGenerator
