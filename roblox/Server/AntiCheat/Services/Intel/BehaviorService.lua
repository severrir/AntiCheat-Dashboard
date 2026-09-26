local AC = script:FindFirstAncestor("AntiCheat")
local Check = require(AC.Classes.Check)
local PlayStyle = require(AC.Classes.PlayStyle)

-- keeps a PlayStyle per player for alt detection. never flags anything itself,
-- the fingerprint goes up with every sync and the backend compares it to banned players
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
