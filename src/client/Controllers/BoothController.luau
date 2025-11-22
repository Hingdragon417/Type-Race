local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local BoothController = Knit.CreateController({
    Name = "BoothController",
    currentWords = {},
    currentIndex = 1,
    typingConnection = nil,
    errorCount = 0,
    startTime = 0,
    correctWordCount = 0,
    totalCharactersTyped = 0,
    lastTypeTime = 0,
    wpmUpdateLoop = nil,
})

function BoothController:UpdateCamera(boothModel)
    local camera = workspace.CurrentCamera
    local camPart = boothModel:FindFirstChild("Camera")
    if camPart then
        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = camPart.CFrame
    end
end

function BoothController:RevertCamera()
    workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

function BoothController:GetLocalPlayer()
    return game.Players.LocalPlayer
end

function BoothController:GetPlayerGui()
    local player = self:GetLocalPlayer()
    return player and player:FindFirstChild("PlayerGui")
end

function BoothController:GetScreenGui()
    local playerGui = self:GetPlayerGui()
    if not playerGui then return nil end
    
    local screenGui = playerGui:FindFirstChild("ScreenGui")
    if not screenGui then
        for _, child in ipairs(playerGui:GetChildren()) do
            if child:IsA("ScreenGui") then
                return child
            end
        end
    end
    return screenGui
end

function BoothController:GetHumanoid()
    local player = self:GetLocalPlayer()
    local character = player and player.Character
    return character and character:FindFirstChild("Humanoid")
end

function BoothController:SetJumpAbility(enabled: boolean)
    local humanoid = self:GetHumanoid()
    if humanoid then
        humanoid.JumpPower = enabled and 50 or 0
        humanoid.JumpHeight = enabled and 7.2 or 0
    end
end

function BoothController:FindStatusLabel()
    local screenGui = self:GetScreenGui()
    if not screenGui then return nil end
    
    for _, desc in ipairs(screenGui:GetDescendants()) do
        if desc.Name == "Status" and desc:IsA("TextLabel") then
            return desc
        end
    end
    return nil
end

function BoothController:HideStatusLabel()
    local status = self:FindStatusLabel()
    if status then
        status.Visible = false
        status.Text = ""
    end
end

function BoothController:ShowStartCountdown(seconds)
    seconds = seconds or 5
    self._countdownCancel = false
    
    local statusLabel = self:FindStatusLabel()
    if not statusLabel then return end
    
    statusLabel.Visible = true
    statusLabel.Text = ""
    
    local initialText = string.format("Get ready to type in %d", seconds)
    for j = 1, #initialText do
        if self._countdownCancel then
            statusLabel.Visible = false
            return
        end
        statusLabel.Text = string.sub(initialText, 1, j)
        task.wait(0.03)
    end
    
    for i = seconds - 1, 1, -1 do
        if self._countdownCancel then
            statusLabel.Visible = false
            return
        end
        statusLabel.Text = string.format("Get ready to type in %d", i)
        task.wait(1)
    end
    
    statusLabel.Text = "Go!"
    task.wait(0.6)
    statusLabel.Visible = false
    self._countdownCancel = false
    
    self:SetJumpAbility(false)
end

