local Rig = {}
Rig.__index = Rig

local function r2(n)
	return math.floor(n * 100 + 0.5) / 100
end

local function color(c)
	return math.floor(c.R * 255) * 65536 + math.floor(c.G * 255) * 256 + math.floor(c.B * 255)
end

local function assetId(s)
	return type(s) == "string" and tonumber(string.match(s, "(%d+)%D*$")) or nil
end

local MAX_ACCESSORIES = 12

local function joint(d)
	if d:IsA("Motor6D") then
		return d.Part0, d.Part1, d.C0, d.C1
	elseif d:IsA("AnimationConstraint") then
		local a0, a1 = d.Attachment0, d.Attachment1
		local p0 = a0 and a0.Parent
		local p1 = a1 and a1.Parent
		if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
			return p0, p1, a0.CFrame, a1.CFrame
		end
	end
	return nil
end

local function attachedTo(handle)
	for _, d in handle:GetChildren() do
		local other
		if d:IsA("JointInstance") then
			other = if d.Part0 == handle then d.Part1 else d.Part0
		elseif d:IsA("RigidConstraint") or d:IsA("WeldConstraint") then
			if d:IsA("WeldConstraint") then
				other = if d.Part0 == handle then d.Part1 else d.Part0
			else
				local a0, a1 = d.Attachment0, d.Attachment1
				local p0 = a0 and a0.Parent
				local p1 = a1 and a1.Parent
				other = if p0 == handle then p1 else p0
			end
		end
		if other and other ~= handle and other:IsA("BasePart") then
			return other
		end
	end
	return nil
end

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
		local limb = handle and attachedTo(handle)
		if limb and #acc < MAX_ACCESSORIES then
			if limb.Parent == char then
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
					w = handle:FindFirstChildOfClass("WrapLayer") ~= nil or nil,
				})
			end
		end
	end
	return clothes, acc
end

function Rig.fromCharacter(char, root)
	local rest = { [root] = CFrame.identity }
	local joints = {}
	for _, d in char:GetDescendants() do
		local p0, p1, c0, c1 = joint(d)
		if p0 and p1 and p1.Parent == char then
			table.insert(joints, { p0, p1, c0, c1 })
		end
	end
	local progressed = true
	while progressed do
		progressed = false
		for i = #joints, 1, -1 do
			local j = joints[i]
			local base = rest[j[1]]
			if base and not rest[j[2]] then
				rest[j[2]] = base * j[3] * j[4]:Inverse()
				table.remove(joints, i)
				progressed = true
			elseif rest[j[2]] then
				table.remove(joints, i)
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
			for _ = 1, 6 do
				table.insert(out, 0)
			end
		end
	end
	return out
end

return Rig
