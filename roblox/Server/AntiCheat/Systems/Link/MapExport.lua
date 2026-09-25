local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

-- sends a simplified copy of the map (every anchored part as a box) so replays have a world to play in.
-- only the first server of each place version does it
local MapExport = { Name = "ACMapExport" }

local MAX_PARTS = 8000
local CHUNK = 1500
local SHAPES = { Block = 0, Ball = 1, Cylinder = 2 }

local Backend
local version = "none"
local bounds = nil

local function r2(n)
	return math.floor(n * 100 + 0.5) / 100
end

local function isCharacterPart(part)
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function collect()
	local parts = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Anchored and d.Transparency < 0.95 and not d:IsA("Terrain")
			and not CollectionService:HasTag(d, "ACInternal") and not isCharacterPart(d) then
			table.insert(parts, d)
		end
	end
	-- big stuff first, if we have to cut, cut the tiny props
	table.sort(parts, function(a, b)
		local sa, sb = a.Size, b.Size
		return sa.X * sa.Y * sa.Z > sb.X * sb.Y * sb.Z
	end)
	for i = #parts, MAX_PARTS + 1, -1 do
		parts[i] = nil
	end
	return parts
end

local function encode(part)
	local p, s = part.Position, part.Size
	local rx, ry, rz = part.CFrame:ToEulerAnglesXYZ()
	local c = part.Color
	local shape = 0
	if part:IsA("Part") then
		shape = SHAPES[part.Shape.Name] or 0
	elseif part:IsA("WedgePart") then
		shape = 3
	end
	return {
		r2(p.X), r2(p.Y), r2(p.Z),
		r2(s.X), r2(s.Y), r2(s.Z),
		r2(rx), r2(ry), r2(rz),
		math.floor(c.R * 255) * 65536 + math.floor(c.G * 255) * 256 + math.floor(c.B * 255),
		shape,
	}
end

function MapExport.Version()
	return version
end

-- used by bait coins to find "way above the map"
function MapExport.Bounds()
	return bounds
end

function MapExport:Start()
	Backend = Framework.Get("ACBackend")

	-- give the place a moment to finish loading
	task.delay(5, function()
		local parts = collect()
		local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, part in parts do
			minV = minV:Min(part.Position - part.Size / 2)
			maxV = maxV:Max(part.Position + part.Size / 2)
		end
		if #parts > 0 then
			bounds = { min = minV, max = maxV }
		end
		version = tostring(game.PlaceVersion) .. "-" .. #parts

		if not Config.On("MapExport") or #parts == 0 then
			return
		end

		local total = math.ceil(#parts / CHUNK)
		local check = Backend.Post({
			op = "map_check",
			place = tostring(game.PlaceId),
			version = version,
			total = total,
			bounds = { r2(minV.X), r2(minV.Y), r2(minV.Z), r2(maxV.X), r2(maxV.Y), r2(maxV.Z) },
		})
		if not check or not check.needed then
			return
		end

		for idx = 1, total do
			local chunk = {}
			for i = (idx - 1) * CHUNK + 1, math.min(idx * CHUNK, #parts) do
				table.insert(chunk, encode(parts[i]))
			end
			Backend.Post({ op = "map_chunk", place = tostring(game.PlaceId), version = version, idx = idx, parts = chunk })
			task.wait(0.5)
		end
	end)
end

return MapExport
