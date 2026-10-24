--!strict
-- Pure layout math for the open-world HUD. No Roblox APIs: every rectangle is in effective pixels,
-- top-left anchored, relative to the usable ScreenGui area (CoreUISafeInsets already applied).
-- The view applies these rectangles and the tests prove they stay on screen and never overlap.
export type Rect = { X: number, Y: number, W: number, H: number }
export type Box = { Name: string, Rect: Rect, Visible: boolean }

local HUDLayout = {}

local MARGIN = 12
local GAP = 6
local BUTTON = 44
local TOP = 8
local SLOT = 44
local TAPE_H = 26
local ZONE_H = 24
local DRIVE_W, DRIVE_H = 64, 56
local MENU_ITEM_W, MENU_ITEM_H, MENU_ITEM_GAP = 150, 40, 4
local JUMP_ZONE_W, JUMP_ZONE_H = 136, 100
local THUMB_ZONE_W, THUMB_ZONE_H = 150, 130

-- Ids are owned here so the view, controller and tests agree on order.
HUDLayout.MenuColumn = table.freeze({ "squad", "inventory", "logistics", "mission" })
HUDLayout.MenuRow = table.freeze({ "squad", "logistics", "mission", "inventory" })
HUDLayout.SlotsRegular = table.freeze({ "Rifle", "Sidearm", "Bandage", "Medkit", "Inventory" })
HUDLayout.SlotsCompact = table.freeze({ "Rifle", "Sidearm", "Bandage", "Medkit" })

local function rect(x: number, y: number, w: number, h: number): Rect
	return { X = math.floor(x + 0.5), Y = math.floor(y + 0.5), W = math.floor(w + 0.5), H = math.floor(h + 0.5) }
end

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function sanitize(width: number, height: number): (number, number)
	if not finite(width) or not finite(height) or width <= 0 or height <= 0 then
		return 1280, 720
	end
	return width, height
end

function HUDLayout.Overlaps(a: Rect, b: Rect): boolean
	return a.X < b.X + b.W and b.X < a.X + a.W and a.Y < b.Y + b.H and b.Y < a.Y + a.H
end

function HUDLayout.Inside(r: Rect, width: number, height: number): boolean
	return r.X >= 0 and r.Y >= 0 and r.X + r.W <= width and r.Y + r.H <= height
end

function HUDLayout.Profile(width: number, height: number)
	local w, h = sanitize(width, height)
	local regular = w >= 700 and h >= 600
	return {
		Regular = regular,
		Compact = not regular,
		Narrow = w < 600,
		ButtonSize = BUTTON,
	}
end

export type Options = { Mode: string?, ChatExpanded: boolean?, Touch: boolean? }

