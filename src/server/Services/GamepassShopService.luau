local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)

local TypewriterStockStore = DataStoreService:GetDataStore("TypewriterStock_V1")
local GAMEPASS_ID = 1596090373
local INITIAL_STOCK = 100

local COIN_PRODUCTS = {
    [3462330237] = 100,  -- 100 coins
    [3462330792] = 500,  -- 500 coins
    [3462331296] = 1000, -- 1000 coins
}

local DataService

local TypewriterShopService = Knit.CreateService({
    Name = "TypewriterShopService",
    Client = {
        StockUpdated = Knit.CreateSignal(),
    },
})

local currentStock = INITIAL_STOCK

function TypewriterShopService:getStock()
    return currentStock
end

function TypewriterShopService:setStock(newStock)
    currentStock = math.max(0, newStock)
    
    -- Save to DataStore
    local success, err = pcall(function()
        TypewriterStockStore:SetAsync("CurrentStock", currentStock)
    end)
    
    if not success then
        warn("[TypewriterShopService] Failed to save stock:", err)
    end
    
    -- Notify all clients
    self.Client.StockUpdated:FireAll(currentStock)
end

function TypewriterShopService:loadStock()
    local success, result = pcall(function()
        return TypewriterStockStore:GetAsync("CurrentStock")
    end)
    
    if success and result then
        currentStock = result
    else
        currentStock = INITIAL_STOCK
        self:setStock(currentStock)
    end
end

function TypewriterShopService:grantCoins(player, amount)
    local session = DataService:getSession(player)
    if not session then
        warn("[TypewriterShopService] No session found for player:", player.Name)
        return false
    end
    
    session.Data.Coins = session.Data.Coins + amount
    DataService:Replicate(player, "Coins")
    
    return true
end

function TypewriterShopService:addTypewriterToInventory(player)
    local session = DataService:getSession(player)
    if not session then
        warn("[TypewriterShopService] No session found for player:", player.Name)
        return false
    end
    
    local inventory = session.Data.KeyboardInventory
    
    -- Check if already owns TypeWriter
    if table.find(inventory, "TypeWriter") then
        warn("[TypewriterShopService] Player already owns TypeWriter:", player.Name)
        return false
    end
    
    -- Add to inventory
    table.insert(inventory, "TypeWriter")
    DataService:Replicate(player, "KeyboardInventory")
    
    return true
end

function TypewriterShopService:checkAndGrantGamepass(player)
    -- Check if player owns the gamepass
    local ownsGamepass = false
    local success, result = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GAMEPASS_ID)
    end)
    
    if success then
        ownsGamepass = result
    else
        warn("[TypewriterShopService] Error checking gamepass ownership:", result)
        return
    end
    
    if not ownsGamepass then
        return
    end
    
    -- Check if there's stock available
    if currentStock <= 0 then
        warn("[TypewriterShopService] Out of stock for player:", player.Name)
        return
    end
    
    -- Add typewriter to player's inventory
    local wasAdded = self:addTypewriterToInventory(player)
    
    if wasAdded then
        -- Decrease stock
        self:setStock(currentStock - 1)
    end
end

function TypewriterShopService:processReceipt(receiptInfo)
    local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
    
    if not player then
        -- Player left before receipt was processed
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    local productId = receiptInfo.ProductId
    local coinAmount = COIN_PRODUCTS[productId]
    
    if not coinAmount then
        -- Unknown product
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    -- Grant coins
    local success = self:grantCoins(player, coinAmount)
    
    if success then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    else
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

function TypewriterShopService.Client:GetTypewriterStock(player)
    return self.Server:getStock()
end

function TypewriterShopService:KnitInit()
    DataService = Knit.GetService("DataService")
    
    -- Load stock from DataStore
    self:loadStock()
    
    -- Set up receipt processing for coin products
    MarketplaceService.ProcessReceipt = function(receiptInfo)
        return self:processReceipt(receiptInfo)
    end
    
    -- Check for gamepass ownership when players join
    Players.PlayerAdded:Connect(function(player)
        task.wait(2) -- Wait for data to load
        self:checkAndGrantGamepass(player)
    end)
    
    -- Check existing players
    for _, player in Players:GetPlayers() do
        task.spawn(function()
            task.wait(2)
            self:checkAndGrantGamepass(player)
        end)
    end
    
    -- Listen for gamepass purchases
    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
        if gamepassId == GAMEPASS_ID and wasPurchased then
            self:checkAndGrantGamepass(player)
        end
    end)
end

return TypewriterShopService
