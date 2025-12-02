local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer

-- Cached references (will be populated by polling system)
local playerGui = nil
local screenGui = nil
local frames = nil
local keyboardsFrame = nil
local container = nil
local scrollingFrame = nil
local assets = nil
local uiAssets = nil
local keyboardTemplate = nil
local keyboardsFolder = nil

-- Polling system to find elements without yielding
local elementsReady = false
local function pollForElements()
	if elementsReady then return true end
	
	-- Try to find PlayerGui
	if not playerGui then
		playerGui = player:FindFirstChild("PlayerGui")
		if not playerGui then return false end
	end
	
	-- Try to find ScreenGui
	if not screenGui then
		screenGui = playerGui:FindFirstChild("ScreenGui")
		if not screenGui then return false end
	end
	
	-- Try to find Frames
	if not frames then
		frames = screenGui:FindFirstChild("Frames")
		if not frames then return false end
	end
	
	-- Try to find Keyboards frame
	if not keyboardsFrame then
		keyboardsFrame = frames:FindFirstChild("Keyboards")
		if not keyboardsFrame then return false end
	end
	
	-- Try to find Container
	if not container then
		container = keyboardsFrame:FindFirstChild("Container")
		if not container then return false end
	end
	
	-- Try to find ScrollingFrame
	if not scrollingFrame then
		scrollingFrame = container:FindFirstChild("ScrollingFrame")
		if not scrollingFrame then return false end
	end
	
	-- Try to find Assets
	if not assets then
		assets = ReplicatedStorage:FindFirstChild("Assets")
		if not assets then return false end
	end
	
	-- Try to find UIAssets
	if not uiAssets then
		uiAssets = assets:FindFirstChild("UIAssets")
		if not uiAssets then return false end
	end
	
	-- Try to find KeyboardTemplate
	if not keyboardTemplate then
		keyboardTemplate = uiAssets:FindFirstChild("KeyboardTemplate")
		if not keyboardTemplate then return false end
	end
	
	-- Try to find Keyboards folder
	if not keyboardsFolder then
		keyboardsFolder = assets:FindFirstChild("Keyboards")
		if not keyboardsFolder then return false end
	end
	
	-- All elements found!
	elementsReady = true
	return true
end

local KeyboardInventoryController = Knit.CreateController({
	Name = "KeyboardInventoryController",
	spinningConnections = {},
})

function KeyboardInventoryController:SpinKeyboard(viewportFrame)
	local camera = Instance.new("Camera")
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera
	
	local keyboard = viewportFrame:FindFirstChildWhichIsA("Model")
	if not keyboard then return end
	
	local cf, size = keyboard:GetBoundingBox()
	camera.CFrame = cf * CFrame.new(0, 1.3, 2) * CFrame.Angles(math.rad(-30), 0, 0)
	
	if self.spinningConnections[viewportFrame] then
		self.spinningConnections[viewportFrame]:Disconnect()
	end
	
	self.spinningConnections[viewportFrame] = RunService.RenderStepped:Connect(function(dt)
		keyboard:PivotTo(keyboard:GetPivot() * CFrame.Angles(0, math.rad(30) * dt, 0))
	end)
end

