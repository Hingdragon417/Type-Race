local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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

local function endGame(boothModel: Model)
    activeGames[boothModel] = nil
    
    local playersInBooth = getPlayersInBooth(boothModel)
    for _, player in ipairs(playersInBooth) do
        playerErrors[player] = nil
        playerWordsCompleted[player] = nil
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
    end
    
    for _, player in ipairs(playersInBooth) do
        BoothService.Client.StartGame:Fire(player, boothModel, words)
    end
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

local function endGameWithWinner(boothModel: Model, winner: Player)
    local playersInBooth = getPlayersInBooth(boothModel)
    
    for _, player in ipairs(playersInBooth) do
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
    
    local clonedKeyboard = keyboardModel:Clone()
    clonedKeyboard:PivotTo(spawnPoint.CFrame)
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
    
    removeSpawnedKeyboard(player, boothModel)
    
    activeBooths[player] = nil
    playerErrors[player] = nil
    playerWordsCompleted[player] = nil
    
    local playerCount = countPlayersInBooth(boothModel)
    updateBoothStatus(boothModel, playerCount)
    
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
        
        print(player.Name .. " won the game!")
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
            print(player.Name .. " lost the game (3 errors)!")
            
            local playersInBooth = getPlayersInBooth(boothModel)
            local winner
            for _, otherPlayer in ipairs(playersInBooth) do
                if otherPlayer ~= player then
                    winner = otherPlayer
                    print(otherPlayer.Name .. " won the game!")
                    break
                end
            end
            
            if winner then
                endGameWithWinner(boothModel, winner)
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
end

return BoothService
