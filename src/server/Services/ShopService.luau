local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)
local ShopConfig = require(script.Parent.Parent.ShopConfig)

local ShopDataStore = DataStoreService:GetDataStore("ShopRotation_V3")
local ROTATION_INTERVAL = 900 -- 15 minutes in seconds
local SHOP_STOCK_COUNT = 3

local ShopService = Knit.CreateService({
    Name = "ShopService",
    Client = {}
})

local currentStock = {}
local nextRotationTime = 0
local DataService
local QuestService
local bobTweens = {}

local function getAvailableKeyboards()
    local keyboards = {}
    for name, data in pairs(ShopConfig.Keyboards) do
        table.insert(keyboards, {
            Name = name,
            Price = data.Price,
            DisplayName = data.DisplayName
        })
    end
    return keyboards
end

local function selectRandomKeyboards(count)
    local available = getAvailableKeyboards()
    local selected = {}
    
    for i = 1, math.min(count, #available) do
        local randomIndex = math.random(1, #available)
        table.insert(selected, available[randomIndex])
        table.remove(available, randomIndex)
    end
    
    return selected
end

local function getNextRotationTime()
    local currentTime = os.time()
    local hoursSinceEpoch = math.floor(currentTime / ROTATION_INTERVAL)
    return (hoursSinceEpoch + 1) * ROTATION_INTERVAL
end

local function loadOrCreateStock()
    local success, data = pcall(function()
        return ShopDataStore:GetAsync("CurrentStock")
    end)
    
    if success and data then
        currentStock = data.stock
        nextRotationTime = data.nextRotation
        
        if os.time() < nextRotationTime then
            print("[ShopService] Loaded existing shop stock")
            return true
        end
    end
    
    print("[ShopService] Creating new shop stock")
    currentStock = selectRandomKeyboards(SHOP_STOCK_COUNT)
    nextRotationTime = getNextRotationTime()
    
    pcall(function()
        ShopDataStore:SetAsync("CurrentStock", {
            stock = currentStock,
            nextRotation = nextRotationTime
        })
    end)
    
    return false
end

local function clearSpawnedKeyboards()
    for _, tween in ipairs(bobTweens) do
        if tween then
            tween:Cancel()
        end
    end
    bobTweens = {}
    
    local shopFolder = workspace:FindFirstChild("Shop")
    if not shopFolder then return end
    
    local spawnsFolder = shopFolder:FindFirstChild("Spawns")
    if not spawnsFolder then return end
    
    for _, spawn in ipairs(spawnsFolder:GetChildren()) do
        for _, child in ipairs(spawn:GetChildren()) do
            if child:IsA("Model") then
                child:Destroy()
            end
        end
    end
end

local function spawnKeyboardsInShop()
    local shopFolder = workspace:FindFirstChild("Shop")
    if not shopFolder then
        warn("[ShopService] Shop folder not found in workspace")
        return
    end
    
    local spawnsFolder = shopFolder:FindFirstChild("Spawns")
    if not spawnsFolder then
        warn("[ShopService] Spawns folder not found in Shop")
        return
    end
    
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    if not assets then
        warn("[ShopService] Assets folder not found")
        return
    end
    
    local shopKeyboards = assets:FindFirstChild("ShopKeyboards")
    if not shopKeyboards then
        warn("[ShopService] ShopKeyboards folder not found in Assets")
        return
    end
    
    clearSpawnedKeyboards()
    
    local spawns = spawnsFolder:GetChildren()
    if #spawns < SHOP_STOCK_COUNT then
        warn("[ShopService] Not enough spawn points")
        return
    end
    
    for i, keyboardData in ipairs(currentStock) do
        if i > #spawns then break end
        
        local keyboardModel = shopKeyboards:FindFirstChild(keyboardData.Name)
        if not keyboardModel then
            warn("[ShopService] Keyboard model not found:", keyboardData.Name)
            continue
        end
        
        local spawn = spawns[i]
        local clonedKeyboard = keyboardModel:Clone()
        
        local spawnCFrame = spawn.CFrame
        local forward = spawnCFrame.LookVector
        local targetCFrame = CFrame.lookAt(spawn.Position + Vector3.new(0, 2, 0), spawn.Position + Vector3.new(0, 2, 0) - forward) * CFrame.Angles(0, math.rad(90), 0)
        
        if clonedKeyboard.PrimaryPart then
            clonedKeyboard:SetPrimaryPartCFrame(targetCFrame)
        else
            local root = clonedKeyboard:FindFirstChild("Root")
            if root and root:IsA("BasePart") then
                root.CFrame = targetCFrame
            end
        end
        
        clonedKeyboard.Parent = spawn
        
        if not clonedKeyboard.PrimaryPart then
            local root = clonedKeyboard:FindFirstChild("Root")
            if root and root:IsA("BasePart") then
                clonedKeyboard.PrimaryPart = root
            end
        end
        
        if clonedKeyboard.PrimaryPart then
            -- Weld all parts to the PrimaryPart
            for _, descendant in ipairs(clonedKeyboard:GetDescendants()) do
                if descendant:IsA("BasePart") and descendant ~= clonedKeyboard.PrimaryPart then
                    descendant.Anchored = false
                    local weld = Instance.new("WeldConstraint")
                    weld.Part0 = clonedKeyboard.PrimaryPart
                    weld.Part1 = descendant
                    weld.Parent = clonedKeyboard.PrimaryPart
                end
            end
            
            local bobHeight = 0.3
            local bobSpeed = 2
            local baseCFrame = clonedKeyboard.PrimaryPart.CFrame
            
            local bobDown, bobUp
            local currentUpTween, currentDownTween
            local isBobbing = true
            
            bobUp = function()
                if not isBobbing then return end
                if not clonedKeyboard or not clonedKeyboard.Parent then return end
                if not clonedKeyboard.PrimaryPart or not clonedKeyboard.PrimaryPart.Parent then return end
                
                currentUpTween = TweenService:Create(
                    clonedKeyboard.PrimaryPart,
                    TweenInfo.new(bobSpeed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                    {CFrame = baseCFrame + Vector3.new(0, bobHeight, 0)}
                )
                currentUpTween.Completed:Connect(function()
                    bobDown()
                end)
                currentUpTween:Play()
                table.insert(bobTweens, currentUpTween)
            end
            
            bobDown = function()
                if not isBobbing then return end
                if not clonedKeyboard or not clonedKeyboard.Parent then return end
                if not clonedKeyboard.PrimaryPart or not clonedKeyboard.PrimaryPart.Parent then return end
                
                currentDownTween = TweenService:Create(
                    clonedKeyboard.PrimaryPart,
                    TweenInfo.new(bobSpeed, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                    {CFrame = baseCFrame}
                )
                currentDownTween.Completed:Connect(function()
                    bobUp()
                end)
                currentDownTween:Play()
                table.insert(bobTweens, currentDownTween)
            end
            
            bobUp()
            
            local proximityPrompt = Instance.new("ProximityPrompt")
            proximityPrompt.ActionText = "Buy"
            proximityPrompt.ObjectText = keyboardData.DisplayName
            proximityPrompt.MaxActivationDistance = 10
            proximityPrompt.RequiresLineOfSight = false
            proximityPrompt.Parent = clonedKeyboard.PrimaryPart
            
            proximityPrompt.Triggered:Connect(function(player)
                local session = DataService:getSession(player)
                if not session or not session.Data then
                    return
                end
                
                -- Check if player already owns this keyboard
                if session.Data.KeyboardInventory and table.find(session.Data.KeyboardInventory, keyboardData.Name) then
                    warn("[ShopService] Player", player.Name, "already owns", keyboardData.DisplayName)
                    return
                end
                
                local playerCoins = session.Data.Coins or 0
                local price = keyboardData.Price
                
                if playerCoins >= price then
                    session.Data.Coins = playerCoins - price
                    
                    if not session.Data.KeyboardInventory then
                        session.Data.KeyboardInventory = {}
                    end
                    
                    if not table.find(session.Data.KeyboardInventory, keyboardData.Name) then
                        table.insert(session.Data.KeyboardInventory, keyboardData.Name)
                    end
                    
                    DataService:Replicate(player, "Coins")
                    DataService:Replicate(player, "KeyboardInventory")
                    
                    -- Track keyboard purchase for quest
                    if QuestService then
                        QuestService:TrackKeyboardPurchase(player)
                    end
                    
                    -- Play purchase sound
                    local soundsFolder = game:GetService("SoundService"):FindFirstChild("Sounds")
                    if soundsFolder then
                        local purchaseSound = soundsFolder:FindFirstChild("Purchase")
                        if purchaseSound and purchaseSound:IsA("Sound") then
                            purchaseSound:Play()
                        end
                    end
                    
                    -- Emit confetti from player
                    local character = player.Character
                    if character then
                        local hrp = character:FindFirstChild("HumanoidRootPart")
                        local assetsFolder = game.ReplicatedStorage:FindFirstChild("Assets")
                        local confettiFolder = assetsFolder and assetsFolder:FindFirstChild("Confetti")
                        
                        if hrp and confettiFolder then
                            for _, emitter in pairs(confettiFolder:GetChildren()) do
                                if emitter:IsA("ParticleEmitter") then
                                    local clonedEmitter = emitter:Clone()
                                    clonedEmitter.Parent = hrp
                                    clonedEmitter:Emit(clonedEmitter:GetAttribute("EmitCount") or 20)
                                    task.delay(1, function()
                                        clonedEmitter:Destroy()
                                    end)
                                end
                            end
                        end
                    end
                    
                    -- Stop bobbing
                    isBobbing = false
                    if currentUpTween then currentUpTween:Cancel() end
                    if currentDownTween then currentDownTween:Cancel() end
                    
                    -- Spin animation - do 4x 90 degree rotations to complete a full spin
                    local startCFrame = clonedKeyboard.PrimaryPart.CFrame
                    
                    local function doSpin(rotations, currentRotation)
                        if currentRotation > rotations then
                            baseCFrame = clonedKeyboard.PrimaryPart.CFrame
                            isBobbing = true
                            bobUp()
                            return
                        end
                        
                        local currentCF = clonedKeyboard.PrimaryPart.CFrame
                        local spinTween = TweenService:Create(
                            clonedKeyboard.PrimaryPart,
                            TweenInfo.new(0.125, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
                            {CFrame = currentCF * CFrame.Angles(math.rad(90), 0, 0)}
                        )
                        spinTween.Completed:Connect(function()
                            doSpin(rotations, currentRotation + 1)
                        end)
                        spinTween:Play()
                    end
                    
                    doSpin(4, 1)
                else
                    print("[ShopService] Not enough coins")
                end
            end)
        end
        
        local display = clonedKeyboard:FindFirstChild("Display")
        if display then
            local billboardGui = display:FindFirstChild("BillboardGui")
            if billboardGui then
                local frame = billboardGui:FindFirstChild("Frame")
                if frame then
                    local nameLabel = frame:FindFirstChild("Name")
                    if nameLabel and nameLabel:IsA("TextLabel") then
                        nameLabel.Text = keyboardData.DisplayName
                    end
                    
                    local priceLabel = frame:FindFirstChild("Price")
                    if priceLabel and priceLabel:IsA("TextLabel") then
                        priceLabel.Text = tostring(keyboardData.Price) .. " Coins"
                    end
                end
            end
        end
    end
end

local function updateShopTimer()
    local shopFolder = workspace:FindFirstChild("Shop")
    if not shopFolder then return end
    
    local display = shopFolder:FindFirstChild("Display")
    if not display then return end
    
    local billboardGui = display:FindFirstChild("BillboardGui")
    if not billboardGui then return end
    
    local timeLabel = billboardGui:FindFirstChild("Time")
    if not timeLabel or not timeLabel:IsA("TextLabel") then return end
    
    local timeRemaining = nextRotationTime - os.time()
    if timeRemaining < 0 then
        timeLabel.Text = "Rotating..."
        return
    end
    
    local hours = math.floor(timeRemaining / 3600)
    local minutes = math.floor((timeRemaining % 3600) / 60)
    local seconds = timeRemaining % 60
    
    timeLabel.Text = string.format("Next Rotation: %02d:%02d:%02d", hours, minutes, seconds)
end

local function checkRotation()
    if os.time() >= nextRotationTime then
        print("[ShopService] Rotating shop stock")
        loadOrCreateStock()
        spawnKeyboardsInShop()
    end
end

function ShopService:KnitStart()
    loadOrCreateStock()
    spawnKeyboardsInShop()
    
    task.spawn(function()
        while true do
            updateShopTimer()
            task.wait(1)
        end
    end)
    
    task.spawn(function()
        while true do
            task.wait(60)
            checkRotation()
        end
    end)
end

function ShopService:KnitInit()
    DataService = Knit.GetService("DataService")
    QuestService = Knit.GetService("QuestService")
end

return ShopService
