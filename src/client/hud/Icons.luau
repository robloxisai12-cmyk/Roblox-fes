--!strict
-- Flat icons drawn with native Frames so the HUD needs no uploaded assets. Every shape is expressed in
-- a unit square (x, y, w, h = 0..1); `r` is the corner radius as a fraction of the shorter side, `rot`
-- the rotation in degrees and `cut = true` paints the shape with the background colour (a cut-out).
local Icons = {}

type Shape = { x: number, y: number, w: number, h: number, r: number?, rot: number?, cut: boolean? }

local function s(x: number, y: number, w: number, h: number, r: number?, rot: number?, cut: boolean?): Shape
	return { x = x, y = y, w = w, h = h, r = r, rot = rot, cut = cut }
end

local DEFINITIONS: { [string]: { Shape } } = {
	heart = {
		s(0.2, 0.52, 0.6, 0.6, 0.12, 45),
		s(0.1, 0.12, 0.42, 0.42, 0.5),
		s(0.48, 0.12, 0.42, 0.42, 0.5),
	},
	drop = {
		s(0.27, 0.42, 0.46, 0.46, 0.5),
		s(0.34, 0.1, 0.32, 0.32, 0.08, 45),
	},
	chat = {
		s(0.1, 0.16, 0.8, 0.54, 0.25),
		s(0.22, 0.6, 0.2, 0.2, 0.1, 45),
		s(0.26, 0.36, 0.48, 0.07, 0.5, nil, true),
		s(0.26, 0.5, 0.32, 0.07, 0.5, nil, true),
	},
	menu = {
		s(0.18, 0.24, 0.64, 0.1, 0.5),
		s(0.18, 0.45, 0.64, 0.1, 0.5),
		s(0.18, 0.66, 0.64, 0.1, 0.5),
	},
	close = {
		s(0.14, 0.45, 0.72, 0.1, 0.5, 45),
		s(0.14, 0.45, 0.72, 0.1, 0.5, -45),
	},
	squad = {
		s(0.36, 0.1, 0.28, 0.28, 0.5),
		s(0.26, 0.42, 0.48, 0.4, 0.45),
		s(0.06, 0.24, 0.2, 0.2, 0.5),
		s(0.0, 0.5, 0.3, 0.3, 0.45),
		s(0.74, 0.24, 0.2, 0.2, 0.5),
		s(0.7, 0.5, 0.3, 0.3, 0.45),
	},
	backpack = {
		s(0.38, 0.1, 0.24, 0.18, 0.5),
		s(0.22, 0.2, 0.56, 0.66, 0.3),
		s(0.32, 0.55, 0.36, 0.2, 0.25, nil, true),
		s(0.32, 0.36, 0.36, 0.06, 0.5, nil, true),
	},
	truck = {
		s(0.04, 0.44, 0.92, 0.26, 0.15),
		s(0.5, 0.26, 0.36, 0.26, 0.2),
		s(0.57, 0.31, 0.22, 0.12, 0.2, nil, true),
		s(0.16, 0.6, 0.24, 0.24, 0.5),
		s(0.6, 0.6, 0.24, 0.24, 0.5),
		s(0.24, 0.68, 0.08, 0.08, 0.5, nil, true),
		s(0.68, 0.68, 0.08, 0.08, 0.5, nil, true),
	},
	clipboard = {
		s(0.2, 0.16, 0.6, 0.72, 0.12),
		s(0.36, 0.08, 0.28, 0.16, 0.3),
		s(0.32, 0.38, 0.36, 0.06, 0.5, nil, true),
		s(0.32, 0.52, 0.36, 0.06, 0.5, nil, true),
		s(0.32, 0.66, 0.24, 0.06, 0.5, nil, true),
	},
	radio = {
		s(0.14, 0.36, 0.72, 0.46, 0.14),
		s(0.62, 0.08, 0.06, 0.34, 0.5, 14),
		s(0.24, 0.46, 0.26, 0.26, 0.5, nil, true),
		s(0.58, 0.46, 0.2, 0.06, 0.5, nil, true),
		s(0.58, 0.58, 0.2, 0.06, 0.5, nil, true),
	},
	cross = {
		s(0.38, 0.16, 0.24, 0.68, 0.15),
		s(0.16, 0.38, 0.68, 0.24, 0.15),
	},
	bandage = {
		s(0.08, 0.36, 0.84, 0.28, 0.4, -35),
		s(0.4, 0.4, 0.2, 0.2, 0.2, -35, true),
	},
	medkit = {
		s(0.38, 0.12, 0.24, 0.16, 0.4),
		s(0.1, 0.24, 0.8, 0.6, 0.18),
		s(0.45, 0.36, 0.1, 0.36, 0.2, nil, true),
		s(0.32, 0.49, 0.36, 0.1, 0.2, nil, true),
	},
	rifle = {
		s(0.04, 0.4, 0.22, 0.2, 0.3),
		s(0.22, 0.42, 0.46, 0.14, 0.2),
		s(0.66, 0.44, 0.3, 0.07, 0.3),
		s(0.42, 0.52, 0.09, 0.26, 0.2, 12),
		s(0.28, 0.54, 0.08, 0.2, 0.2, -14),
		s(0.5, 0.34, 0.2, 0.08, 0.3),
	},
	pistol = {
		s(0.12, 0.3, 0.7, 0.2, 0.2),
		s(0.78, 0.34, 0.12, 0.12, 0.2),
		s(0.22, 0.44, 0.2, 0.38, 0.2, -10),
		s(0.46, 0.5, 0.16, 0.1, 0.4),
	},
	magazine = {
		s(0.34, 0.1, 0.32, 0.72, 0.1, 10),
		s(0.41, 0.2, 0.18, 0.06, 0.5, 10, true),
		s(0.41, 0.34, 0.18, 0.06, 0.5, 10, true),
		s(0.41, 0.48, 0.18, 0.06, 0.5, 10, true),
	},
	bullet = {
		s(0.38, 0.1, 0.24, 0.52, 0.5, 38),
		s(0.46, 0.5, 0.28, 0.14, 0.2, 38),
	},
	pin = {
		s(0.3, 0.1, 0.4, 0.4, 0.5),
		s(0.36, 0.38, 0.28, 0.28, 0.1, 45),
		s(0.42, 0.22, 0.16, 0.16, 0.5, nil, true),
	},
	fuel = {
		s(0.16, 0.14, 0.44, 0.72, 0.14),
		s(0.24, 0.24, 0.28, 0.2, 0.2, nil, true),
		s(0.6, 0.3, 0.24, 0.07, 0.5),
		s(0.78, 0.3, 0.07, 0.34, 0.5),
		s(0.1, 0.82, 0.56, 0.08, 0.3),
	},
	chevronLeft = {
		s(0.3, 0.3, 0.4, 0.1, 0.5, -45),
		s(0.3, 0.6, 0.4, 0.1, 0.5, 45),
	},
	chevronRight = {
		s(0.3, 0.3, 0.4, 0.1, 0.5, 45),
		s(0.3, 0.6, 0.4, 0.1, 0.5, -45),
	},
	chevronUp = {
		s(0.16, 0.45, 0.4, 0.1, 0.5, -45),
		s(0.44, 0.45, 0.4, 0.1, 0.5, 45),
	},
	chevronDown = {
		s(0.16, 0.45, 0.4, 0.1, 0.5, 45),
		s(0.44, 0.45, 0.4, 0.1, 0.5, -45),
	},
	stop = {
		s(0.24, 0.24, 0.52, 0.52, 0.18),
	},
	camera = {
		s(0.1, 0.3, 0.8, 0.52, 0.18),
		s(0.32, 0.2, 0.3, 0.14, 0.4),
		s(0.34, 0.36, 0.32, 0.32, 0.5, nil, true),
		s(0.42, 0.44, 0.16, 0.16, 0.5),
	},
	exit = {
		s(0.18, 0.14, 0.34, 0.72, 0.1),
		s(0.22, 0.2, 0.26, 0.6, 0.1, nil, true),
		s(0.42, 0.46, 0.4, 0.08, 0.5),
		s(0.66, 0.34, 0.08, 0.3, 0.5, 45),
	},
}

