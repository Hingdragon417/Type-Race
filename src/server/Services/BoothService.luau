local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local BoothService = Knit.CreateService({
    Name = "BoothService",
    Client = {
        UpdateCamera = Knit.CreateSignal(),
        RevertCamera = Knit.CreateSignal(),
        StartGame = Knit.CreateSignal(),
        BeginCountdown = Knit.CreateSignal(),
        PlayerWon = Knit.CreateSignal(),
        PlayerLost = Knit.CreateSignal(),
        ShowGameResult = Knit.CreateSignal(),
        ReportWPM = Knit.CreateSignal(),
        ValidateWordCompletion = Knit.CreateSignal(),
        UpdateWPM = Knit.CreateSignal(),
        UpdateOpponentProgress = Knit.CreateSignal(),
        UpdateBoothPlayerCount = Knit.CreateSignal(),
    }
})

local REQUIRED_PLAYERS = 2
local COUNTDOWN_SECONDS = 5
local WORD_COUNT = 35
local MAX_ERRORS = 5

local activeBooths = {}
local boothCountdowns = {}
local activeGames = {}
local playerErrors = {}
local playerWordsCompleted = {}
local spawnedKeyboards = {}
local playerWPM = {}
local playerTypingStats = {}
local wpmUpdateLoops = {}
local _hasPlayerWon = {}
local DataService
local TypewriterShopService
local QuestService

local function isPlayerInBooth(player: Player): boolean
    return activeBooths[player] ~= nil
end

local function getPlayersInBooth(boothModel: Model): {Player}
    local players = {}
    for player, booth in pairs(activeBooths) do
        if booth == boothModel then
            table.insert(players, player)
        end
    end
    return players
end

local function countPlayersInBooth(boothModel: Model): number
    return #getPlayersInBooth(boothModel)
end

local function isGameActive(boothModel: Model): boolean
    return activeGames[boothModel] ~= nil
end

local function removeSpawnedKeyboard(player: Player, boothModel: Model)
    if not spawnedKeyboards[boothModel] then
        return
    end
    
    local keyboardModel = spawnedKeyboards[boothModel][player]
    if keyboardModel and keyboardModel.Parent then
        keyboardModel:Destroy()
    end
    
    spawnedKeyboards[boothModel][player] = nil
end

local function calculateWPM(player: Player, boothModel: Model): number
    local stats = playerTypingStats[player]
    if not stats then return 0 end
    
    local elapsedTime = tick() - stats.startTime
    local elapsedMinutes = elapsedTime / 60
    
    if elapsedMinutes == 0 then return 0 end
    
    local timeSinceLastType = tick() - stats.lastTypeTime
    local decayFactor = 1
    if timeSinceLastType > 2 then
        decayFactor = math.max(0.1, 1 - ((timeSinceLastType - 2) * 0.1))
    end
    
    local wordsTyped = stats.correctWordCount
    local baseWPM = wordsTyped / elapsedMinutes
    
    return math.floor(baseWPM * decayFactor)
end

local function startWPMUpdates(boothModel: Model)
    if wpmUpdateLoops[boothModel] then
        task.cancel(wpmUpdateLoops[boothModel])
    end
    
    wpmUpdateLoops[boothModel] = task.spawn(function()
        while isGameActive(boothModel) do
            local playersInBooth = getPlayersInBooth(boothModel)
            for _, player in ipairs(playersInBooth) do
                local wpm = calculateWPM(player, boothModel)
                BoothService.Client.UpdateWPM:Fire(player, wpm)
            end
            task.wait(0.1)
        end
    end)
end

local function stopWPMUpdates(boothModel: Model)
    if wpmUpdateLoops[boothModel] then
        task.cancel(wpmUpdateLoops[boothModel])
        wpmUpdateLoops[boothModel] = nil
    end
end

local function endGame(boothModel: Model)
    stopWPMUpdates(boothModel)
    activeGames[boothModel] = nil
    
    local playersInBooth = getPlayersInBooth(boothModel)
    for _, player in ipairs(playersInBooth) do
        playerErrors[player] = nil
        playerWordsCompleted[player] = nil
        playerWPM[player] = nil
        playerTypingStats[player] = nil
        _hasPlayerWon[player] = nil
    end
