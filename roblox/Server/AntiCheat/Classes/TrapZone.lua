-- a box nobody can legally be inside. the auto vault is one, every part named ACVault is another
local TrapZone = {}
TrapZone.__index = TrapZone

-- how far off a straight line into the zone a smoothed teleport can be and still count as "headed in"
local HEADING = math.cos(math.rad(4))

function TrapZone.new(cframe, size)
	return setmetatable({
		cframe = cframe,
		half = size / 2,
	}, TrapZone)
end

function TrapZone.fromPart(part)
	return TrapZone.new(part.CFrame, part.Size)
end

function TrapZone:Contains(pos)
	local p = self.cframe:PointToObjectSpace(pos)
	local h = self.half
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

-- moving from `from` to `to`, pointed straight at us
function TrapZone:IsHeadingInto(from, to)
	local dir = to - from
	local toZone = self.cframe.Position - from
	if dir.Magnitude < 1 or toZone.Magnitude < 1 then
		return false
	end
	return dir.Unit:Dot(toZone.Unit) >= HEADING
end

return TrapZone
