local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self._handlers
	table.insert(handlers, fn)
	return {
		Disconnect = function()
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

-- a broken listener shouldn't take the anticheat down with it
function Signal:Fire(...)
	for _, fn in self._handlers do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[AntiCheat] listener error:", err)
		end
	end
end

return Signal
