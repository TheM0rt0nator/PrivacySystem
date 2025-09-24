local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

Players.PlayerAdded:Connect(function(player: Player)
	local clientScriptClone = ReplicatedStorage.PrivacySystem.PrivacySystem_Client:Clone()
	clientScriptClone.Parent = player:WaitForChild('PlayerGui')
end)

for _, player in Players:GetPlayers() do
	local clientScriptClone = ReplicatedStorage.PrivacySystem.PrivacySystem_Client:Clone()
	clientScriptClone.Parent = player:WaitForChild('PlayerGui')
end

local ServerHandler = require(ReplicatedStorage.PrivacySystem.ServerModules.Server_Handler)
ServerHandler:initiate()