local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GAMEPASS_ID = 1596090373
local COIN_PRODUCT_IDS = {
    [3462330237] = 100,  -- Frame (100 coins)
    [3462330792] = 500,  -- Frame2 (500 coins)
    [3462331296] = 1000, -- Frame3 (1000 coins)
}

local GamepassShopController = Knit.CreateController({
    Name = "GamepassShopController",
})

local TypewriterShopService

function GamepassShopController:setupBuyButton()
    local screenGui = playerGui:WaitForChild("ScreenGui")
    local frames = screenGui:WaitForChild("Frames")
    local shop = frames:WaitForChild("Shop")
    local container = shop:WaitForChild("Container")
    local scrollingFrame = container:WaitForChild("ScrollingFrame")
    
    -- Typewriter gamepass button
    local typewritter = scrollingFrame:WaitForChild("Typewritter")
    local holder = typewritter:WaitForChild("Holder")
    local buyButton = holder:WaitForChild("BuyButton")
    
    buyButton.MouseButton1Click:Connect(function()
        self:purchaseTypewriter()
    end)
    
    -- Coin product buttons
    local coins = scrollingFrame:WaitForChild("Coins")
    local coinsHolder = coins:WaitForChild("Holder")
    local coinsFrame = coinsHolder:WaitForChild("Frame")
    
    local coinFrames = {
        {frame = coinsFrame:WaitForChild("Frame"), productId = 3462330237},
        {frame = coinsFrame:WaitForChild("Frame2"), productId = 3462330792},
        {frame = coinsFrame:WaitForChild("Frame3"), productId = 3462331296}
    }
    
    for _, data in ipairs(coinFrames) do
        local buyButton = data.frame:WaitForChild("BuyButton")
        buyButton.MouseButton1Click:Connect(function()
            self:purchaseCoins(data.productId)
        end)
    end
end

function GamepassShopController:purchaseTypewriter()
    MarketplaceService:PromptGamePassPurchase(player, GAMEPASS_ID)
end

function GamepassShopController:purchaseCoins(productId)
    MarketplaceService:PromptProductPurchase(player, productId)
end

function GamepassShopController:onPurchaseFinished(receiptInfo)
    if receiptInfo.PlayerId == player.UserId then
        if receiptInfo.PurchaseSuccess then
            -- Purchase successful - server will handle adding to inventory
        end
    end
end

function GamepassShopController:updateStockDisplay(stock)
    local screenGui = playerGui:WaitForChild("ScreenGui")
    local frames = screenGui:WaitForChild("Frames")
    local shop = frames:WaitForChild("Shop")
    local container = shop:WaitForChild("Container")
    local scrollingFrame = container:WaitForChild("ScrollingFrame")
    local typewritter = scrollingFrame:WaitForChild("Typewritter")
    local holder = typewritter:WaitForChild("Holder")
    local stockLabel = holder:WaitForChild("Stock")
    
    if stockLabel and stockLabel:IsA("TextLabel") then
        stockLabel.Text = "Stock: " .. tostring(stock)
    end
end

function GamepassShopController:KnitStart() 
    TypewriterShopService = Knit.GetService("TypewriterShopService")
    
    self:setupBuyButton()
    
    -- Listen for stock updates from server
    TypewriterShopService.StockUpdated:Connect(function(stock)
        self:updateStockDisplay(stock)
    end)
    
    -- Request initial stock
    TypewriterShopService:GetTypewriterStock():andThen(function(stock)
        self:updateStockDisplay(stock)
    end)
end

function GamepassShopController:KnitInit()
    
end

return GamepassShopController