function KeyboardInventoryController:CreateKeyboardButton(keyboardName, equippedKeyboard)
	if not pollForElements() then
		warn("[KeyboardInventoryController] Elements not ready yet")
		return nil
	end
	
	local button = keyboardTemplate:Clone()
	button.Name = keyboardName
	
	local nameLabel = button:FindFirstChild("Name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = keyboardName
	end
	
	local viewportFrame = button:FindFirstChild("ViewportFrame")
	if viewportFrame then
		local keyboardModel = keyboardsFolder:FindFirstChild(keyboardName)
		if keyboardModel then
			local clonedKeyboard = keyboardModel:Clone()
			clonedKeyboard.Parent = viewportFrame
			self:SpinKeyboard(viewportFrame)
		end
	end
	
	local function updateEquipStatus(isEquipped)
		local uiStroke = button:FindFirstChildWhichIsA("UIStroke", true)
		if isEquipped then
			if uiStroke then
				uiStroke.Color = Color3.fromRGB(0, 255, 0)
			else
				local newStroke = Instance.new("UIStroke")
				newStroke.Color = Color3.fromRGB(0, 255, 0)
				newStroke.Thickness = 3
				newStroke.Parent = button
			end
		else
			if uiStroke then
				uiStroke.Color = Color3.fromRGB(255, 255, 255)
			end
		end
	end
	
	updateEquipStatus(keyboardName == equippedKeyboard)
	
	button.MouseButton1Click:Connect(function()
		self:EquipKeyboard(keyboardName)
	end)
	
	button.Parent = scrollingFrame
	return button
end

function KeyboardInventoryController:LoadKeyboards(keyboardInventory, equippedKeyboard)
	if not pollForElements() then
		warn("[KeyboardInventoryController] Elements not ready, cannot load keyboards")
		return
	end
	
	if not keyboardInventory then
		local DataController = Knit.GetController("DataController")
		local data = DataController and DataController.getData()
		if data then
			keyboardInventory = data.KeyboardInventory
			equippedKeyboard = equippedKeyboard or data.EquippedKeyboard
		end
	end
	
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiButton") or child:IsA("ImageButton") then
			local uiStroke = child:FindFirstChildWhichIsA("UIStroke", true)
			local isEquipped = child.Name == equippedKeyboard
			
			if uiStroke then
				if isEquipped then
					uiStroke.Color = Color3.fromRGB(0, 255, 0)
				else
					uiStroke.Color = Color3.fromRGB(255, 255, 255)
				end
			elseif isEquipped then
				local newStroke = Instance.new("UIStroke")
				newStroke.Color = Color3.fromRGB(0, 255, 0)
				newStroke.Thickness = 3
				newStroke.Parent = child
			end
		end
	end
	
	if #scrollingFrame:GetChildren() > 0 then
		local hasAllKeyboards = true
		if keyboardInventory then
			for _, keyboardName in ipairs(keyboardInventory) do
				if not scrollingFrame:FindFirstChild(keyboardName) then
					hasAllKeyboards = false
					break
				end
			end
		end
		
		if hasAllKeyboards then
			return
		end
	end
	
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiButton") or child:IsA("ImageButton") then
			child:Destroy()
		end
	end
	
	for _, connection in pairs(self.spinningConnections) do
		connection:Disconnect()
	end
	self.spinningConnections = {}

	if not keyboardInventory or type(keyboardInventory) ~= "table" then
		return
	end

	for _, keyboardName in ipairs(keyboardInventory) do
		self:CreateKeyboardButton(keyboardName, equippedKeyboard)
	end
end

function KeyboardInventoryController:EquipKeyboard(keyboardName)
	local KeyboardInventoryService = Knit.GetService("KeyboardInventoryService")
	if KeyboardInventoryService then
		KeyboardInventoryService:EquipKeyboard(keyboardName):andThen(function(success)
			if success then
				self:LoadKeyboards(nil, keyboardName)
			end
		end)
	end
end

function KeyboardInventoryController:KnitStart()
	-- Start polling for elements on RenderStepped (non-yielding)
	local pollConnection
	pollConnection = RunService.RenderStepped:Connect(function()
		if pollForElements() then
			pollConnection:Disconnect()
			
			-- Now that elements are ready, load keyboards
			local DataController = Knit.GetController("DataController")
			
			if DataController then
				local data = DataController.getData()
				
				-- Non-yielding poll for data
				if not data then
					local dataConnection
					dataConnection = RunService.Heartbeat:Connect(function()
						data = DataController.getData()
						if data then
							dataConnection:Disconnect()
							self:LoadKeyboards(data.KeyboardInventory, data.EquippedKeyboard)
						end
					end)
				else
					self:LoadKeyboards(data.KeyboardInventory, data.EquippedKeyboard)
				end
				
				DataController.onReplicated({"KeyboardInventory", "EquippedKeyboard"}):Connect(function()
					local currentData = DataController.getData()
					if currentData then
						self:LoadKeyboards(currentData.KeyboardInventory, currentData.EquippedKeyboard)
					end
				end)
			end
		end
	end)
end

function KeyboardInventoryController:KnitInit()
end

return KeyboardInventoryController