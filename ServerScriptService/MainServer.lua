local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonGenerator = require(ServerScriptService.DungeonGenerator)

local serverEvents = ReplicatedStorage.events.server

local curGenerator

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		char:AddTag("Damageable")
		char:AddTag("EnemyTarget")
	end)
end)

serverEvents.remoteEvents.RegenerateDungeon.OnServerEvent:Connect(function(plr, newData)
	if curGenerator then
		curGenerator:Destroy()
	end
	curGenerator = DungeonGenerator.new({
		DungeonType = "DebugDungeon",
		Quota = newData.Quota or 75,
		MaxRooms = newData.MaxRooms or 150,
	})
	curGenerator:Generate(true)
end)

repeat task.wait() until #game.Players:GetPlayers() > 0
curGenerator = DungeonGenerator.new({
	DungeonType = "DebugDungeon"
})
while not curGenerator:Generate(true) do
	task.wait()
end