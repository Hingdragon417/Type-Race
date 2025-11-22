local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)
local ShopConfig = require(script.Parent.Parent.ShopConfig)

local ShopDataStore = DataStoreService:GetDataStore("ShopRotation_V1")
local ROTATION_INTERVAL = 3 * 60 * 60 -- 3 hours in seconds
local SHOP_STOCK_COUNT = 3

local ShopService = Knit.CreateService({
    Name = "ShopService",
    Client = {}
})

local currentStock = {}
local nextRotationTime = 0

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
        
        local root = clonedKeyboard:FindFirstChild("Root")
        if root then
            local proximityPrompt = Instance.new("ProximityPrompt")
            proximityPrompt.ActionText = "Buy"
            proximityPrompt.ObjectText = keyboardData.DisplayName
            proximityPrompt.MaxActivationDistance = 10
            proximityPrompt.RequiresLineOfSight = false
            proximityPrompt.Parent = root
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
    
    print("[ShopService] Spawned", #currentStock, "keyboards in shop")
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

end

return ShopService
