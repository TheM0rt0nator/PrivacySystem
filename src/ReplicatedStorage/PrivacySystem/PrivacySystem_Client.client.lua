local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local player = Players.LocalPlayer

local clientHandler = require(ReplicatedStorage.PrivacySystem.ClientModules.Client_Handler)
clientHandler:initiate()

task.wait(1)
script.Parent = player:FindFirstChild('PlayerScripts')