-- Draws `kind` into a square, transparent container that fills `parent`. `cutColor` is the colour of
-- whatever sits behind the icon so cut-out details read as holes.
function Icons.Draw(parent: Instance, kind: string, color: Color3, cutColor: Color3): Frame
	local container = Instance.new("Frame")
	container.Name = "Icon_" .. kind
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = UDim2.fromScale(1, 1)
	container.Parent = parent
	for index, shape in ipairs(DEFINITIONS[kind] or {}) do
		local frame = Instance.new("Frame")
		frame.Name = "Part" .. index
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = if shape.cut then cutColor else color
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(shape.x + shape.w / 2, shape.y + shape.h / 2)
		frame.Size = UDim2.fromScale(shape.w, shape.h)
		frame.Rotation = shape.rot or 0
		if shape.r ~= nil then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(shape.r, 0)
			corner.Parent = frame
		end
		frame.Parent = container
	end
	return container
end

-- Recolours every painted part (used for selected / disabled states).
function Icons.Tint(container: Instance, color: Color3, cutColor: Color3, kind: string)
	local definition = DEFINITIONS[kind]
	if definition == nil then
		return
	end
	for index, shape in ipairs(definition) do
		local part = container:FindFirstChild("Part" .. index)
		if part ~= nil and part:IsA("Frame") then
			part.BackgroundColor3 = if shape.cut then cutColor else color
		end
	end
end

function Icons.Has(kind: string): boolean
	return DEFINITIONS[kind] ~= nil
end

return table.freeze(Icons)
