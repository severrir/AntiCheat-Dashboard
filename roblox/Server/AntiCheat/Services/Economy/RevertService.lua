local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Framework = require(ReplicatedStorage.Shared.Framework)

local RevertService = { Name = "ACRevertService" }

function RevertService:Init()
	self._handler = nil
	self._seen = {}
end

function RevertService:OnRevert(fn)
	assert(type(fn) == "function", "OnRevert wants a function")
	self._handler = fn
end

local function fromLeaderstats(userId, summary)
	local player = Players:GetPlayerByUserId(userId)
	local stats = player and player:FindFirstChild("leaderstats")
	if not stats then
		return false, "player not in this server and no AntiCheat.OnRevert handler"
	end
	local done = {}
	for key, amount in summary.currency or {} do
		local value = stats:FindFirstChild(key)
		if value and (value:IsA("IntValue") or value:IsA("NumberValue")) and type(amount) == "number" then
			value.Value = math.max(0, value.Value - amount)
			table.insert(done, string.format("%s -%d", key, amount))
		end
	end
	local kills = stats:FindFirstChild("Kills")
	if kills and type(summary.kills) == "number" and summary.kills > 0 and (kills:IsA("IntValue") or kills:IsA("NumberValue")) then
		kills.Value = math.max(0, kills.Value - summary.kills)
		table.insert(done, string.format("Kills -%d", summary.kills))
	end
	if #done == 0 then
		return false, "nothing matched their leaderstats"
	end
	return true, "leaderstats: " .. table.concat(done, ", ")
end

function RevertService:_run(job)
	local userId = tonumber(job.user)
	local summary = if type(job.summary) == "table" then job.summary else {}
	if not userId then
		return false, "bad job"
	end
	if self._handler then
		local ok, result, note = pcall(self._handler, userId, summary)
		if not ok then
			return false, "handler errored: " .. string.sub(tostring(result), 1, 150)
		end
		return result ~= false, if type(note) == "string" then note elseif result ~= false then "done by game handler" else "handler said no"
	end
	return fromLeaderstats(userId, summary)
end

function RevertService:_onSynced(data)
	if type(data.reverts) ~= "table" then
		return
	end
	for _, job in data.reverts do
		if type(job) == "table" and type(job.id) == "number" and not self._seen[job.id] then
			self._seen[job.id] = true
			task.spawn(function()
				local ok, note = self:_run(job)
				self._backend:AckRevert(job.id, ok == true, string.sub(tostring(note or ""), 1, 200))
			end)
		end
	end
end

function RevertService:Start()
	self._backend = Framework.Get("ACBackendService")
	self._backend.Synced:Connect(function(data)
		self:_onSynced(data)
	end)
end

return RevertService
