local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Check = require(AC.Classes.Check)
local BaitDummy = require(AC.Classes.BaitDummy)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- invisible dummies parked right next to players who are already looking suspicious.
-- kill aura and silent aim pick the nearest humanoid and send it straight to your hit remote,
-- so CombatService:ValidateHit sees them target something nobody can see
local BaitNpcService = Check.extend({
	Name = "ACBaitNpcService",
	Category = "Honeypot",
	Feature = "BaitNPC",
	Rate = "cold",
})

local SUSPECT = 0.25 -- share of the kick score before a player gets a bait

function BaitNpcService:Init()
	self._byProfile = {} -- profile -> BaitDummy
	self._byModel = {} -- model -> BaitDummy
end

function BaitNpcService:IsBait(model)
	return typeof(model) == "Instance" and self._byModel[model] ~= nil
end

function BaitNpcService:Tripped(profile, how)
	if profile and self:IsEnabled() then
		self._honeypot:Trip(profile, "BaitNPC:" .. how)
	end
end

function BaitNpcService:_release(profile)
	local dummy = self._byProfile[profile]
	if dummy then
		self._byProfile[profile] = nil
		self._byModel[dummy.model] = nil
		dummy:Destroy()
	end
end

function BaitNpcService:Step(profile, now)
	local root = profile.root
	local suspicious = profile:Score(now) >= Config.Thresholds.KickScore * SUSPECT
	if profile.admin or not suspicious or not root or not root.Parent then
		self:_release(profile)
		return
	end
	local dummy = self._byProfile[profile]
	if not dummy then
		dummy = BaitDummy.new(profile)
		self._byProfile[profile] = dummy
		self._byModel[dummy.model] = dummy
	end
	dummy:MoveNear(root.Position)
end

function BaitNpcService:OnStart()
	self._honeypot = Framework.Get("ACHoneypotService")
	Framework.Get("ACPlayerService").Removing:Connect(function(profile)
		self:_release(profile)
	end)
	Config.Changed:Connect(function()
		if not self:IsEnabled() then
			for profile in self._byProfile do
				self:_release(profile)
			end
		end
	end)
end

return BaitNpcService
