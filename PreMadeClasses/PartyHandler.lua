--!nonstrict

-- Services
const MemoryStoreService = game:GetService("MemoryStoreService")
const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const TeleportService = game:GetService("TeleportService")

-- Modules

-- Variables
local partyMemoryStore = MemoryStoreService:GetHashMap("PartyMemoryStore")
local remotes = ReplicatedStorage.Remotes.Party

local PLACE_TO_TELEPORT_TO = -1
local MEMORY_EXPIRATION_TIME = (60 * 60) * 10

-- key = name, value = validator
local SettingsValidators = {
	friendsOnly = function(val: any)
		return typeof(val) == "boolean"
	end,
	maxMembers = function(val: any)
		return typeof(val) == "number" and val > 0 and val <= 4
	end,
}

local PartyHandler = {}
PartyHandler.__index = PartyHandler

---------------------------------------- Functions

----------------------------------------

type ClassProperties = {
	leader: number,
	members: { number },
	partyMetadata: { [any]: any },
	maxMembers: number,
	friendsOnly: boolean,
	isHandlingTeleporting: boolean,
}

export type PartyHandler = setmetatable<ClassProperties, typeof(PartyHandler)>

function PartyHandler.hasLeader(self: PartyHandler): boolean
	return self.leader ~= -1
end

function PartyHandler.setLeader(self: PartyHandler, leaderId: number)
	self.leader = leaderId
	remotes.OpenPartyMenu:FireClient(Players:GetPlayerByUserId(leaderId))
end

function PartyHandler.addMember(self: PartyHandler, memberId: number, dontReplicate: boolean): boolean
	dontReplicate = dontReplicate or false

	-- quick function to not repeat code.
	local function replicate()
		if dontReplicate == true then
			return
		end
		self:replicateClientDataToLeader()
	end

	if self.isHandlingTeleporting then
		return
	end

	if self.leader == memberId then
		table.insert(self.members, memberId)
		replicate()
		return true
	end

	if self.friendsOnly then
		local leaderPlayer = Players:GetPlayerByUserId(self.leader)
		if leaderPlayer:IsFriendsWithAsync(memberId) then
			table.insert(self.members, memberId)
			replicate()
			return true
		end

		return false
	else
		table.insert(self.members, memberId)
		replicate()
		return true
	end
end

function PartyHandler.isPartyFull(self: PartyHandler)
	return #self.members >= self.maxMembers
end

function PartyHandler.removeMember(self: PartyHandler, memberId: number, dontReplicate: boolean): boolean
	-- quick function to not repeat code.
	local function replicate()
		if dontReplicate == true then
			return
		end
		self:replicateClientDataToLeader()
	end

	local index = table.find(self.members, memberId)
	if not index then
		return false
	end

	table.remove(self.members, index)
	replicate()
	return true
end

function PartyHandler.replicateClientDataToLeader(self: PartyHandler)
	local leaderPlayer = Players:GetPlayerByUserId(self.leader)
	local clientData = {
		members = self.members,
		maxMembers = self.maxMembers,
		friendsOnly = self.friendsOnly,
	}
	remotes.ReplicatePartyClientDataToLeader:FireClient(leaderPlayer, clientData)
end

function PartyHandler.onSettingChanged(self: PartyHandler, settingName: string, value: any)
	if settingName == "friendsOnly" and value == true then
		local leaderPlayer = Players:GetPlayerByUserId(self.leader)
		for _, member in self.members do
			if not leaderPlayer:IsFriendsWithAsync(member) then
				-- dont replicate as we're replicating at the end
				self:removeMember(member, true)
			end
		end
	end

	-- replicate only at the end, saving some remote calls :)
	self:replicateClientDataToLeader()
end

function PartyHandler.changeSetting(self: PartyHandler, settingName: keyof<typeof(SettingsValidators)>, value: any)
	if SettingsValidators[settingName] then
		if SettingsValidators[settingName](value) then
			self[settingName] = value
			self:onSettingChanged(settingName, value)
		else
			warn("Invalid value for setting: " .. settingName)
		end
	else
		warn("Unknown setting: " .. settingName)
	end
end

function PartyHandler.isLeader(self: PartyHandler, userId: number): boolean
	return self.leader == userId
end

function PartyHandler.reInstantiateValues(self: PartyHandler)
	self.leader = -1
	self.members = {}
	self.friendsOnly = false
	self.maxMembers = 4
	self.partyMetadata = {}
	self.isHandlingTeleporting = false
end

function PartyHandler.startParty(self: PartyHandler)
	if self.isHandlingTeleporting then
		return
	end

	self.isHandlingTeleporting = true

	local playerInstances = {}
	for _, id in self.members do
		local player = Players:GetPlayerByUserId(id)
		if not player then
			self:removeMember(id, true)
			continue
		end
		table.insert(playerInstances, player)
	end

	local accessCode, serverId = TeleportService:ReserveServerAsync(PLACE_TO_TELEPORT_TO)
	partyMemoryStore:SetAsync(serverId, self.partyMetadata, MEMORY_EXPIRATION_TIME)
	TeleportService:TeleportToPrivateServer(PLACE_TO_TELEPORT_TO, accessCode, playerInstances)

	self.isHandlingTeleporting = false
end

function PartyHandler.clear(self: PartyHandler)
	local leaderPlayer = Players:GetPlayerByUserId(self.leader)
	if leaderPlayer then
		remotes.ClosePartyMenu:FireClient(leaderPlayer)
	end

	for _, id in self.members do
		self:removeMember(id, true)
	end

	self:reInstantiateValues()
end

local function new(): PartyHandler
	local self = setmetatable({} :: ClassProperties, PartyHandler)

	self:reInstantiateValues()

	return self
end

return table.freeze({
	new = new,
})
