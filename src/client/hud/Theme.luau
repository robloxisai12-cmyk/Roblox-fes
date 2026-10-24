--!strict
-- Visual language of the open-world HUD: carbon panels, intense green accent, white text.
-- Everything is built from native instances; no external assets.
local Theme = {}

Theme.Color = table.freeze({
	Panel = Color3.fromRGB(14, 17, 16),
	PanelRaised = Color3.fromRGB(28, 33, 31),
	Track = Color3.fromRGB(52, 58, 56),
	Border = Color3.fromRGB(255, 255, 255),
	Accent = Color3.fromRGB(46, 204, 98),
	AccentDeep = Color3.fromRGB(24, 120, 62),
	Text = Color3.fromRGB(245, 247, 246),
	Muted = Color3.fromRGB(162, 172, 168),
	Health = Color3.fromRGB(228, 62, 58),
	Warning = Color3.fromRGB(246, 160, 38),
	Info = Color3.fromRGB(64, 156, 255),
	Road = Color3.fromRGB(112, 124, 118),
})

Theme.Transparency = table.freeze({
	Panel = 0.22,
	Button = 0.18,
	Border = 0.86,
	Hidden = 1,
})

Theme.Radius = table.freeze({ Panel = 10, Button = 10, Pill = 12 })

function Theme.Corner(instance: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.Radius.Panel)
	corner.Parent = instance
	return corner
end

function Theme.Round(instance: Instance): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = instance
	return corner
end

function Theme.Stroke(instance: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color or Theme.Color.Border
	stroke.Thickness = thickness or 1
	stroke.Transparency = if transparency ~= nil then transparency else Theme.Transparency.Border
	stroke.Parent = instance
	return stroke
end

function Theme.Panel(parent: Instance, name: string, radius: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Theme.Color.Panel
	frame.BackgroundTransparency = Theme.Transparency.Panel
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Theme.Corner(frame, radius)
	Theme.Stroke(frame)
	return frame
end

function Theme.Box(parent: Instance, name: string, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color or Theme.Color.Panel
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

function Theme.Label(
	parent: Instance,
	name: string,
	text: string,
	size: number,
	color: Color3?,
	font: Enum.Font?,
	alignment: Enum.TextXAlignment?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamMedium
	label.Text = text
	label.TextSize = size
	label.TextColor3 = color or Theme.Color.Text
	label.TextXAlignment = alignment or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
end

-- A transparent text-less button: the icon, number and count are child instances.
function Theme.Button(parent: Instance, name: string, radius: number?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = true
	button.BackgroundColor3 = Theme.Color.Panel
	button.BackgroundTransparency = Theme.Transparency.Button
	button.BorderSizePixel = 0
	button.Parent = parent
	Theme.Corner(button, radius or Theme.Radius.Button)
	Theme.Stroke(button)
	return button
end

return table.freeze(Theme)
