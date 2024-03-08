-- Just generic utility functions which I use and repeat across all my projects

-- LOCAL
local Utility = {}
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

-- FUNCTIONS
function Utility.copyTable(t)
	-- Credit to Stephen Leitnick (September 13, 2017) for this function from TableUtil
	assert(type(t) == "table", "First argument must be a table")
	local tCopy = table.create(#t)
	for k, v in pairs(t) do
		if type(v) == "table" then
			tCopy[k] = Utility.copyTable(v)
		else
			tCopy[k] = v
		end
	end
	return tCopy
end

local validCharacters = {
	"a",
	"b",
	"c",
	"d",
	"e",
	"f",
	"g",
	"h",
	"i",
	"j",
	"k",
	"l",
	"m",
	"n",
	"o",
	"p",
	"q",
	"r",
	"s",
	"t",
	"u",
	"v",
	"w",
	"x",
	"y",
	"z",
	"A",
	"B",
	"C",
	"D",
	"E",
	"F",
	"G",
	"H",
	"I",
	"J",
	"K",
	"L",
	"M",
	"N",
	"O",
	"P",
	"Q",
	"R",
	"S",
	"T",
	"U",
	"V",
	"W",
	"X",
	"Y",
	"Z",
	"1",
	"2",
	"3",
	"4",
	"5",
	"6",
	"7",
	"8",
	"9",
	"0",
	"<",
	">",
	"?",
	"@",
	"{",
	"}",
	"[",
	"]",
	"!",
	"(",
	")",
	"=",
	"+",
	"~",
	"#",
}
function Utility.generateUID(length)
	length = length or 8
	local UID = ""
	local list = validCharacters
	local total = #list
	for i = 1, length do
		local randomCharacter = list[math.random(1, total)]
		UID = UID .. randomCharacter
	end
	return UID
end

local instanceTrackers = {}
function Utility.setVisible(instance, bool, sourceUID)
	-- This effectively works like a buff object but
	-- incredibly simplified. It stacks false values
	-- so that if there is more than more than, the
	-- instance remains hidden even if set visible true
	local tracker = instanceTrackers[instance]
	if not tracker then
		tracker = {}
		instanceTrackers[instance] = tracker
		instance.Destroying:Once(function()
			instanceTrackers[instance] = nil
		end)
	end
	if not bool then
		tracker[sourceUID] = true
	else
		tracker[sourceUID] = nil
	end
	local isVisible = bool
	if bool then
		for sourceUID, _ in pairs(tracker) do
			isVisible = false
			break
		end
	end
	instance.Visible = isVisible
end

function Utility.formatStateName(incomingStateName)
	return string.upper(string.sub(incomingStateName, 1, 1)) .. string.lower(string.sub(incomingStateName, 2))
end

function Utility.localPlayerRespawned(callback)
	-- The client localscript may be located under a ScreenGui with ResetOnSpawn set to true
	-- In these scenarios, traditional methods like CharacterAdded won't be called by the
	-- time the localscript has been destroyed, therefore we listen for died instead
	task.spawn(function()
		local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
		local humanoid
		for i = 1, 5 do
			humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				break
			end
			task.wait(1)
		end
		if humanoid then
			humanoid.Died:Once(function()
				task.delay(Players.RespawnTime - 0.1, function()
					callback()
				end)
			end)
		end
	end)
end

function Utility.getClippedContainer(screenGui)
	-- We always want clipped items to display in front hence
	-- why we have this
	local clippedContainer = screenGui:FindFirstChild("ClippedContainer")
	if not clippedContainer then
		clippedContainer = Instance.new("Folder")
		clippedContainer.Name = "ClippedContainer"
		clippedContainer.Parent = screenGui
	end
	return clippedContainer
end

local Janitor = require(script.Parent.Packages.Janitor)
local GuiService = game:GetService("GuiService")
function Utility.clipOutside(icon, instance)
	local cloneJanitor = icon.janitor:add(Janitor.new())
	instance.Destroying:Once(function()
		cloneJanitor:Destroy()
	end)
	icon.janitor:add(instance)

	local originalParent = instance.Parent
	local clone = cloneJanitor:add(Instance.new("Frame"))
	clone:SetAttribute("IsAClippedClone", true)
	clone.Name = instance.Name
	clone.AnchorPoint = instance.AnchorPoint
	clone.Size = instance.Size
	clone.Position = instance.Position
	clone.BackgroundTransparency = 1
	clone.LayoutOrder = instance.LayoutOrder
	clone.Parent = originalParent

	local valueInstance = Instance.new("ObjectValue")
	valueInstance.Name = "OriginalInstance"
	valueInstance.Value = instance
	valueInstance.Parent = clone

	local valueInstanceCopy = valueInstance:Clone()
	instance:SetAttribute("HasAClippedClone", true)
	valueInstanceCopy.Name = "ClippedClone"
	valueInstanceCopy.Value = clone
	valueInstanceCopy.Parent = instance

	local screenGui
	local function updateScreenGui()
		local originalScreenGui = originalParent:FindFirstAncestorWhichIsA("ScreenGui")
		screenGui = if string.match(originalScreenGui.Name, "Clipped")
			then originalScreenGui
			else originalScreenGui.Parent[originalScreenGui.Name .. "Clipped"]
		instance.AnchorPoint = Vector2.new(0, 0)
		instance.Parent = Utility.getClippedContainer(screenGui)
	end
	cloneJanitor:add(icon.alignmentChanged:Connect(updateScreenGui))
	updateScreenGui()

	-- Lets copy over children that modify size
	for _, child in pairs(instance:GetChildren()) do
		if child:IsA("UIAspectRatioConstraint") then
			child:Clone().Parent = clone
		end
	end

	-- If the icon is hidden, its important we are too (as
	-- setting a parent to visible = false no longer makes
	-- this hidden)
	local widget = icon.widget
	local isOutsideParent = false
	local ignoreVisibilityUpdater = instance:GetAttribute("IgnoreVisibilityUpdater")
	local function updateVisibility()
		if ignoreVisibilityUpdater then
			return
		end
		local isVisible = widget.Visible
		if isOutsideParent then
			isVisible = false
		end
		Utility.setVisible(instance, isVisible, "ClipHandler")
	end
	cloneJanitor:add(widget:GetPropertyChangedSignal("Visible"):Connect(updateVisibility))

	local function checkIfOutsideParentXBounds()
		-- Defer so that roblox's properties reflect their true values
		task.defer(function()
			-- If the instance is within a parent item (such as a dropdown or menu)
			-- then we hide it if it exceeds the bounds of that parent
			local shouldClipToParent = instance:GetAttribute("ClipToJoinedParent")
			local parentInstance = shouldClipToParent and icon.joinedFrame
			if not parentInstance then
				return
			end
			local pos = instance.AbsolutePosition
			local halfSize = instance.AbsoluteSize / 2
			local parentPos = parentInstance.AbsolutePosition
			local parentSize = parentInstance.AbsoluteSize
			local posHalf = (pos + halfSize)
			local exceededLeft = posHalf.X < parentPos.X
			local exceededRight = posHalf.X > (parentPos.X + parentSize.X)
			local exceededTop = posHalf.Y < parentPos.Y
			local exceededBottom = posHalf.Y > (parentPos.Y + parentSize.Y)
			local hasExceeded = exceededLeft or exceededRight or exceededTop or exceededBottom
			if hasExceeded ~= isOutsideParent then
				isOutsideParent = hasExceeded
				updateVisibility()
			end
		end)
	end

	local camera = workspace.CurrentCamera
	local additionalOffsetX = instance:GetAttribute("AdditionalOffsetX") or 0
	local function trackProperty(property)
		local absoluteProperty = "Absolute" .. property
		cloneJanitor:add(clone:GetPropertyChangedSignal(absoluteProperty):Connect(function()
			task.defer(
				function() -- This defer is essential as the listener may be in a different screenGui to the actor
					local cloneValue = clone[absoluteProperty]
					local absoluteValue = UDim2.fromOffset(cloneValue.X, cloneValue.Y)
					if property == "Position" then
						-- This binds the instances within the bounds of the screen
						local SIDE_PADDING = 4
						local limitX = camera.ViewportSize.X - instance.AbsoluteSize.X - SIDE_PADDING
						local inputX = absoluteValue.X.Offset
						if inputX < SIDE_PADDING then
							inputX = SIDE_PADDING
						elseif inputX > limitX then
							inputX = limitX
						end
						absoluteValue = UDim2.fromOffset(inputX, absoluteValue.Y.Offset)

						-- AbsolutePosition does not perfectly match with TopbarInsets enabled
						-- This corrects this
						local topbarInset = GuiService.TopbarInset
						local viewportWidth = workspace.CurrentCamera.ViewportSize.X
						local guiWidth = screenGui.AbsoluteSize.X
						local guiOffset = screenGui.AbsolutePosition.X
						local widthDifference = guiOffset - topbarInset.Min.X
						local oldTopbarCenterOffset = 0 --widthDifference/30 -- I have no idea why this works, it just does
						local offsetX = if icon.isOldTopbar
							then guiOffset
							else viewportWidth - guiWidth - oldTopbarCenterOffset

						-- Also add additionalOffset
						offsetX -= additionalOffsetX
						absoluteValue += UDim2.fromOffset(-offsetX, topbarInset.Height)

						-- Finally check if within its direct parents bounds
						checkIfOutsideParentXBounds()
					end
					instance[property] = absoluteValue
				end
			)
		end))
	end
	checkIfOutsideParentXBounds()
	updateVisibility()
	trackProperty("Position")

	-- To ensure accurate positioning, it's important the clone also remains the same size as the instance
	local shouldTrackCloneSize = instance:GetAttribute("TrackCloneSize")
	if shouldTrackCloneSize then
		trackProperty("Size")
	else
		cloneJanitor:add(instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local absolute = instance.AbsoluteSize
			clone.Size = UDim2.fromOffset(absolute.X, absolute.Y)
		end))
	end

	return clone