end

local function startGame(boothModel: Model, words: {string})
    if isGameActive(boothModel) then
        return
    end
    
    activeGames[boothModel] = {
        words = words,
        startTime = tick(),
    }
    
    local playersInBooth = getPlayersInBooth(boothModel)
    for _, player in ipairs(playersInBooth) do
        playerErrors[player] = 0
        playerWordsCompleted[player] = 0
        _hasPlayerWon[player] = nil
        playerTypingStats[player] = {
            startTime = tick(),
            lastTypeTime = tick(),
            correctWordCount = 0,
            totalCharactersTyped = 0,
        }
    end
    
    for _, player in ipairs(playersInBooth) do
        BoothService.Client.StartGame:Fire(player, boothModel, words)
    end
    
    startWPMUpdates(boothModel)
end

local function kickPlayerFromSeat(player: Player)
    if not player or not player.Parent then
        return
    end
    
    local character = player.Character
    if not character then
        return
    end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if humanoid and humanoid.SeatPart then
        humanoid.Sit = false
    end
end

local function updatePlayerStats(player: Player, won: boolean, averageWPM: number)
    if not DataService then
        return
    end
    
    local session = DataService:getSession(player)
    if not session or not session.Data then
        return
    end
    
    local data = session.Data
    
    if won then
        data.Coins = (data.Coins or 0) + 25
        data.Wins = (data.Wins or 0) + 1
        data.Winstreak = (data.Winstreak or 0) + 1
        
        if data.Winstreak > (data.HighestWinstreak or 0) then
            data.HighestWinstreak = data.Winstreak
        end
        
        -- Track quest progress
        if QuestService then
            QuestService:TrackWin(player)
            QuestService:TrackWinStreak(player, data.Winstreak)
        end
    else
        data.Coins = (data.Coins or 0) + 10
        data.Losses = (data.Losses or 0) + 1
        
        local previousWinstreak = data.Winstreak or 0
        if previousWinstreak > 0 then
            if TypewriterShopService then
                TypewriterShopService:registerWinstreakRestore(player.UserId, previousWinstreak)
            end
            data.Winstreak = 0
            
            local success, result = pcall(function()
                MarketplaceService:PromptProductPurchase(player, 3462811274)
            end)
            
            if not success then
                warn("Failed to prompt product purchase:", result)
            end
        else
            data.Winstreak = 0
        end
    end
    
    data.WPM = math.floor(averageWPM)
    
    local totalGames = (data.Wins or 0) + (data.Losses or 0)
    if totalGames > 0 then
        data.WinRate = math.floor((data.Wins / totalGames) * 100)
    else
        data.WinRate = 0
    end
    
    DataService:updateLeaderstats(player, "Winstreak", data.Winstreak)
    DataService:updateLeaderstats(player, "Wins", data.Wins)
    
    DataService:Replicate(player, "Coins")
    DataService:Replicate(player, "Wins")
    DataService:Replicate(player, "Losses")
    DataService:Replicate(player, "Winstreak")
    DataService:Replicate(player, "HighestWinstreak")
    DataService:Replicate(player, "WPM")
    DataService:Replicate(player, "WinRate")
end

local function endGameWithWinner(boothModel: Model, winner: Player)
    local playersInBooth = getPlayersInBooth(boothModel)
    
    for _, player in ipairs(playersInBooth) do
        local wpm = playerWPM[player] or 0
        local won = player == winner
        updatePlayerStats(player, won, wpm)
        
        -- Track perfect game (0 errors) for winner
        if won and QuestService then
            local errors = playerErrors[player] or 0
            if errors == 0 then
                QuestService:TrackPerfectGame(player)
            end
        end
        
        if player == winner then
            BoothService.Client.ShowGameResult:Fire(player, true, winner.Name)
        else
            BoothService.Client.ShowGameResult:Fire(player, false, winner.Name)
        end
    end
    
    task.wait(3.5)
    
    for _, player in ipairs(playersInBooth) do
        kickPlayerFromSeat(player)
        BoothService:RemovePlayerFromBooth(player)
    end
    
    endGame(boothModel)
