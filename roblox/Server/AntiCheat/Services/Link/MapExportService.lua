local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AC = script:FindFirstAncestor("AntiCheat")
local Config = require(AC.Settings.Config)
local Framework = require(ReplicatedStorage.Shared.Framework)

local MapExportService = { Name = "ACMapExportService" }

local FORMAT = "v2"
local MAX_PARTS = 12000
local CHUNK = 1500
local TERRAIN_CELLS = 160
local TERRAIN_CHUNK = 3000

local SHAPES = { Block = 0, Ball = 1, Cylinder = 2, Wedge = 3, CornerWedge = 5 }

local MATERIALS = {
	[Enum.Material.Neon] = 1,
	[Enum.Material.Glass] = 2,
	[Enum.Material.Wood] = 3,
	[Enum.Material.WoodPlanks] = 3,
	[Enum.Material.Metal] = 4,
	[Enum.Material.DiamondPlate] = 4,
	[Enum.Material.CorrodedMetal] = 4,
	[Enum.Material.Foil] = 4,
	[Enum.Material.Grass] = 5,
	[Enum.Material.LeafyGrass] = 5,
	[Enum.Material.Concrete] = 6,
	[Enum.Material.Slate] = 6,
	[Enum.Material.Rock] = 6,
	[Enum.Material.Basalt] = 6,
	[Enum.Material.Asphalt] = 6,
	[Enum.Material.Pavement] = 6,
	[Enum.Material.Cobblestone] = 6,
	[Enum.Material.Granite] = 6,
	[Enum.Material.Marble] = 6,
	[Enum.Material.Brick] = 7,
	[Enum.Material.Sand] = 8,
	[Enum.Material.Sandstone] = 8,
	[Enum.Material.Ice] = 9,
	[Enum.Material.Glacier] = 9,
	[Enum.Material.ForceField] = 10,
	[Enum.Material.Fabric] = 11,
	[Enum.Material.SmoothPlastic] = 12,
}

local TERRAIN = {
	Enum.Material.Grass, Enum.Material.LeafyGrass, Enum.Material.Sand, Enum.Material.Rock, Enum.Material.Slate,
	Enum.Material.Ground, Enum.Material.Mud, Enum.Material.Snow, Enum.Material.Ice, Enum.Material.Glacier,
	Enum.Material.Sandstone, Enum.Material.Basalt, Enum.Material.Asphalt, Enum.Material.Concrete,
	Enum.Material.Pavement, Enum.Material.Cobblestone, Enum.Material.Brick, Enum.Material.WoodPlanks,
	Enum.Material.Limestone, Enum.Material.Salt, Enum.Material.CrackedLava, Enum.Material.Water,
}
local TERRAIN_INDEX = {}
for i, m in TERRAIN do
	TERRAIN_INDEX[m] = i
end

local function r2(n)
	return math.floor(n * 100 + 0.5) / 100
end

local function rgb(c)
	return math.floor(c.R * 255) * 65536 + math.floor(c.G * 255) * 256 + math.floor(c.B * 255)
end

local function isCharacterPart(part)
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function collect()
	local parts = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.98 and not d:IsA("Terrain")
			and not CollectionService:HasTag(d, "ACInternal") and not isCharacterPart(d)
			and not d:FindFirstAncestorOfClass("Tool") then
			table.insert(parts, d)
		end
	end
	table.sort(parts, function(a, b)
		local sa, sb = a.Size, b.Size
		return sa.X * sa.Y * sa.Z > sb.X * sb.Y * sb.Z
	end)
	for i = #parts, MAX_PARTS + 1, -1 do
		parts[i] = nil
	end
	return parts
end

local function shapeOf(part)
	if part:IsA("Part") then
		return SHAPES[part.Shape.Name] or 0
	elseif part:IsA("WedgePart") then
		return 3
	elseif part:IsA("CornerWedgePart") then
		return 5
	elseif part:IsA("TrussPart") then
		return 6
	end
	return 4
end

local function encode(part)
	local p, s = part.Position, part.Size
	local rx, ry, rz = part.CFrame:ToEulerAnglesXYZ()
	return {
		r2(p.X), r2(p.Y), r2(p.Z),
		r2(s.X), r2(s.Y), r2(s.Z),
		r2(rx), r2(ry), r2(rz),
		rgb(part.Color),
		shapeOf(part),
		MATERIALS[part.Material] or 0,
		math.floor(part.Transparency * 100 + 0.5),
	}
end

local function sky()
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local sun = Lighting:GetSunDirection()
	return {
		clock = r2(Lighting.ClockTime),
		ambient = rgb(Lighting.OutdoorAmbient),
		fog = rgb(Lighting.FogColor),
		fogEnd = math.min(Lighting.FogEnd, 100000),
		brightness = r2(Lighting.Brightness),
		haze = if atmo then rgb(atmo.Color) else nil,
		density = if atmo then r2(atmo.Density) else nil,
		sun = { r2(sun.X), r2(sun.Y), r2(sun.Z) },
	}
end

