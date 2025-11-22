local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local BASE_SIZE = 1920

local cameraConnection

local function formatCoins(amount: number): string
	if not amount or type(amount) ~= "number" then
		return "0"
	end
	
	if amount >= 1000000000 then
		return string.format("%.1fB", math.floor(amount / 100000000) / 10)
	elseif amount >= 1000000 then
		return string.format("%.1fM", math.floor(amount / 100000) / 10)
	elseif amount >= 1000 then
		return string.format("%.1fK", math.floor(amount / 100) / 10)
	else
		return tostring(math.floor(amount))
	end
end

local function updateCoinsDisplay(coins: number)
	if not coins or type(coins) ~= "number" then
		return
	end
	
	local mainGui = playerGui:FindFirstChild("ScreenGui")
	if not mainGui then return end
	
	local leftContainer = mainGui:FindFirstChild("LeftContainer")
	if not leftContainer then return end
	
	local coinsFrame = leftContainer:FindFirstChild("Coins")
	if not coinsFrame then return end
	
	local amount = coinsFrame:FindFirstChild("Amount")
	if not amount then return end
	
	local textLabel = amount:FindFirstChild("Text")
	if not textLabel or not textLabel:IsA("TextLabel") then return end
	
	textLabel.Text = formatCoins(coins)
end

local function updateAllUIStrokeThickness()
	local scale = camera.ViewportSize.X / BASE_SIZE
	
	for _, instance in ipairs(localPlayer.PlayerGui:GetDescendants()) do
		if instance:IsA("UIStroke") then
			local initial = instance:GetAttribute("InitialThickness")
			if not initial then
				initial = instance.Thickness
				instance:SetAttribute("InitialThickness", initial)
			end
			instance.Thickness = initial * scale
		end
	end
end

do
    Knit.AddControllersDeep(script.Parent.Controllers)

    Knit.Start()
        :andThen(function()
            updateAllUIStrokeThickness()
            
            local DataController = Knit.GetController("DataController")
            
            cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateAllUIStrokeThickness)
            
            localPlayer.PlayerGui.DescendantAdded:Connect(function(instance)
                if instance:IsA("UIStroke") then
                    local scale = camera.ViewportSize.X / BASE_SIZE
                    local initial = instance.Thickness
                    instance:SetAttribute("InitialThickness", initial)
                    instance.Thickness = initial * scale
                end
            end)
            
            task.spawn(function()
                local playerData = DataController.waitForData()
                
                while not playerData.Coins do
                    task.wait(0.1)
                    playerData = DataController.getData()
                end
                
                DataController.onReplicated():Connect(function()
                    local data = DataController.getData()
                    if data and data.Coins then
                        updateCoinsDisplay(data.Coins)
                    end
                end)
                
                updateCoinsDisplay(playerData.Coins)
            end)
        end)
        :catch(warn)
end