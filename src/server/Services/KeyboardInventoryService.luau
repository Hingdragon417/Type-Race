local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)

local DataService

local KeyboardInventoryService = Knit.CreateService({
    Name = "KeyboardInventoryService",
    Client = {
        KeyboardEquipped = Knit.CreateSignal(),
    }
})

function KeyboardInventoryService.Client:EquipKeyboard(player, keyboardName)
    if not DataService then
        return false
    end
    
    local session = DataService:getSession(player)
    if not session or not session.Data then
        return false
    end
    
    local inventory = session.Data.KeyboardInventory
    if not inventory or type(inventory) ~= "table" then
        return false
    end
    
    local hasKeyboard = false
    for _, ownedKeyboard in ipairs(inventory) do
        if ownedKeyboard == keyboardName then
            hasKeyboard = true
            break
        end
    end
    
    if not hasKeyboard then
        return false
    end
    
    session.Data.EquippedKeyboard = keyboardName
    DataService:Replicate(player, "EquippedKeyboard")
    
    self.KeyboardEquipped:Fire(player, keyboardName)
    
    return true
end

function KeyboardInventoryService:KnitStart()

end

function KeyboardInventoryService:KnitInit()
    DataService = Knit.GetService("DataService")
end

return KeyboardInventoryService
