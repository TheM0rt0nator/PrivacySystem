local CollectionService = game:GetService('CollectionService')
local Players = game:GetService('Players')

local Config = require(script.Parent.Parent.Config)
local Zone = require(script.Parent.Parent.Libraries.Zone)

type ZoneData = {
	zonePart: Part,
	zoneObj: any,
	claimed: boolean?
}

local REMOTES = script.Parent.Parent:WaitForChild('Remotes')

local zoneClaimedEvent = REMOTES:WaitForChild('ZoneClaimed')
local zoneUnclaimedEvent = REMOTES:WaitForChild('ZoneUnclaimed')

local claimZoneFunc = REMOTES:WaitForChild('ClaimZone')
local unclaimZoneFunc = REMOTES:WaitForChild('UnclaimZone')

local player = Players.LocalPlayer

local PrivacySystemClient = {}
local SetupZones: {[string]: ZoneData} = {}
local InZones: {[string]: boolean} = {}

local function claimZone(zoneId: string): boolean
	local success = claimZoneFunc:InvokeServer(zoneId)
	if success then
		SetupZones[zoneId].claimed = true
	end
	
	return success
end

function PrivacySystemClient:_setupZones(zones: {Part}): ()
	task.delay(1, function()
		for _, zonePart in zones do
			local zoneId = zonePart:GetAttribute('ZoneID')
			if not zoneId then warn('No zone ID found for zone') end
			
			if SetupZones[zoneId] then continue end

			zonePart.CanCollide = false
			zonePart.Anchored = true
			
			local detectionPart = zonePart:Clone()
			detectionPart.Name = "PrivacyDetectionZone"
			detectionPart.Anchored = true
			detectionPart.CanCollide = false
			detectionPart.Transparency = 1
			detectionPart.Size = zonePart:GetAttribute('Client_Detection_Size') or zonePart.Size * Config.CLIENT_DETECTION_MULTI
			detectionPart.Parent = zonePart

			if detectionPart:FindFirstChild('ServerValidationZone') then
				detectionPart:FindFirstChild('ServerValidationZone'):Destroy()
			end
			
			local newZone = Zone.new(detectionPart)
			newZone.playerEntered:Connect(function(enteredPlayer)
				InZones[zoneId] = true
				if enteredPlayer ~= player or not SetupZones[zoneId] or SetupZones[zoneId].claimed then return end
				
				claimZone(zoneId)
			end)

			newZone.playerExited:Connect(function(exitedPlayer)
				InZones[zoneId] = nil
				if exitedPlayer ~= player then return end
				
				local success = unclaimZoneFunc:InvokeServer(zoneId)
				if success and SetupZones[zoneId] then
					SetupZones[zoneId].claimed = false
				end
			end)
			
			SetupZones[zoneId] = {
				zonePart = zonePart;
				zoneObj = newZone;
			}
			
			if zonePart:GetAttribute('Claimed') then
				self:_zoneClaimed(zoneId)
			end
		end
	end)
end

function PrivacySystemClient:_destroyZones(zones: {Part}): ()
	for _, zonePart in zones do
		local zoneId = zonePart:GetAttribute('ZoneID')
		if not zoneId then warn('Failed to destroy zone, no id found') end
		
		if not SetupZones[zoneId] then continue end
		
		SetupZones[zoneId].zoneObj:destroy()
		SetupZones[zoneId] = nil
	end
end

function PrivacySystemClient:_zoneClaimed(zoneId: string): ()
	if not SetupZones[zoneId] then return end
	
	SetupZones[zoneId].claimed = true
	SetupZones[zoneId].zonePart.CanCollide = true
end

function PrivacySystemClient:_zoneUnclaimed(zoneId: string): ()
	if not SetupZones[zoneId] then return end

	SetupZones[zoneId].claimed = false
	SetupZones[zoneId].zonePart.CanCollide = false
	
	if InZones[zoneId] then
		claimZone(zoneId)
	end
end

function PrivacySystemClient:initiate(): ()
	local zones = CollectionService:GetTagged(Config.ZONE_TAG)
	if zones and next(zones) then
		self:_setupZones(zones)
	end
	
	CollectionService:GetInstanceAddedSignal(Config.ZONE_TAG):Connect(function(zone)
		if not zone:IsDescendantOf(workspace) then return end
		
		self:_setupZones({zone})
	end)
	
	CollectionService:GetInstanceRemovedSignal(Config.ZONE_TAG):Connect(function(zone)
		self:_destroyZones({zone})
	end)
	
	zoneClaimedEvent.OnClientEvent:Connect(function(...)
		self:_zoneClaimed(...)
	end)
	
	zoneUnclaimedEvent.OnClientEvent:Connect(function(...)
		self:_zoneUnclaimed(...)
	end)
end

return PrivacySystemClient
