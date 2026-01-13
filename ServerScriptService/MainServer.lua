local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonGenerator = require(ServerScriptService.DungeonGenerator)

local serverEvents = ReplicatedStorage.events.server

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		char:AddTag("Damageable")
		char:AddTag("EnemyTarget")
	end)
end)

repeat task.wait() until #game.Players:GetPlayers() > 0
local generator = DungeonGenerator.new("DebugDungeon")
while not generator:Generate(true) do
	task.wait()
end