-- a character's body parts, their rest pose and colors, so a replay can move the real avatar
-- limb by limb. the server sees animations (they replicate), so what we record is what others saw
local Rig = {}
Rig.__index = Rig

local function r2(n)
	return math.floor(n * 100 + 0.5) / 100
end

local function color(c)
	return math.floor(c.R * 255) * 65536 + math.floor(c.G * 255) * 256 + math.floor(c.B * 255)
end

-- "rbxassetid://123", "http://www.roblox.com/asset/?id=123" -> 123
local function assetId(s)
	return type(s) == "string" and tonumber(string.match(s, "(%d+)%D*$")) or nil
end

local MAX_ACCESSORIES = 12

-- classic clothing is folded onto the body in the viewer. accessories become simple shapes in their
-- texture's color: their meshes can't be downloaded without a roblox login
local function looks(char)
	local shirt = char:FindFirstChildOfClass("Shirt")
	local pants = char:FindFirstChildOfClass("Pants")
	local tee = char:FindFirstChildOfClass("ShirtGraphic")
	local head = char:FindFirstChild("Head")
	local face = head and head:FindFirstChild("face")
	local clothes = {
		shirt = shirt and assetId(shirt.ShirtTemplate),
		pants = pants and assetId(pants.PantsTemplate),
		tshirt = tee and assetId(tee.Graphic),
		face = face and face:IsA("Decal") and assetId(face.Texture),
	}

	local acc = {}
	for _, a in char:GetChildren() do
		local handle = a:IsA("Accessory") and a:FindFirstChild("Handle")
		local weld = handle and handle:FindFirstChild("AccessoryWeld")
		if weld and weld:IsA("JointInstance") and #acc < MAX_ACCESSORIES then
			local limb = if weld.Part0 == handle then weld.Part1 else weld.Part0
			if limb and limb.Parent == char then
				local off = limb.CFrame:ToObjectSpace(handle.CFrame)
				local rx, ry, rz = off:ToEulerAnglesXYZ()
				local mesh = handle:FindFirstChildOfClass("SpecialMesh")
				local tex = if handle:IsA("MeshPart") then handle.TextureID elseif mesh then mesh.TextureId else ""
				local size = handle.Size
				if mesh and not handle:IsA("MeshPart") then
					size = size * mesh.Scale
				end
				table.insert(acc, {
					l = limb.Name,
					s = { r2(size.X), r2(size.Y), r2(size.Z) },
					o = { r2(off.X), r2(off.Y), r2(off.Z), r2(rx), r2(ry), r2(rz) },
					c = color(handle.Color),
					t = assetId(tex),
					-- layered clothing wraps the body, a shape for it would hide the shirt underneath
					w = handle:FindFirstChildOfClass("WrapLayer") ~= nil or nil,
				})
			end
		end
	end
	return clothes, acc
end

-- every part hung off the root through Motor6Ds: 15 for R15, 6 for R6. accessories ride along on their limb
function Rig.fromCharacter(char, root)
	local rest = { [root] = CFrame.identity }
	local motors = {}
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 and d.Part1.Parent == char then
			table.insert(motors, d)
		end
	end
	-- walk the joint tree outwards from the root, joint by joint, ignoring the animation
	local progressed = true
	while progressed do
		progressed = false
		for i = #motors, 1, -1 do
			local m = motors[i]
			local base = rest[m.Part0]
			if base then
				rest[m.Part1] = base * m.C0 * m.C1:Inverse()
				table.remove(motors, i)
				progressed = true
			end
		end
	end

	local limbs, parts = {}, {}
	for part, cf in rest do
		if part ~= root and part:IsA("BasePart") then
			table.insert(limbs, part)
		end
	end
	table.sort(limbs, function(a, b)
		return a.Name < b.Name
	end)
	for _, part in limbs do
		local cf = rest[part]
		local rx, ry, rz = cf:ToEulerAnglesXYZ()
		local s = part.Size
		table.insert(parts, {
			n = part.Name,
			s = { r2(s.X), r2(s.Y), r2(s.Z) },
			r = { r2(cf.X), r2(cf.Y), r2(cf.Z), r2(rx), r2(ry), r2(rz) },
			c = color(part.Color),
		})
	end

	local hum = char:FindFirstChildOfClass("Humanoid")
	local clothes, acc = looks(char)
	return setmetatable({
		root = root,
		limbs = limbs,
		info = {
			type = if hum and hum.RigType == Enum.HumanoidRigType.R6 then "R6" else "R15",
			hip = r2(hum and hum.HipHeight or 2),
			root = { r2(root.Size.X), r2(root.Size.Y), r2(root.Size.Z) },
			parts = parts,
			clothes = clothes,
			acc = acc,
		},
	}, Rig)
end

-- flat list, 6 numbers per limb in `info.parts` order: offset from the root, then XYZ euler angles
function Rig:Pose()
	local rootCF = self.root.CFrame
	local out = table.create(#self.limbs * 6)
	for _, part in self.limbs do
		if part.Parent then
			local cf = rootCF:ToObjectSpace(part.CFrame)
			local rx, ry, rz = cf:ToEulerAnglesXYZ()
			table.insert(out, r2(cf.X))
			table.insert(out, r2(cf.Y))
			table.insert(out, r2(cf.Z))
			table.insert(out, r2(rx))
			table.insert(out, r2(ry))
			table.insert(out, r2(rz))
		else
			-- limb gone (deleted, blown off): park it at the root
			for _ = 1, 6 do
				table.insert(out, 0)
			end
		end
	end
	return out
end

return Rig
