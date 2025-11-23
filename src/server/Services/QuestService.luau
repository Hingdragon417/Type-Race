local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)
local QuestEnums = require(Shared.Data.QuestEnums)

local QuestService = Knit.CreateService({
    Name = "QuestService",
    Client = {
        QuestsUpdated = Knit.CreateSignal(),
        ProgressUpdated = Knit.CreateSignal(),
    }
})

local RESET_INTERVAL = 1800 -- 30 minutes in seconds
local DataService
local completedQuests = {}

local function getQuestsByType(questType)
    local quests = {}
    for questName, questData in pairs(QuestEnums) do
        if questData.Type == questType then
            table.insert(quests, questName)
        end
    end
    return quests
end

local function getRandomQuest(questType)
    local quests = getQuestsByType(questType)
    if #quests > 0 then
        return quests[math.random(#quests)]
    end
    return nil
end

function QuestService:TrackWin(player: Player)
    if not DataService then return end
    
    local session = DataService:getSession(player)
    if not session or not session.Data or not session.Data.ActiveQuests then return end
    
    for _, questName in ipairs(session.Data.ActiveQuests) do
        local questData = QuestEnums[questName]
        if questData and questData.Type == "Typing" then
            if questName == "Win 5 Games" then
                self:UpdateProgress(player, questName, 1)
            elseif questName == "Win a Game and Emote" then
                -- Mark that they've won, wait for emote
                if not session.Data._questFlags then
                    session.Data._questFlags = {}
                end
                session.Data._questFlags.hasWonForEmote = true
            end
        end
    end
end

function QuestService:TrackEmote(player: Player)
    if not DataService then return end
    
    local session = DataService:getSession(player)
    if not session or not session.Data or not session.Data.ActiveQuests then return end
    
    -- Check if they completed a win first
    if session.Data._questFlags and session.Data._questFlags.hasWonForEmote then
        for _, questName in ipairs(session.Data.ActiveQuests) do
            if questName == "Win a Game and Emote" then
                self:UpdateProgress(player, questName, 1)
                session.Data._questFlags.hasWonForEmote = false
                break
            end
        end
    end
end

function QuestService:TrackWordTyped(player: Player)
    if not DataService then return end
    
    local session = DataService:getSession(player)
    if not session or not session.Data or not session.Data.ActiveQuests then return end
    
    for _, questName in ipairs(session.Data.ActiveQuests) do
        if questName == "Type 500 Words" then
            self:UpdateProgress(player, questName, 1)
            break
        end
    end
end

function QuestService:TrackWinStreak(player: Player, streakAmount: number)
    if not DataService then return end
    
    local session = DataService:getSession(player)
    if not session or not session.Data or not session.Data.ActiveQuests then return end
    
    for _, questName in ipairs(session.Data.ActiveQuests) do
        if questName == "Earn 3 Win Streak" then
            -- Only update if they reached the streak
            if streakAmount >= 3 then
                session.Data.QuestProgress = session.Data.QuestProgress or {}
                if (session.Data.QuestProgress[questName] or 0) < 3 then
                    self:UpdateProgress(player, questName, 3)
                end
            end
            break
        end
    end
end

function QuestService:TrackPerfectGame(player: Player)
    if not DataService then return end
    
    local session = DataService:getSession(player)
    if not session or not session.Data or not session.Data.ActiveQuests then return end
    
    for _, questName in ipairs(session.Data.ActiveQuests) do
        if questName == "Complete Without Errors" then
            self:UpdateProgress(player, questName, 1)
            break
        end
    end
end

function QuestService:TrackKeyboardPurchase(player: Player)
    if not DataService then return end
    
    local session = DataService:getSession(player)
    if not session or not session.Data or not session.Data.ActiveQuests then return end
    
    for _, questName in ipairs(session.Data.ActiveQuests) do
        if questName == "Purchase 3 Keyboards" then
            self:UpdateProgress(player, questName, 1)
            break
        end
    end
end

function QuestService:GenerateQuestsForPlayer(player: Player)
    if not DataService then return end
    
    local session = DataService.waitForSession(player, 10)
    if not session or not session.Data then return end
    
    local questNames = {}
    
    -- Get 3 random quests from different types
    local typingQuest = getRandomQuest("Typing")
    if typingQuest then
        table.insert(questNames, typingQuest)
    end
    
    local shopQuest = getRandomQuest("Shop")
    if shopQuest then
        table.insert(questNames, shopQuest)
    end
    
    -- Get one more random quest
    local allQuestNames = {}
    for questName, _ in pairs(QuestEnums) do
        if not table.find(questNames, questName) then
            table.insert(allQuestNames, questName)
        end
    end
    
    if #allQuestNames > 0 then
        local randomQuestName = allQuestNames[math.random(#allQuestNames)]
        table.insert(questNames, randomQuestName)
    end
    
    local uniqueQuestNames = {}
    local seen = {}
    for _, questName in ipairs(questNames) do
        if not seen[questName] then
            seen[questName] = true
            table.insert(uniqueQuestNames, questName)
        end
    end
    questNames = uniqueQuestNames
    
    session.Data.ActiveQuests = questNames
    session.Data.LastQuestResetTime = os.time()
    session.Data.QuestProgress = {}
    
    local quests = {}
    for _, questName in questNames do
        table.insert(quests, {
            Name = questName,
            Data = QuestEnums[questName]
        })
    end
    
    self.Client.QuestsUpdated:Fire(player, quests, session.Data.LastQuestResetTime)
end

function QuestService:GetActiveQuests(player: Player)
    if not DataService then return {}, 0 end
    
    local session = DataService.waitForSession(player, 10)
    if not session or not session.Data then return {}, 0 end
    
    if not session.Data.ActiveQuests or not session.Data.LastQuestResetTime then
        self:GenerateQuestsForPlayer(player)
    else
        local currentTime = os.time()
        if currentTime - session.Data.LastQuestResetTime >= RESET_INTERVAL then
            self:GenerateQuestsForPlayer(player)
        end
    end
    
    local quests = {}
    if session.Data.ActiveQuests then
        for _, questName in session.Data.ActiveQuests do
            if QuestEnums[questName] then
                table.insert(quests, {
                    Name = questName,
                    Data = QuestEnums[questName]
                })
            end
        end
    end
    
    return quests, session.Data.LastQuestResetTime or 0
end

function QuestService:GetPlayerProgress(player: Player)
    if not DataService then return {} end
    
    local session = DataService.waitForSession(player, 10)
    if not session or not session.Data then return {} end
    
    return session.Data.QuestProgress or {}
end

function QuestService:UpdateProgress(player: Player, questName: string, amount: number)
    if not DataService then return 0 end
    
    local session = DataService:getSession(player)
    if not session or not session.Data then return 0 end
    
    if not session.Data.QuestProgress then
        session.Data.QuestProgress = {}
    end
    
    local progress = session.Data.QuestProgress[questName] or 0
    progress = progress + amount
    
    session.Data.QuestProgress[questName] = progress
    
    self.Client.ProgressUpdated:Fire(player, questName, progress)
    
    local questData = QuestEnums[questName]
    local completionKey = player.UserId .. "_" .. questName
    if questData and progress >= questData.Goal and not completedQuests[completionKey] then
        completedQuests[completionKey] = true
        self:CompleteQuest(player, questName)
    end
    
    return progress
end

function QuestService:ResetCompletionTracking()
    table.clear(completedQuests)
end

function QuestService:CompleteQuest(player: Player, questName: string)
    local questData = QuestEnums[questName]
    if not questData or not DataService then return end
    
    local session = DataService:getSession(player)
    if session and session.Data then
        if not session.Data.Coins then
            session.Data.Coins = 0
        end
        session.Data.Coins = session.Data.Coins + questData.Reward
        DataService:Replicate(player, "Coins")
    end
end

function QuestService.Client:GetActiveQuests(player: Player)
    return self.Server:GetActiveQuests(player)
end

function QuestService.Client:GetPlayerProgress(player: Player)
    return self.Server:GetPlayerProgress(player)
end

function QuestService:KnitStart()
    task.spawn(function()
        while true do
            task.wait(30)
            if DataService then
                for _, player in Players:GetPlayers() do
                    local session = DataService:getSession(player)
                    if session and session.Data and session.Data.LastQuestResetTime then
                        local currentTime = os.time()
                        if currentTime - session.Data.LastQuestResetTime >= RESET_INTERVAL then
                            self:GenerateQuestsForPlayer(player)
                        end
                    end
                end
            end
        end
    end)
end

function QuestService:KnitInit() 
    DataService = Knit.GetService("DataService")
end

return QuestService
