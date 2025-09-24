local CollectionService = game:GetService('CollectionService')
local HttpService = game:GetService('HttpService')
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local Config = require(script.Parent.Parent.Config)

type ZoneInfo = {
	zone: Part,
	serverValidationPart: Part,
	claimed: Player | boolean,
	claiming: boolean?
}

local REMOTES = script.Parent.Parent:FindFirstChild('Remotes')
if not REMOTES then
	REMOTES = Instance.new('Folder')
	REMOTES.Name = 'Remotes'
	REMOTES.Parent = script.Parent.Parent
end

local function createRemote(remoteType: string, remoteName: string): Instance
	local newRemote = Instance.new(remoteType)
	newRemote.Name = remoteName
	newRemote.Parent = REMOTES
	
	return newRemote
end

local claimZoneFunc = createRemote('RemoteFunction', 'ClaimZone')
local unclaimZoneFunc = createRemote('RemoteFunction', 'UnclaimZone')

local zoneClaimedEvent = createRemote('RemoteEvent', 'ZoneClaimed')
local zoneUnclaimedEvent = createRemote('RemoteEvent', 'ZoneUnclaimed')

local PrivacySystemServer = {}

local setupZones: {[string]: ZoneInfo} = {}

local function createCustomZones(): ()
	local newZones = {}
	
	-- add any custom code here to create your zones
	--[[
		e.g.
			for _, model in workspace.Toilets:GetChildren() do
				local cf, size = model:GetBoundingBox()
				local newZone = Instance.new('Part')
				newZone.Name = model.Name .. '_Privacy_Zone'
				newZone.Anchored = true
				newZone.Size = size * 1.2
				newZone.CFrame = cf
				newZone.Transparency = 1
				newZone.CanCollide = false
				newZone.CanTouch = false
				newZone.CanQuery = true
				newZone.Anchored = true
				newZone.Parent = model
				
				table.insert(newZones, newZone)
			end
	]]
	
	for _, zone in newZones do
		CollectionService:AddTag(zone, Config.ZONE_TAG)
	end
end

function PrivacySystemServer:_getZones(): {Part}
	createCustomZones()
	
	return CollectionService:GetTagged(Config.ZONE_TAG)
end

function PrivacySystemServer:_setupZone(zone: Part): ()
	local serverValidationPart = Instance.new("Part")
	serverValidationPart.Name = "ServerValidationZone"
	serverValidationPart.Anchored = true
	serverValidationPart.CanCollide = false
	serverValidationPart.Transparency = 1
	serverValidationPart:PivotTo(zone.CFrame)
	serverValidationPart.Size = zone:GetAttribute('Server_Validation_Size') or zone.Size * Config.SERVER_VALIDATION_MULTI
	serverValidationPart.Parent = zone
	
	local offset = zone:GetAttribute('Server_Validation_Offset')
	if offset then
		serverValidationPart:PivotTo(zone.CFrame + offset)
	end

	zone.CanCollide = false
	zone.Anchored = true
	
	local zoneInfo = {
		zone = zone;
		serverValidationPart = serverValidationPart;
		claimed = false;
	}
	
	local zoneId = HttpService:GenerateGUID(false)
	zone:SetAttribute('ZoneID', zoneId)
	
	setupZones[zoneId] = zoneInfo
end

function PrivacySystemServer:_getSetupZones(): {[string]: ZoneInfo}
	return setupZones
end

function PrivacySystemServer:_checkPlayerProximity(player: Player, validationPart: Part): boolean
	local char = player.Character
	if not char then return false end
	
	local hrp = char:FindFirstChild('HumanoidRootPart')
	if not hrp then return false end
	
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = {char}
	
	local canClaim = true
	local partsInZone = workspace:GetPartsInPart(validationPart, overlapParams)
	if not partsInZone or not next(partsInZone) then 
		-- Optionally add in here a distance check if you want it to be a bit more forgiving
		canClaim = false
	end
	
	return canClaim
end

function PrivacySystemServer:_claimZone(player: Player, zoneId: string): boolean
	if typeof(zoneId) ~= 'string' or not setupZones[zoneId] then 
		warn('Failed to claim zone: Missing zone or zone not yet setup')
		return false 
	end
	
	local zoneInfo = setupZones[zoneId]
	if zoneInfo.claimed 
		or zoneInfo.claiming 
		or not zoneInfo.zone 
		or zoneInfo.zone.Parent == nil 
		or not zoneInfo.serverValidationPart 
		or zoneInfo.serverValidationPart.Parent == nil 
	then 
		return false 
	end
	
	zoneInfo.claiming = true
	
	local success, isCloseEnough = pcall(function()
		return self:_checkPlayerProximity(player, zoneInfo.serverValidationPart)
	end)

	if not success then
		zoneInfo.claiming = false
		warn("Failed to claim zone due to error: ", isCloseEnough)
		return false
	end

	if not isCloseEnough then
		zoneInfo.claiming = false
		return false
	end
	
	zoneInfo.claimed = player
	zoneInfo.claiming = false
	
	zoneInfo.zone:SetAttribute('Claimed', true)

	pcall(function()
		local playersInZone = self:_getPlayersInZone(zoneInfo)
		for _, otherPlayer in playersInZone do
			if otherPlayer == player or (zoneInfo.prevClaimed and otherPlayer.UserId == zoneInfo.prevClaimed.playerId) then continue end
			
			self:_shiftPlayerOut(otherPlayer, zoneInfo)
		end
	end)
	
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then continue end
		
		zoneClaimedEvent:FireClient(otherPlayer, zoneId)
	end
	
	return true
end

