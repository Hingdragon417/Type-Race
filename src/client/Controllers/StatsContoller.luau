local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("ScreenGui")
local frames = screenGui:WaitForChild("Frames")
local statsFrame = frames:WaitForChild("Stats")
local container = statsFrame:WaitForChild("Container")
local statContainer = container:WaitForChild("StatContainer")

local StatsController = Knit.CreateController({
    Name = "StatsController",
})

local DataController

function StatsController:UpdateStats(data)
    if not data then
        return
    end
    
    local highestWinstreakLabel = statContainer:WaitForChild("HighestWinstreak")
    if highestWinstreakLabel and highestWinstreakLabel:IsA("TextLabel") then
        highestWinstreakLabel.Text = "Highest Winstreak: " .. tostring(data.HighestWinstreak or 0)
    end
    
    local winsLabel = statContainer:FindFirstChild("Wins")
    if winsLabel and winsLabel:IsA("TextLabel") then
        winsLabel.Text = "Wins: " .. tostring(data.Wins or 0)
    end
    
    local wpmLabel = statContainer:FindFirstChild("WPM")
    if wpmLabel and wpmLabel:IsA("TextLabel") then
        wpmLabel.Text = "WPM: " .. tostring(data.WPM or 0)
    end
    
    local winRateLabel = statContainer:FindFirstChild("WinRate")
    if winRateLabel and winRateLabel:IsA("TextLabel") then
        winRateLabel.Text = "Win Rate: " .. tostring(data.WinRate or 0) .. "%"
    end
end

function StatsController:KnitStart()
    local profileImage = container:FindFirstChildWhichIsA("ImageLabel")
    if profileImage then
        profileImage.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=420&h=420"
    end
    
    if DataController then
        local data = DataController.getData()
        while not data do
            task.wait(0.1)
            data = DataController.getData()
        end
        
        self:UpdateStats(data)
        
        DataController.onReplicated({"HighestWinstreak", "Wins", "WPM", "WinRate"}):Connect(function()
            local currentData = DataController.getData()
            if currentData then
                self:UpdateStats(currentData)
            end
        end)
    end
end

function StatsController:KnitInit()
    DataController = Knit.GetController("DataController")
end

return StatsController