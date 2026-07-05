-- modified it a little so doing require's will be just like DataService
-- as it is very annoying to setup replica, this will simply be drag n drop with no worries :)

local RunService = game:GetService("RunService")

local ReplicaClient = require(script.ReplicaClient)
local ReplicaServer = require(script.ReplicaServer)

if RunService:IsClient() then
	ReplicaClient.RequestData()
end

return {
	client = ReplicaClient,
	server = ReplicaServer,
}