end

local function updateBoothStatus(boothModel: Model, playerCount: number, displayText: string?)
    local rootPart = boothModel:FindFirstChild("Root")
    if not rootPart then return end
    
    local billboardGui = rootPart:FindFirstChild("BillboardGui")
    if not billboardGui then return end

    local holderFrame = billboardGui:FindFirstChild("Holder")
    if not holderFrame then return end

    local statusLabel = holderFrame:FindFirstChild("Status")
    if statusLabel then
        statusLabel.Visible = true
        if displayText then
            statusLabel.Text = displayText
        else
            statusLabel.Text = playerCount .. "/2"
        end
    end
end

local function hideBoothStatus(boothModel: Model)
    local rootPart = boothModel:FindFirstChild("Root")
    if not rootPart then return end

    local billboardGui = rootPart:FindFirstChild("BillboardGui")
    if not billboardGui then return end
    
    local holderFrame = billboardGui:FindFirstChild("Holder")
    if not holderFrame then return end

    local statusLabel = holderFrame:FindFirstChild("Status")
    if statusLabel then
        statusLabel.Visible = false
    end
end

local function loadWordModule()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if shared then
        local wordModule = shared:FindFirstChild("WordModule") or shared:FindFirstChild("WordModula")
        if wordModule then
            local success, module = pcall(function()
                return require(wordModule)
            end)
            if success then
                return module
            end
        end
    end
    
    local wordModule = ReplicatedStorage:FindFirstChild("WordModule") or ReplicatedStorage:FindFirstChild("WordModula")
    if wordModule then
        local success, module = pcall(function()
            return require(wordModule)
        end)
        if success then
            return module
        end
    end
    
    return nil
end

local function generateWords(count: number): {string}
    local wordModule = loadWordModule()
    local words = {}
    
    for i = 1, count do
        local word
        if wordModule and wordModule.GetRandomWord then
            word = wordModule.GetRandomWord()
        end
        
        if type(word) ~= "string" or #word == 0 then
            word = "word" .. tostring(i)
        end
        
        table.insert(words, word)
    end
    
    return words
end

local function startBoothCountdown(boothModel: Model)
    if boothCountdowns[boothModel] then
        return
    end
    
    boothCountdowns[boothModel] = true
    
    task.spawn(function()
        for i = COUNTDOWN_SECONDS, 1, -1 do
            local playerCount = countPlayersInBooth(boothModel)
            
            if playerCount < REQUIRED_PLAYERS then
                updateBoothStatus(boothModel, playerCount)
                boothCountdowns[boothModel] = nil
                return
            end
            
            updateBoothStatus(boothModel, playerCount, "Game Starting in " .. tostring(i))
            task.wait(1)
        end
        
        if countPlayersInBooth(boothModel) >= REQUIRED_PLAYERS then
            hideBoothStatus(boothModel)
            
            local playersInBooth = getPlayersInBooth(boothModel)
            
            for _, player in ipairs(playersInBooth) do
                if player.Character then
                    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                    if humanoid then
                        humanoid.JumpPower = 0
                        humanoid.JumpHeight = 0
                    end
                end
            end
            
            for _, player in ipairs(playersInBooth) do
                BoothService.Client.BeginCountdown:Fire(player, COUNTDOWN_SECONDS)
            end
            
            task.wait(0.1)
            
            local words = generateWords(WORD_COUNT)
            startGame(boothModel, words)
        end
        
        boothCountdowns[boothModel] = nil
    end)
end

