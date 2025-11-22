local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("ScreenGui")
local frames = screenGui:WaitForChild("Frames")
local keyboardsFrame = frames:WaitForChild("Keyboards")
local container = keyboardsFrame:WaitForChild("Container")
local scrollingFrame = container:WaitForChild("ScrollingFrame")

local assets = ReplicatedStorage:WaitForChild("Assets")
local uiAssets = assets:WaitForChild("UIAssets")
local keyboardTemplate = uiAssets:WaitForChild("KeyboardTemplate")
local keyboardsFolder = assets:WaitForChild("Keyboards")

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
    
    self.spinningConnections[viewportFrame] = game:GetService("RunService").RenderStepped:Connect(function(dt)
        keyboard:PivotTo(keyboard:GetPivot() * CFrame.Angles(0, math.rad(30) * dt, 0))
    end)
end

function KeyboardInventoryController:CreateKeyboardButton(keyboardName, equippedKeyboard)
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
    
    if keyboardName == equippedKeyboard then
        local uiStroke = button:FindFirstChildWhichIsA("UIStroke", true)
        if uiStroke then
            uiStroke.Color = Color3.fromRGB(0, 255, 0)
        else
            local newStroke = Instance.new("UIStroke")
            newStroke.Color = Color3.fromRGB(0, 255, 0)
            newStroke.Thickness = 3
            newStroke.Parent = button
        end
    end
    
    button.Parent = scrollingFrame
    return button
end

function KeyboardInventoryController:LoadKeyboards(keyboardInventory, equippedKeyboard)
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

function KeyboardInventoryController:KnitStart()
    local DataController = Knit.GetController("DataController")
    
    if DataController then
        local data = DataController.getData()
        while not data do
            task.wait(0.1)
            data = DataController.getData()
        end
        self:LoadKeyboards(data.KeyboardInventory, data.EquippedKeyboard)
        DataController.onReplicated({"KeyboardInventory", "EquippedKeyboard"}):Connect(function()
            local currentData = DataController.getData()
            if currentData then
                self:LoadKeyboards(currentData.KeyboardInventory, currentData.EquippedKeyboard)
            end
        end)
    else
    end
end

function KeyboardInventoryController:KnitInit()
end

return KeyboardInventoryController