function BoothController:UpdatePreviewColors(preview)
    if not preview then 
        warn("Preview is nil")
        return 
    end
    
    local displayCount = math.min(35, #self.currentWords)
    local newText = ""
    
    for i = 1, displayCount do
        local word = self.currentWords[i]
        if i < self.currentIndex then
            newText = newText .. '<font color="#00FF00">' .. word .. '</font>'
        else
            newText = newText .. word
        end
        
        if i < displayCount then
            newText = newText .. " "
        end
    end
    
    preview.Text = newText
    print("Updated preview, currentIndex:", self.currentIndex, "Text length:", #newText)
end

function BoothController:ShakeTextBox(textBox)
    local TweenService = game:GetService("TweenService")
    local originalPos = textBox.Position
    
    local shakeInfo = TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 0, true)
    local shake = TweenService:Create(textBox, shakeInfo, {Position = originalPos + UDim2.new(0, 10, 0, 0)})
    shake:Play()
    shake.Completed:Connect(function()
        textBox.Position = originalPos
    end)
end

function BoothController:CalculateWPM(): number
    local elapsedMinutes = (tick() - self.startTime) / 60
    if elapsedMinutes <= 0 then
        return 0
    end
    
    local timeSinceLastType = tick() - self.lastTypeTime
    local decayFactor = 1
    
    if timeSinceLastType > 1 then
        decayFactor = math.max(0.5, 1 - (timeSinceLastType - 1) * 0.1)
    end
    
    local wordsTyped = self.correctWordCount
    local baseWPM = wordsTyped / elapsedMinutes
    
    return math.floor(baseWPM * decayFactor)
end

function BoothController:StartWPMUpdater(typingGui)
    if self.wpmUpdateLoop then
        task.cancel(self.wpmUpdateLoop)
    end
    
    self.wpmUpdateLoop = task.spawn(function()
        while true do
            local wpmLabel = typingGui:FindFirstChild("WPM")
            if wpmLabel then
                local wpm = self:CalculateWPM()
                wpmLabel.Text = "WPM: " .. wpm
            end
            task.wait(0.1)
        end
    end)
end

function BoothController:StopWPMUpdater()
    if self.wpmUpdateLoop then
        task.cancel(self.wpmUpdateLoop)
        self.wpmUpdateLoop = nil
    end
end

function BoothController:SetupTypingInput(typingGui, preview)
    local textBox = typingGui:FindFirstChild("TextBox")
    if not textBox or not textBox:IsA("TextBox") then return end
    
    if self.typingConnection then
        self.typingConnection:Disconnect()
    end
    
    local lastTextLength = 0
    
    self.typingConnection = textBox:GetPropertyChangedSignal("Text"):Connect(function()
        local text = textBox.Text
        local currentLength = #text
        
        if currentLength > lastTextLength then
            self.totalCharactersTyped = self.totalCharactersTyped + (currentLength - lastTextLength)
            self.lastTypeTime = tick()
            
            local soundService = game:GetService("SoundService")
            local soundsFolder = soundService:FindFirstChild("Sounds")
            if soundsFolder then
                local typeSound = soundsFolder:FindFirstChild("Type")
                if typeSound and typeSound:IsA("Sound") then
                    typeSound:Play()
                end
            end
        end
        
        if self.currentIndex <= #self.currentWords then
            local expectedWord = self.currentWords[self.currentIndex]
            local isCorrectSoFar = string.sub(expectedWord, 1, #text) == text
            
            if isCorrectSoFar then
                textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
            else
                textBox.TextColor3 = Color3.fromRGB(255, 0, 0)
            end
            
            if text == expectedWord then
                if self.currentIndex == #self.currentWords then
                    self.currentIndex = self.currentIndex + 1
                    self.correctWordCount = self.correctWordCount + 1
                    textBox.Text = ""
                    textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
                    lastTextLength = 0
                    self:UpdatePreviewColors(preview)
                    self.BoothService.PlayerWon:Fire()
                    return
                end
            end
        end
        
        lastTextLength = currentLength
        
        if string.sub(text, -1) == " " then
            local typedWord = string.sub(text, 1, -2)
            
            if self.currentIndex <= #self.currentWords then
                local expectedWord = self.currentWords[self.currentIndex]
                
                if typedWord == expectedWord then
                    self.currentIndex = self.currentIndex + 1
                    self.correctWordCount = self.correctWordCount + 1
                    textBox.Text = ""
                    textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
                    lastTextLength = 0
                    self:UpdatePreviewColors(preview)
                    
                    print("Word completed! Index:", self.currentIndex, "Total words:", #self.currentWords)
                    
                    if self.currentIndex > #self.currentWords then
                        print("YOU WON! Firing PlayerWon signal")
                        self.BoothService.PlayerWon:Fire()
                        return
                    end
                else
                    self.errorCount = self.errorCount + 1
                    self:ShakeTextBox(textBox)
                    textBox.Text = ""
                    textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
                    lastTextLength = 0
                    
                    print("Error count:", self.errorCount)
                    self.BoothService.PlayerLost:Fire()
                end
            end
        end
    end)
end

function BoothController:CreateTypingGame(words)
    if type(words) ~= "table" or #words == 0 then return end
    
    local screenGui = self:GetScreenGui()
    if not screenGui then return end
    
    local typingGui = screenGui:FindFirstChild("TypingGame")
    if not typingGui then return end
    
    local preview = typingGui:FindFirstChild("Preview")
    if not preview then return end
    
    self.currentWords = words
    self.currentIndex = 1
    self.errorCount = 0
    self.correctWordCount = 0
    self.totalCharactersTyped = 0
    self.startTime = tick()
    self.lastTypeTime = tick()
    
    preview.RichText = true
    print("Preview RichText enabled:", preview.RichText)
    self:UpdatePreviewColors(preview)
    
    local wpmLabel = typingGui:FindFirstChild("WPM")
    if wpmLabel then
        wpmLabel.Text = "WPM: 0"
    end
    
    typingGui.Visible = true
    self:SetupTypingInput(typingGui, preview)
    self:StartWPMUpdater(typingGui)
    
    local textBox = typingGui:FindFirstChild("TextBox")
    if textBox then
        textBox.Text = ""
        task.wait(0.1)
        textBox:CaptureFocus()
    end
end

function BoothController:ShowGameResult(didWin: boolean, winnerName: string)
    local statusLabel = self:FindStatusLabel()
    if not statusLabel then return end
    
    statusLabel.Visible = true
    if didWin then
        statusLabel.Text = "You Won!"
        statusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    else
        statusLabel.Text = winnerName .. " Won!"
        statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
    end
    
    task.wait(3)
    statusLabel.Visible = false
    statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    
    self:SetJumpAbility(true)
    self:StopWPMUpdater()
    
    local screenGui = self:GetScreenGui()
    if screenGui then
        local typingGui = screenGui:FindFirstChild("TypingGame")
        if typingGui then
            typingGui.Visible = false
        end
    end
end

function BoothController:KnitStart()
    if self.BoothService.UpdateCamera then
        self.BoothService.UpdateCamera:Connect(function(boothModel)
            self:UpdateCamera(boothModel)
        end)
    end
    
    if self.BoothService.RevertCamera then
        self.BoothService.RevertCamera:Connect(function()
            self._countdownCancel = true
            self:HideStatusLabel()
            self:RevertCamera()
            self:SetJumpAbility(true)
            
            if self.typingConnection then
                self.typingConnection:Disconnect()
                self.typingConnection = nil
            end
            self:StopWPMUpdater()
            self.currentWords = {}
            self.currentIndex = 1
            self.errorCount = 0
            self.correctWordCount = 0
            self.totalCharactersTyped = 0
            self.startTime = 0
            self.lastTypeTime = 0
        end)
    end
    
    if self.BoothService.StartGame then
        self.BoothService.StartGame:Connect(function(boothModel, words)
            task.wait(5.5)
            self:CreateTypingGame(words)
        end)
    end
    
    if self.BoothService.BeginCountdown then
        self.BoothService.BeginCountdown:Connect(function(seconds)
            self:ShowStartCountdown(seconds)
        end)
    end
    
    if self.BoothService.ShowGameResult then
        self.BoothService.ShowGameResult:Connect(function(didWin, winnerName)
            self:ShowGameResult(didWin, winnerName)
        end)
    end
end

function BoothController:KnitInit()
    self.BoothService = Knit.GetService("BoothService")
end

return BoothController