local function spawnKeyboardForPlayer(player: Player, boothModel: Model, seatName: string)
    local DataService = Knit.GetService("DataService")
    if not DataService then
        return
    end
    
    local session = DataService:getSession(player)
    if not session or not session.Data then
        return
    end
    
    local equippedKeyboard = session.Data.EquippedKeyboard
    if not equippedKeyboard then
        return
    end
    
    local keyboardsFolder = ReplicatedStorage:FindFirstChild("Assets")
    if keyboardsFolder then
        keyboardsFolder = keyboardsFolder:FindFirstChild("Keyboards")
    end
    
    if not keyboardsFolder then
        return
    end
    
    local keyboardModel = keyboardsFolder:FindFirstChild(equippedKeyboard)
    if not keyboardModel then
        return
    end
    
    local spawnName = (seatName == "Seat") and "KeyboardSpawn" or "KeyboardSpawn2"
    local spawnPoint = boothModel:FindFirstChild(spawnName, true)
    if not spawnPoint then
        return
    end
    
    local forward = spawnPoint.CFrame.LookVector
    local targetCFrame = CFrame.lookAt(spawnPoint.Position, spawnPoint.Position + forward)
    
    local clonedKeyboard = keyboardModel:Clone()
    clonedKeyboard:PivotTo(targetCFrame)
    clonedKeyboard.Parent = boothModel
    
    if not spawnedKeyboards[boothModel] then
        spawnedKeyboards[boothModel] = {}
    end
    spawnedKeyboards[boothModel][player] = clonedKeyboard
end

function BoothService:AddPlayerToBooth(player: Player, boothModel: Model)
    if not player or not player.Parent then
        return
    end
    
    if isPlayerInBooth(player) then
        return
    end
    
    activeBooths[player] = boothModel
    local playerCount = countPlayersInBooth(boothModel)
    
    self.Client.UpdateCamera:Fire(player, boothModel)
    updateBoothStatus(boothModel, playerCount)
    
    -- Notify all players in booth of the player count
    local playersInBooth = getPlayersInBooth(boothModel)
    for _, p in ipairs(playersInBooth) do
        self.Client.UpdateBoothPlayerCount:Fire(p, playerCount)
    end
    
    if playerCount >= REQUIRED_PLAYERS then
        startBoothCountdown(boothModel)
    end
end

function BoothService:RemovePlayerFromBooth(player: Player)
    if not player then
        return
    end
    
    local boothModel = activeBooths[player]
    if not boothModel then
        return
    end
    
    -- Check if game is active and player hasn't been processed yet
    -- Only update stats if player is leaving mid-game (not from endGameWithWinner cleanup)
    if isGameActive(boothModel) and _hasPlayerWon[player] == nil then
        local wpm = playerWPM[player] or 0
        updatePlayerStats(player, false, wpm)
        
        -- Check if there's another player who should win
        local playersInBooth = getPlayersInBooth(boothModel)
        for _, otherPlayer in ipairs(playersInBooth) do
            if otherPlayer ~= player and otherPlayer.Parent then
                -- The other player wins by default
                if not _hasPlayerWon[otherPlayer] then
                    _hasPlayerWon[otherPlayer] = true
                    task.spawn(function()
                        task.wait(0.1)
                        endGameWithWinner(boothModel, otherPlayer)
                    end)
                end
                break
            end
        end
    end
    
    removeSpawnedKeyboard(player, boothModel)
    
    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.JumpPower = 50
            humanoid.JumpHeight = 7.2
        end
    end
    
    activeBooths[player] = nil
    playerErrors[player] = nil
    playerWordsCompleted[player] = nil
    playerWPM[player] = nil
    playerTypingStats[player] = nil
    _hasPlayerWon[player] = nil
    
    local playerCount = countPlayersInBooth(boothModel)
    updateBoothStatus(boothModel, playerCount)
    
    -- Notify remaining players in booth of the new player count
    local playersInBooth = getPlayersInBooth(boothModel)
    for _, p in ipairs(playersInBooth) do
        self.Client.UpdateBoothPlayerCount:Fire(p, playerCount)
    end
    
    boothCountdowns[boothModel] = nil
    
    if isGameActive(boothModel) and playerCount == 0 then
        endGame(boothModel)
    end
    
    self.Client.RevertCamera:Fire(player)
end

local function onSeatOccupancyChanged(seat: Seat, boothModel: Model)
    local occupant = seat.Occupant
    
    if occupant then
        local character = occupant.Parent
        if not character then return end
        
        local player = Players:GetPlayerFromCharacter(character)
        if player then
            BoothService:AddPlayerToBooth(player, boothModel)
            spawnKeyboardForPlayer(player, boothModel, seat.Name)
        end
    else
        local playersInBooth = getPlayersInBooth(boothModel)
        for _, player in ipairs(playersInBooth) do
            local character = player.Character
            if character then
                local humanoid = character:FindFirstChild("Humanoid")
                if humanoid and humanoid.SeatPart == seat then
                    BoothService:RemovePlayerFromBooth(player)
                    break
                end
            end
        end
    end