function HUDLayout.Compute(width: number, height: number, options: Options?): any
	local w, h = sanitize(width, height)
	local opts: Options = options or {}
	local profile = HUDLayout.Profile(w, h)
	local compact, narrow = profile.Compact, profile.Narrow
	local mode = opts.Mode or "walking"
	local driving = mode == "driving"
	local touch = opts.Touch ~= false
	local chatExpanded = if opts.ChatExpanded ~= nil then opts.ChatExpanded else not compact

	-- Right column -----------------------------------------------------------------------------
	local rw = if compact then math.clamp(math.floor(w * 0.27), 188, 232) else 264
	local rx = w - MARGIN - rw
	local statusH = if compact then 46 else 58
	local weaponH = if compact then 40 else 64
	local vehicleH = if compact then 60 else 96

	-- Compass: centred when there is room between both columns, otherwise on its own second row.
	local leftBlock = MARGIN + 2 * BUTTON + GAP
	local rightBlock = rw + MARGIN
	local avail = w - 2 * (math.max(leftBlock, rightBlock) + 8)
	local secondRow = narrow or avail < 140
	local compassW, compassY
	if secondRow then
		compassY = math.max(TOP + BUTTON + GAP, TOP + statusH + GAP)
		compassW = math.min(w - 2 * MARGIN, 300)
	else
		compassY = TOP
		compassW = math.min(avail, if compact then 280 else 340)
	end
	local compassX = (w - compassW) / 2
	local compassBottom = compassY + TAPE_H + 4 + ZONE_H
	local zoneW = math.min(compassW, 280)

	local weaponY = if secondRow then compassBottom + GAP else TOP + statusH + GAP
	local hotbarY = weaponY + weaponH + GAP
	local slotIds = if compact then HUDLayout.SlotsCompact else HUDLayout.SlotsRegular
	local slotCount = #slotIds
	local spacing = (rw - slotCount * SLOT) / (slotCount - 1)
	local slots: { Rect } = {}
	for index = 1, slotCount do
		slots[index] = rect(rx + (index - 1) * (SLOT + spacing), hotbarY, SLOT, SLOT)
	end

	-- Left column ------------------------------------------------------------------------------
	local chatW = if narrow
		then math.min(320, w - 2 * MARGIN)
		elseif compact then math.min(300, math.floor(w * 0.38))
		else math.min(340, math.floor(w * 0.30))
	local chatY = if secondRow then compassBottom + GAP else 66
	-- Short phones shrink the chat so it never reaches the native thumbstick area.
	local chatH = if compact then math.clamp(h - THUMB_ZONE_H - chatY, 64, 104) else 124
	local leftTop
	if chatExpanded then
		leftTop = chatY + chatH + GAP
	elseif secondRow then
		leftTop = compassBottom + GAP
	else
		leftTop = TOP + BUTTON + GAP
	end
	local menuH = #HUDLayout.MenuColumn * MENU_ITEM_H + (#HUDLayout.MenuColumn - 1) * MENU_ITEM_GAP
	local mapSize
	if compact then
		mapSize = math.clamp((h - THUMB_ZONE_H) - leftTop, 72, 96)
	else
		mapSize = math.clamp((h - THUMB_ZONE_H) - leftTop - menuH - 2 * GAP, 96, 140)
	end
	local mapRect = rect(MARGIN, leftTop, mapSize, mapSize)
	-- Radio shortcut hugs the map; on very narrow screens it drops below the map to clear the right column.
	local radioBeside = MARGIN + mapSize + GAP + BUTTON + 8 <= rx
	local radioRect = if radioBeside
		then rect(MARGIN + mapSize + GAP, leftTop + mapSize - BUTTON, BUTTON, BUTTON)
		else rect(MARGIN, leftTop + mapSize + GAP, BUTTON, BUTTON)

	local menuItems: { { Id: string, Rect: Rect } } = {}
	if not compact then
		local y = leftTop + mapSize + GAP
		for index, id in ipairs(HUDLayout.MenuColumn) do
			menuItems[index] = {
				Id = id,
				Rect = rect(MARGIN, y + (index - 1) * (MENU_ITEM_H + MENU_ITEM_GAP), MENU_ITEM_W, MENU_ITEM_H),
			}
		end
	end

	local shortcuts: { { Id: string, Rect: Rect } } = {}
	if compact then
		local startX = MARGIN + 2 * (BUTTON + GAP)
		local limit = if secondRow then rx - 8 else compassX - 8
		local count = math.clamp(math.floor((limit - startX + GAP) / (BUTTON + GAP)), 0, #HUDLayout.MenuRow)
		for index = 1, count do
			shortcuts[index] = {
				Id = HUDLayout.MenuRow[index],
				Rect = rect(startX + (index - 1) * (BUTTON + GAP), TOP, BUTTON, BUTTON),
			}
		end
	end

	-- Bottom controls --------------------------------------------------------------------------
	-- Fire sits left of Roblox's jump button; reload sits beside it. Very narrow portrait screens have no
	-- room between the thumbstick and jump areas, so both stack above the jump area instead.
	local fireSize, reloadSize = 64, 48
	local stacked = w < THUMB_ZONE_W + 8 + reloadSize + 8 + fireSize + 8 + JUMP_ZONE_W
	local fire, reload
	if stacked then
		fire = rect(w - MARGIN - fireSize, h - JUMP_ZONE_H - 8 - fireSize, fireSize, fireSize)
		reload = rect(fire.X + (fireSize - reloadSize) / 2, fire.Y - 8 - reloadSize, reloadSize, reloadSize)
	else
		fire = rect(w - JUMP_ZONE_W - 8 - fireSize, h - 20 - fireSize, fireSize, fireSize)
		reload = rect(fire.X - 8 - reloadSize, h - 20 - reloadSize, reloadSize, reloadSize)
	end

	local row0, row1 = h - 12 - 2 * DRIVE_H - 8, h - 12 - DRIVE_H
	local drive: { [string]: Rect } = {
		Forward = rect(w - 80, row0, DRIVE_W, DRIVE_H),
		Reverse = rect(w - 80, row1, DRIVE_W, DRIVE_H),
		Brake = rect(w - 152, row1, DRIVE_W, DRIVE_H),
		Exit = rect(w - 152, row0, DRIVE_W, DRIVE_H),
		Camera = rect(w - 224, row0, DRIVE_W, DRIVE_H),
		Left = rect(MARGIN, row1, DRIVE_W, DRIVE_H),
		Right = rect(MARGIN + DRIVE_W + 8, row1, DRIVE_W, DRIVE_H),
	}

	local noticeH = 36
	local notice
	if narrow then
		-- Above the thumbstick area, clear of the stacked fire/reload buttons on the right.
		local right = if stacked and not driving then fire.X - 8 else w - MARGIN
		notice = rect(MARGIN, h - THUMB_ZONE_H - 8 - noticeH, right - MARGIN, noticeH)
	else
		local left = if driving then MARGIN + 2 * (DRIVE_W + 8) + 8 else THUMB_ZONE_W + 8
		local right = if driving then drive.Brake.X - 8 else reload.X - 8
		local noticeW = math.min(300, right - left)
		notice = rect(left + (right - left - noticeW) / 2, h - 12 - noticeH, noticeW, noticeH)
	end

	-- Visibility ---------------------------------------------------------------------------------
	local chatCoversRight = chatExpanded and secondRow
	local chatCoversLeft = chatExpanded and compact
	local visible = {
		Chat = chatExpanded,
		Map = not chatCoversLeft,
		Radio = not chatCoversLeft,
		Weapon = not driving and not chatCoversRight,
		Hotbar = not driving and not chatCoversRight,
		Vehicle = driving and not chatCoversRight,
		Fire = mode == "walking" and touch,
		Reload = mode == "walking" and touch,
		Drive = driving and touch,
	}

	local boxes: { Box } = {
		{ Name = "ChatButton", Rect = rect(MARGIN, TOP, BUTTON, BUTTON), Visible = true },
		{ Name = "MenuButton", Rect = rect(MARGIN + BUTTON + GAP, TOP, BUTTON, BUTTON), Visible = true },
		{ Name = "Compass", Rect = rect(compassX, compassY, compassW, TAPE_H), Visible = true },
		{
			Name = "Zone",
			Rect = rect(compassX + (compassW - zoneW) / 2, compassY + TAPE_H + 4, zoneW, ZONE_H),
			Visible = true,
		},
		{ Name = "Status", Rect = rect(rx, TOP, rw, statusH), Visible = true },
		{ Name = "Weapon", Rect = rect(rx, weaponY, rw, weaponH), Visible = visible.Weapon },
		{ Name = "Hotbar", Rect = rect(rx, hotbarY, rw, SLOT), Visible = visible.Hotbar },
		{ Name = "Vehicle", Rect = rect(rx, weaponY, rw, vehicleH), Visible = visible.Vehicle },
		{ Name = "Chat", Rect = rect(MARGIN, chatY, chatW, chatH), Visible = visible.Chat },
		{ Name = "Map", Rect = mapRect, Visible = visible.Map },
		{ Name = "Radio", Rect = radioRect, Visible = visible.Radio },
		{ Name = "Notice", Rect = notice, Visible = true },
		{ Name = "Fire", Rect = fire, Visible = visible.Fire },
		{ Name = "Reload", Rect = reload, Visible = visible.Reload },
	}
	for _, item in ipairs(menuItems) do
		table.insert(boxes, { Name = "Menu_" .. item.Id, Rect = item.Rect, Visible = true })
	end
	for _, item in ipairs(shortcuts) do
		table.insert(boxes, { Name = "Shortcut_" .. item.Id, Rect = item.Rect, Visible = true })
	end
	for index, slot in ipairs(slots) do
		-- Slots live inside the Hotbar box; they are listed for bounds/touch checks only.
		table.insert(boxes, { Name = "Slot_" .. (slotIds[index] :: string), Rect = slot, Visible = false })
	end
	for name, item in pairs(drive) do
		table.insert(boxes, { Name = "Drive_" .. name, Rect = item, Visible = visible.Drive })
	end

	return {
		Width = w,
		Height = h,
		Profile = profile,
		SecondRow = secondRow,
		ChatExpanded = chatExpanded,
		Visible = visible,
		ButtonSize = BUTTON,
		ChatButton = boxes[1].Rect,
		MenuButton = boxes[2].Rect,
		Compass = boxes[3].Rect,
		Zone = boxes[4].Rect,
		Status = boxes[5].Rect,
		Weapon = boxes[6].Rect,
		Hotbar = boxes[7].Rect,
		Vehicle = boxes[8].Rect,
		Chat = boxes[9].Rect,
		Map = mapRect,
		Radio = radioRect,
		Notice = notice,
		Fire = fire,
		Reload = reload,
		Drive = drive,
		Slots = slots,
		SlotIds = slotIds,
		MenuItems = menuItems,
		Shortcuts = shortcuts,
		Boxes = boxes,
		Reserved = {
			Jump = rect(w - JUMP_ZONE_W, h - JUMP_ZONE_H, JUMP_ZONE_W, JUMP_ZONE_H),
			Thumb = rect(0, h - THUMB_ZONE_H, THUMB_ZONE_W, THUMB_ZONE_H),
		},
	}
end

return table.freeze(HUDLayout)
