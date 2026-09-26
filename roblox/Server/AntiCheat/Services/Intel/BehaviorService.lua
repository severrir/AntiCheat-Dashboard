local AC = script:FindFirstAncestor("AntiCheat")
local Check = require(AC.Classes.Core.Check)
local PlayStyle = require(AC.Classes.Player.PlayStyle)

local BehaviorService = Check.extend({
	Name = "ACBehaviorService",
	Category = "Behavior",
	Feature = "AltDetection",
	Rate = "cold",
})

function BehaviorService:Step(profile)
	if not profile.behavior then
		profile.behavior = PlayStyle.new()
	end
	profile.behavior:Consume(profile)
end

function BehaviorService:Fingerprint(profile)
	return profile.behavior and profile.behavior:Vector(profile.netCalls)
end

return BehaviorService