end

local function setupBoothListeners(boothModel: Model)
    local seatsFolder = boothModel:WaitForChild("Seats")
    for _, seat in pairs(seatsFolder:GetChildren()) do
        if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
            seat:GetPropertyChangedSignal("Occupant"):Connect(function()
                onSeatOccupancyChanged(seat, boothModel)
            end)
        end
    end
end

function BoothService:KnitStart()
    TypewriterShopService = Knit.GetService("TypewriterShopService")
    QuestService = Knit.GetService("QuestService")
    
    local boothsFolder = game.Workspace:WaitForChild("BoothsFolder")
    local boothModels = boothsFolder:GetChildren()
    
    for _, booth in ipairs(boothModels) do
        setupBoothListeners(booth)
    end
    
    self.Client.PlayerWon:Connect(function(player)
        if not player or not player.Parent then
            return
        end
        
        local boothModel = activeBooths[player]
        if not boothModel or not isGameActive(boothModel) then
            return
        end
        
        local gameData = activeGames[boothModel]
        if not gameData then
            return
        end
        
        if _hasPlayerWon[player] then
            return
        end
        
        _hasPlayerWon[player] = true
        
        endGameWithWinner(boothModel, player)
    end)
    
    self.Client.PlayerLost:Connect(function(player)
        if not player or not player.Parent then
            return
        end
        
        local boothModel = activeBooths[player]
        if not boothModel or not isGameActive(boothModel) then
            return
        end
        
        if not playerErrors[player] then
            return
        end
        
        playerErrors[player] = playerErrors[player] + 1
        
        if playerErrors[player] >= MAX_ERRORS then
            if _hasPlayerWon[player] ~= nil then
                return
            end
            
            _hasPlayerWon[player] = false
            
            local playersInBooth = getPlayersInBooth(boothModel)
            local winner
            for _, otherPlayer in ipairs(playersInBooth) do
                if otherPlayer ~= player then
                    winner = otherPlayer
                    if not _hasPlayerWon[winner] then
                        _hasPlayerWon[winner] = true
                    end
                    break
                end
            end
            
            if winner then
                endGameWithWinner(boothModel, winner)
            end
        end
    end)
    
    self.Client.ValidateWordCompletion:Connect(function(player, wordIndex, word)
        if not player or not player.Parent then
            return
        end
        
        local boothModel = activeBooths[player]
        if not boothModel or not isGameActive(boothModel) then
            return
        end
        
        local gameData = activeGames[boothModel]
        if not gameData or not gameData.words then
            return
        end
        
        if wordIndex < 1 or wordIndex > #gameData.words then
            return
        end
        
        if gameData.words[wordIndex] ~= word then
            return
        end
        
        local stats = playerTypingStats[player]
        if stats then
            stats.correctWordCount = stats.correctWordCount + 1
            stats.lastTypeTime = tick()
            
            local currentWPM = calculateWPM(player, boothModel)
            playerWPM[player] = currentWPM
        end
        
        -- Track word typed for quest
        if QuestService then
            QuestService:TrackWordTyped(player)
        end
        
        playerWordsCompleted[player] = (playerWordsCompleted[player] or 0) + 1
        
        local gameData = activeGames[boothModel]
        local totalWords = gameData and gameData.words and #gameData.words or 1
        local progress = playerWordsCompleted[player] / totalWords
        
        local playersInBooth = getPlayersInBooth(boothModel)
        for _, otherPlayer in ipairs(playersInBooth) do
            if otherPlayer ~= player then
                BoothService.Client.UpdateOpponentProgress:Fire(otherPlayer, player.UserId, progress)
            end
        end
    end)
    
    Players.PlayerRemoving:Connect(function(player)
        if isPlayerInBooth(player) then
            self:RemovePlayerFromBooth(player)
        end
    end)
end

function BoothService:KnitInit()
    DataService = Knit.GetService("DataService")
end

return BoothService