end

function Utility.joinFeature(originalIcon, parentIcon, iconsArray, scrollingFrameOrFrame)
	-- This is resonsible for moving the icon under a feature like a dropdown
	local joinJanitor = originalIcon.joinJanitor
	joinJanitor:clean()
	if not scrollingFrameOrFrame then
		originalIcon:leave()
		return
	end
	originalIcon.parentIconUID = parentIcon.UID
	originalIcon.joinedFrame = scrollingFrameOrFrame
	local function updateAlignent()
		local parentAlignment = parentIcon.alignment
		if parentAlignment == "Center" then
			parentAlignment = "Left"
		end
		originalIcon:setAlignment(parentAlignment, true)
	end
	joinJanitor:add(parentIcon.alignmentChanged:Connect(updateAlignent))
	updateAlignent()
	originalIcon:modifyTheme({ "IconButton", "BackgroundTransparency", 1 }, "JoinModification")
	originalIcon:modifyTheme({ "ClickRegion", "Active", false }, "JoinModification")
	if parentIcon.childModifications then
		originalIcon:modifyTheme(parentIcon.childModifications, parentIcon.childModificationsUID)
	end
	--
	local clickRegion = originalIcon:getInstance("ClickRegion")
	local function makeSelectable()
		clickRegion.Selectable = parentIcon.isSelected
	end
	joinJanitor:add(parentIcon.toggled:Connect(makeSelectable))
	task.defer(makeSelectable)
	joinJanitor:add(function()
		clickRegion.Selectable = true
	end)
	--

	-- We track icons in arrays and dictionaries using their UID instead of the icon
	-- itself to prevent heavy cyclical tables when printing the icons
	local originalIconUID = originalIcon.UID
	table.insert(iconsArray, originalIconUID)
	parentIcon:autoDeselect(false)
	parentIcon.childIconsDict[originalIconUID] = true
	if not parentIcon.isEnabled then
		parentIcon:setEnabled(true)
	end
	originalIcon.joinedParent:Fire(parentIcon)

	-- This is responsible for removing it from that feature and updating
	-- their parent icon so its informed of the icon leaving it
	joinJanitor:add(function()
		local joinedFrame = originalIcon.joinedFrame
		if not joinedFrame then
			return
		end
		for i, iconUID in pairs(iconsArray) do
			if iconUID == originalIconUID then
				table.remove(iconsArray, i)
				break
			end
		end
		local Icon = require(originalIcon.iconModule)
		local parentIcon = Icon.getIconByUID(originalIcon.parentIconUID)
		originalIcon:setAlignment(originalIcon.originalAlignment)
		originalIcon.parentIconUID = false
		originalIcon.joinedFrame = false
		originalIcon:setBehaviour("IconButton", "BackgroundTransparency", nil, true)
		originalIcon:removeModification("JoinModification")
		local parentHasNoChildren = true
		local parentChildIcons = parentIcon.childIconsDict
		parentChildIcons[originalIconUID] = nil
		for childIconUID, _ in pairs(parentChildIcons) do
			parentHasNoChildren = false
			break
		end
		if parentHasNoChildren and not parentIcon.isAnOverflow then
			parentIcon:setEnabled(false)
		end
		updateAlignent()
	end)
end

return Utility
