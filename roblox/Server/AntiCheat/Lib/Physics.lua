-- one shared raycast setup that ignores every character, instead of building params per check
local Physics = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true
params.IgnoreWater = true

local characters = {}

local function rebuild()
	local list = table.create(#characters)
	for i, char in characters do
		list[i] = char
	end
	params.FilterDescendantsInstances = list
end

function Physics.Track(char)
	if not table.find(characters, char) then
		table.insert(characters, char)
		rebuild()
	end
end

function Physics.Untrack(char)
	local i = table.find(characters, char)
	if i then
		characters[i] = characters[#characters]
		characters[#characters] = nil
		rebuild()
	end
end

function Physics.Cast(origin, direction)
	return workspace:Raycast(origin, direction, params)
end

return Physics
