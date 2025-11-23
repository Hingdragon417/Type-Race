local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local QuestEnums = require(Shared.Data.QuestEnums)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("ScreenGui")
local rightContainer = mainGui:WaitForChild("RightContainer")
local questsFrame = rightContainer:WaitForChild("Quests")
local holder = questsFrame:WaitForChild("Holder")

local QuestController = Knit.CreateController({
    Name = "QuestController",
})

local QuestService
local activeQuests = {}
local resetTime = 0

local function formatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    
    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

local function updateQuestDisplay()
    QuestService:GetPlayerProgress():andThen(function(progress)
        for i = 1, 3 do
            local questFrame = holder:FindFirstChild("Quest" .. i)
            if questFrame then
                local quest = activeQuests[i]
                
                if quest then
                    questFrame.Visible = true
                    
                    -- Update quest name in "Text" TextLabel
                    local nameLabel = questFrame:FindFirstChild("Text")
                    if nameLabel and nameLabel:IsA("TextLabel") then
                        nameLabel.Text = quest.Name
                    end
                    
                    -- Get progress data
                    local current = progress[quest.Name] or 0
                    local goal = quest.Data.Goal
                    local progressPercent = math.clamp(current / goal, 0, 1)
                    
                    -- Update "Text2" with progress
                    local progressLabel = questFrame:FindFirstChild("Text2")
                    if progressLabel and progressLabel:IsA("TextLabel") then
                        progressLabel.Text = string.format("%d/%d", current, goal)
                    end
                    
                    -- Update "Reward" with coin amount
                    local rewardLabel = questFrame:FindFirstChild("Reward")
                    if rewardLabel and rewardLabel:IsA("TextLabel") then
                        rewardLabel.Text = string.format("+%d Coins", quest.Data.Reward)
                    end
                    
                    -- Update Bar -> Filler
                    local bar = questFrame:FindFirstChild("Bar")
                    if bar then
                        local filler = bar:FindFirstChild("Filler")
                        if filler then
                            -- Tween the filler to the left based on progress
                            local tweenInfo = TweenInfo.new(
                                0.5, -- Duration
                                Enum.EasingStyle.Quad,
                                Enum.EasingDirection.Out
                            )
                            
                            local tweenGoal = {
                                Size = UDim2.new(progressPercent, 0, 1, 0)
                            }
                            
                            local tween = TweenService:Create(filler, tweenInfo, tweenGoal)
                            tween:Play()
                        end
                    end
                else
                    questFrame.Visible = false
                end
            end
        end
    end):catch(function(err)
        warn("[QuestController] Failed to get player progress:", err)
    end)
end

local function updateTimer()
    local timeLabel = questsFrame:FindFirstChild("Text")
    if timeLabel and timeLabel:IsA("TextLabel") then
        if resetTime == 0 then
            timeLabel.Text = "Loading..."
            return
        end
        
        local currentTime = os.time()
        local timeSinceReset = currentTime - resetTime
        local timeUntilReset = math.max(0, 1800 - timeSinceReset)
        
        if timeUntilReset == 0 then
            timeLabel.Text = "Resetting..."
        else
            timeLabel.Text = "Resets In: " .. formatTime(timeUntilReset)
        end
    end
end

function QuestController:KnitStart()
    local function loadQuests()
        QuestService:GetActiveQuests():andThen(function(quests, lastReset)
            activeQuests = quests
            resetTime = lastReset
            
            -- Retry if we got empty quests (data might not be ready yet)
            if #quests == 0 and resetTime == 0 then
                task.wait(2)
                loadQuests()
                return
            end
            
            updateQuestDisplay()
            updateTimer()
        end):catch(function(err)
            warn("[QuestController] Failed to get active quests:", err)
            -- Retry on error
            task.wait(2)
            loadQuests()
        end)
    end
    
    loadQuests()
    
    QuestService.QuestsUpdated:Connect(function(quests, lastReset)
        activeQuests = quests
        resetTime = lastReset
        updateQuestDisplay()
        updateTimer()
    end)
    
    QuestService.ProgressUpdated:Connect(function(questName, progress)
        updateQuestDisplay()
    end)
    
    RunService.Heartbeat:Connect(function()
        updateTimer()
    end)
end

function QuestController:KnitInit()
    QuestService = Knit.GetService("QuestService")
end

return QuestController