local function terrainGrid()
	local terrain = workspace.Terrain
	local ok, cells = pcall(terrain.CountCells, terrain)
	if not ok or cells == 0 then
		return nil
	end
	local ext = terrain.MaxExtents
	local minV = Vector3.new(ext.Min.X, ext.Min.Y, ext.Min.Z) * 4
	local maxV = Vector3.new(ext.Max.X, ext.Max.Y, ext.Max.Z) * 4
	minV = minV:Max(Vector3.one * -8192)
	maxV = maxV:Min(Vector3.one * 8192)
	local span = math.max(maxV.X - minV.X, maxV.Z - minV.Z)
	local step = math.max(4, math.ceil(span / TERRAIN_CELLS / 4) * 4)
	local cols = math.max(1, math.ceil((maxV.X - minV.X) / step))
	local rows = math.max(1, math.ceil((maxV.Z - minV.Z) / step))

	local ground = RaycastParams.new()
	ground.FilterType = Enum.RaycastFilterType.Include
	ground.FilterDescendantsInstances = { terrain }
	ground.IgnoreWater = true
	local water = RaycastParams.new()
	water.FilterType = Enum.RaycastFilterType.Include
	water.FilterDescendantsInstances = { terrain }
	water.IgnoreWater = false

	local top = maxV.Y + 8
	local down = Vector3.new(0, -(maxV.Y - minV.Y + 16), 0)
	local h, w, m = table.create(cols * rows), table.create(cols * rows), table.create(cols * rows)
	local used, casts = {}, 0
	local any = false
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local origin = Vector3.new(minV.X + (col + 0.5) * step, top, minV.Z + (row + 0.5) * step)
			local hit = workspace:Raycast(origin, down, ground)
			local surface = workspace:Raycast(origin, down, water)
			casts += 2
			if hit then
				any = true
				local idx = TERRAIN_INDEX[hit.Material] or 1
				used[idx] = hit.Material
				table.insert(h, math.floor(hit.Position.Y * 2 + 0.5) / 2)
				table.insert(m, idx)
			else
				table.insert(h, -99999)
				table.insert(m, 0)
			end
			if surface and surface.Material == Enum.Material.Water and (not hit or surface.Position.Y > hit.Position.Y + 0.5) then
				any = true
				used[22] = Enum.Material.Water
				table.insert(w, math.floor(surface.Position.Y * 2 + 0.5) / 2)
			else
				table.insert(w, -99999)
			end
			if casts >= 2000 then
				casts = 0
				task.wait()
			end
		end
	end
	if not any then
		return nil
	end

	local palette = {}
	for idx, mat in used do
		local okColor, c = pcall(terrain.GetMaterialColor, terrain, mat)
		palette[tostring(idx)] = if okColor then rgb(c) elseif mat == Enum.Material.Water then rgb(terrain.WaterColor) else 0x6a7f3f
	end
	palette["22"] = rgb(terrain.WaterColor)

	return {
		meta = {
			x0 = r2(minV.X), z0 = r2(minV.Z), step = step, cols = cols, rows = rows,
			palette = palette, water = r2(terrain.WaterTransparency),
		},
		h = h,
		w = w,
		m = m,
	}
end

function MapExportService:Init()
	self._version = "none"
	self._bounds = nil
end

function MapExportService:Version()
	return self._version
end

function MapExportService:Bounds()
	return self._bounds
end

function MapExportService:_upload(parts, minV, maxV, grid)
	local partChunks = math.ceil(#parts / CHUNK)
	local terrainChunks = if grid then math.ceil(#grid.h / TERRAIN_CHUNK) else 0
	local check = self._backend:Post({
		op = "map_check",
		place = tostring(game.PlaceId),
		version = self._version,
		total = partChunks + terrainChunks,
		bounds = { r2(minV.X), r2(minV.Y), r2(minV.Z), r2(maxV.X), r2(maxV.Y), r2(maxV.Z) },
		sky = sky(),
		terrain = grid and grid.meta,
	})
	if not check or not check.needed then
		return
	end
	for idx = 1, partChunks do
		local chunk = {}
		for i = (idx - 1) * CHUNK + 1, math.min(idx * CHUNK, #parts) do
			table.insert(chunk, encode(parts[i]))
		end
		self._backend:Post({ op = "map_chunk", place = tostring(game.PlaceId), version = self._version, idx = idx, parts = chunk })
		task.wait(0.5)
	end
	for idx = 1, terrainChunks do
		local from = (idx - 1) * TERRAIN_CHUNK + 1
		local to = math.min(idx * TERRAIN_CHUNK, #grid.h)
		self._backend:Post({
			op = "map_terrain",
			place = tostring(game.PlaceId),
			version = self._version,
			idx = idx,
			start = from - 1,
			h = table.move(grid.h, from, to, 1, {}),
			w = table.move(grid.w, from, to, 1, {}),
			m = table.move(grid.m, from, to, 1, {}),
		})
		task.wait(0.5)
	end
end

function MapExportService:Start()
	self._backend = Framework.Get("ACBackendService")

	task.delay(5, function()
		local parts = collect()
		local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, part in parts do
			minV = minV:Min(part.Position - part.Size / 2)
			maxV = maxV:Max(part.Position + part.Size / 2)
		end
		if #parts > 0 then
			self._bounds = { min = minV, max = maxV }
		end
		local okCells, cells = pcall(workspace.Terrain.CountCells, workspace.Terrain)
		local hasTerrain = okCells and cells > 0
		self._version = string.format("%d-%d-%s%s", game.PlaceVersion, #parts, FORMAT, if hasTerrain then "t" else "")
		local grid = if Config.On("MapExport") and hasTerrain then terrainGrid() else nil

		if Config.On("MapExport") and (#parts > 0 or grid) then
			if #parts == 0 then
				minV = Vector3.new(grid.meta.x0, -50, grid.meta.z0)
				maxV = minV + Vector3.new(grid.meta.cols * grid.meta.step, 100, grid.meta.rows * grid.meta.step)
			end
			self:_upload(parts, minV, maxV, grid)
		end
	end)
end

return MapExportService
