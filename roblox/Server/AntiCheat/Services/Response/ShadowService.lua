local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Check = require(AC.Classes.Check)
local Signal = require(AC.Classes.Signal)
local Framework = require(ReplicatedStorage.Shared.Framework)

local T = Config.Thresholds

-- shadow mode: a suspect keeps playing like nothing happened, but their hits do nothing
-- (CombatService) and their earnings are held back (LedgerService), while every check keeps
-- collecting proof. "auto" comes from the score, "staff" from the dashboard or discord.
-- staff-shadowed players don't get auto-kicked, someone asked to watch them
local ShadowService = Check.extend({
	Name = "ACShadowService",
	Category = "Shadow",
	Feature = "ShadowMode",
	Rate = "cold",
	Changed = Signal.new(), -- (player, on, by)
})

function ShadowService:IsShadowed(player)
	if not Config.On("ShadowMode") then
		return false
	end
	local profile = self._players:Get(player)
	return profile ~= nil and profile.shadow ~= nil
end

-- by: "auto" or "staff". quiet = it came from the backend, don't report it back
function ShadowService:Set(profile, by, why, quiet)
	if profile.immune or profile.shadow == by then
		return
	end
	local was = profile.shadow
	profile.shadow = by
	profile.shadowCleared = false
	self.Changed:Fire(profile.player, true, by)

	if not quiet then
		self._backend:QueueShadow(profile, true, why or "", by)
	end
	-- the moment they cross the line is the best evidence there is
	if not was and not quiet and Config.On("Replays") then
		local recording = self._recorder:Capture(profile, "capture", "shadowed: " .. (why or by))
		self._backend:Track(function()
			self._recorder:Upload(recording)
		end)
	end
end

function ShadowService:Clear(profile, quiet)
	if not profile.shadow then
		return
	end
	profile.shadow = nil
	-- a human cleared them, don't slam them straight back in on the next score tick
	profile.shadowCleared = true
	self.Changed:Fire(profile.player, false, nil)
	if not quiet then
		self._backend:QueueShadow(profile, false, "")
	end
end

function ShadowService:Step(profile, now)
	if profile.shadow or profile.shadowCleared or profile.immune or profile.kicked then
		return
	end
	local limit = T.ShadowScore
	if limit <= 0 or limit >= T.KickScore then
		return
	end
	local score = profile:Score(now)
	if score >= limit then
		local top = profile:Breakdown(now)[1]
		self:Set(profile, "auto", string.format("score %d%s", score, if top then ", mostly " .. top.check else ""))
	end
end

function ShadowService:OnStart()
	self._players = Framework.Get("ACPlayerService")
	self._backend = Framework.Get("ACBackendService")
	self._recorder = Framework.Get("ACRecorderService")

	-- shadow mode follows them into every server
	Framework.Get("ACBanService").JoinChecked:Connect(function(player, res)
		if res.shadow ~= true then
			return
		end
		local profile = self._players:Await(player)
		if profile then
			self:Set(profile, if res.shadowBy == "anticheat" then "auto" else "staff", "carried over", true)
		end
	end)
end

return ShadowService
