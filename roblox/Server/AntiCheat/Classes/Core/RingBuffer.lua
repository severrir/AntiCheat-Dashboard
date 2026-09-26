-- fixed size, preallocated, overwrites the oldest. no garbage in hot loops
local RingBuffer = {}
RingBuffer.__index = RingBuffer

function RingBuffer.new(size, fill)
	return setmetatable({
		size = size,
		head = 0,
		count = 0,
		items = table.create(size, fill or 0),
	}, RingBuffer)
end

function RingBuffer:Push(value)
	local head = self.head % self.size + 1
	self.head = head
	self.items[head] = value
	if self.count < self.size then
		self.count += 1
	end
end

-- 1 = newest
function RingBuffer:Get(i)
	if i > self.count then
		return nil
	end
	return self.items[(self.head - i) % self.size + 1]
end

function RingBuffer:Clear()
	self.head = 0
	self.count = 0
end

return RingBuffer
