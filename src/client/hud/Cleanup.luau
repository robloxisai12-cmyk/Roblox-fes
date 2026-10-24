--!strict
-- A scope can be cleaned repeatedly and reused after respawn/restart.
local Cleanup = {}
Cleanup.__index = Cleanup

function Cleanup.new()
	return setmetatable({ _items = {} :: { () -> () } }, Cleanup)
end

function Cleanup:Add(callback: () -> ())
	table.insert(self._items, callback)
	return callback
end

function Cleanup:Connect(signal: any, callback: any)
	local connection = signal:Connect(callback)
	self:Add(function()
		connection:Disconnect()
	end)
	return connection
end

function Cleanup:Clean()
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		items[index]()
	end
end

return Cleanup