function PrivacySystemServer:_unclaimZone(player: Player, zoneId: string): boolean
	if typeof(zoneId) ~= 'string' or not setupZones[zoneId] then 
		warn('Failed to unclaim zone: Missing zone or zone not yet setup')
		return false 
	end
	
	local zoneInfo = setupZones[zoneId]
	if not zoneInfo.claimed or player ~= zoneInfo.claimed then return false end
	
	zoneInfo.prevClaimed = {
		playerId = zoneInfo.claimed.UserId;
		unclaimedTime = os.clock();
	}
	zoneInfo.claimed = false
	zoneInfo.zone:SetAttribute('Claimed', false)
	
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then continue end
		
		zoneUnclaimedEvent:FireClient(otherPlayer, zoneId)
	end
	
	return true
end

function PrivacySystemServer:_onPlayerRemoving(player: Player): ()
	for zoneId, zoneInfo in setupZones do
		if zoneInfo and zoneInfo.claimed ~= player then continue end
		
		self:_unclaimZone(player, zoneId)
	end
end

function PrivacySystemServer:_getPlayersInZone(zoneInfo: ZoneInfo): {Player}
	local playersInZone = {}
	local foundPlayers = {}
	
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	local filterDescendantsInstances = {}
	
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char or not char:FindFirstChild('HumanoidRootPart') then continue end

		pcall(function()
			table.insert(filterDescendantsInstances, char.HumanoidRootPart)
		end)
	end

	overlapParams.FilterDescendantsInstances = filterDescendantsInstances
	
	if #overlapParams.FilterDescendantsInstances == 0 then
		return playersInZone
	end
	
	local partsInZone = workspace:GetPartsInPart(zoneInfo.zone, overlapParams)
	
	for _, part in partsInZone do
		if part.Name ~= 'HumanoidRootPart' then continue end
		
		local player = Players:GetPlayerFromCharacter(part.Parent)
		if player and not foundPlayers[player] then
			foundPlayers[player] = true
			table.insert(playersInZone, player)
		end
	end
	
	return playersInZone
end

function PrivacySystemServer:_shiftPlayerOut(player: Player, zoneInfo: ZoneInfo): ()
	local char = player.Character
	if not char then return end
	
	local hrp = char:FindFirstChild('HumanoidRootPart')
	if not hrp then return end
	
	local zoneCFrame = zoneInfo.zone.CFrame
	local zoneSize = zoneInfo.zone.Size
	local playerPos = hrp.Position
	local zonePos = zoneCFrame.Position
	
	local direction = (playerPos - zonePos)
	if direction.Magnitude == 0 then
		direction = Vector3.new(0, 0, 1)
	else
		direction = direction.Unit
	end
	
	local halfSize = zoneSize * 0.5
	local localDirection = zoneCFrame:VectorToObjectSpace(direction)
	
	local xTime = math.abs(localDirection.X) > 0 and halfSize.X / math.abs(localDirection.X) or math.huge
	local zTime = math.abs(localDirection.Z) > 0 and halfSize.Z / math.abs(localDirection.Z) or math.huge
	
	local minTime = math.min(xTime, zTime)
	local exitPoint = zonePos + (direction * minTime)
	
	local safeDistance = 3
	local newPosition = exitPoint + (direction * safeDistance)
	newPosition = Vector3.new(newPosition.X, playerPos.Y, newPosition.Z)
	
	hrp.CFrame = CFrame.new(newPosition, hrp.CFrame.LookVector)
end

function PrivacySystemServer:_checkZoneIntruders(): ()
	for _zoneId, zoneInfo in setupZones do
		if not zoneInfo.claimed or typeof(zoneInfo.claimed) == 'boolean' then continue end

		local currentTime = os.clock()
		
		local playersInZone = self:_getPlayersInZone(zoneInfo)
		for _, player in playersInZone do
			if not zoneInfo.claimed 
				or player == zoneInfo.claimed 
				or (zoneInfo.prevClaimed 
					and player.UserId == zoneInfo.prevClaimed.playerId 
					and currentTime - zoneInfo.prevClaimed.unclaimedTime < 1
				) 
			then 
				continue 
			end

			self:_shiftPlayerOut(player, zoneInfo)
		end
	end
end

function PrivacySystemServer:initiate()
	local zones = self:_getZones()
	if not zones or not next(zones) then 
		warn('No privacy zones assigned')
		return 
	end
	
	CollectionService:GetInstanceRemovedSignal(Config.ZONE_TAG):Connect(function(zone)
		local zoneId = zone:GetAttribute('ZoneID')
		if not zoneId then return end
		
		setupZones[zoneId] = nil
	end)
	
	CollectionService:GetInstanceAddedSignal(Config.ZONE_TAG):Connect(function(zone)
		if not zone:IsA('Part') or not zone:IsDescendantOf(workspace) then return end
		
		self:_setupZone(zone)
	end)
	
	for _, zone in zones do
		self:_setupZone(zone)
	end
	
	claimZoneFunc.OnServerInvoke = function(...)
		return self:_claimZone(...)
	end
	
	unclaimZoneFunc.OnServerInvoke = function(...)
		return self:_unclaimZone(...)
	end
	
	Players.PlayerRemoving:Connect(function(...)
		self:_onPlayerRemoving(...)
	end)
	
	local lastCheck = 0
	RunService.Heartbeat:Connect(function()
		local currentTime = os.clock()
		if currentTime - lastCheck >= Config.ZONE_CHECK_INTERVAL then
			lastCheck = currentTime
			self:_checkZoneIntruders()
		end
	end)
end

return PrivacySystemServer
