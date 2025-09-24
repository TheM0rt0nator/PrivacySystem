local CollectionService = game:GetService('CollectionService')
local HttpService = game:GetService('HttpService')
local Players = game:GetService('Players')

local Config = require(script.Parent.Parent.Config)

local REMOTES = script.Parent.Parent:FindFirstChild('Remotes')
if not REMOTES then
	REMOTES = Instance.new('Folder')
	REMOTES.Name = 'Remotes'
	REMOTES.Parent = script.Parent.Parent
end

local function createRemote(remoteType: string, remoteName: string): RemoteEvent
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

local setupZones = {}

local function createCustomZones(): nil
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

function PrivacySystemServer:_getZones(): {}
	createCustomZones()
	
	return CollectionService:GetTagged(Config.ZONE_TAG)
end

function PrivacySystemServer:_setupZone(zone: Part): {}
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
	
	local zoneInfo = {
		zone = zone;
		serverValidationPart = serverValidationPart;
		claimed = false;
	}
	
	local zoneId = HttpService:GenerateGUID(false)
	zone:SetAttribute('ZoneID', zoneId)
	
	setupZones[zoneId] = zoneInfo
end

function PrivacySystemServer:_getSetupZones(): {}
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
	if zoneInfo.claimed or zoneInfo.claiming then return false end
	
	zoneInfo.claiming = true
	
	local success, result = pcall(function()
		local isCloseEnough = self:_checkPlayerProximity(player, zoneInfo.serverValidationPart)
		if not isCloseEnough then 
			zoneInfo.claiming = false
			return false 
		end
		
		return true
	end)
	
	if not success then
		warn('Failed to claim zone due to error: ', result)
		return false
	elseif success and not result then
		return false
	end
	
	zoneInfo.claimed = player
	zoneInfo.claiming = false
	zoneInfo.zone:SetAttribute('Claimed', true)
	
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
	
	zoneInfo.claimed = false
	zoneInfo.zone:SetAttribute('Claimed', false)
	
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then continue end
		
		zoneUnclaimedEvent:FireClient(otherPlayer, zoneId)
	end
	
	return true
end

function PrivacySystemServer:_onPlayerRemoving(player: Player): nil
	for zoneId, zoneInfo in setupZones do
		if zoneInfo and zoneInfo.claimed ~= player then continue end
		
		self:_unclaimZone(player, zoneId)
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
end

return PrivacySystemServer
