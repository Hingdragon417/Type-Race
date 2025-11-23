local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local BoothController = Knit.CreateController({
    Name = "BoothController",
    currentWords = {},
    currentIndex = 1,
    typingConnection = nil,
    errorCount = 0,
    gameActive = false,
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

function BoothController:ShowFeedback(isCorrect: boolean)
    local statusLabel = self:FindStatusLabel()
    if not statusLabel then return end
    
    statusLabel.Visible = true
    statusLabel.Text = isCorrect and "Correct" or "Incorrect"
    statusLabel.TextColor3 = isCorrect and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
    
    local SoundService = game:GetService("SoundService")
    local soundsFolder = SoundService:FindFirstChild("Sounds")
    if soundsFolder then
        local soundName = isCorrect and "Correct" or "Incorrect"
        local sound = soundsFolder:FindFirstChild(soundName)
        if sound and sound:IsA("Sound") then
            sound:Play()
        end
    end
    
    task.delay(0.5, function()
        statusLabel.Visible = false
        statusLabel.TextColor3 = Color3.fromRGB(255, 251, 0)
    end)
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
end

function BoothController:UpdateOpponentProgress(opponentUserId, progress)
    local screenGui = self:GetScreenGui()
    if not screenGui then return end
    
    local typingGui = screenGui:FindFirstChild("TypingGame")
    if not typingGui or not typingGui.Visible then return end
    
    local bar = typingGui:WaitForChild("Bar")
    if not bar then return end
    
    local playerTemplate = bar:FindFirstChild("PlayerTemplate")
    if not playerTemplate or not playerTemplate:IsA("ImageLabel") then return end
    
    playerTemplate.Image = "rbxthumb://type=AvatarHeadShot&id=" .. opponentUserId .. "&w=150&h=150"
    
    local barSize = bar.AbsoluteSize.X
    local targetX = progress * barSize
    
    local TweenService = game:GetService("TweenService")
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(playerTemplate, tweenInfo, {
        Position = UDim2.new(0, targetX, playerTemplate.Position.Y.Scale, playerTemplate.Position.Y.Offset)
    })
    tween:Play()
end

function BoothController:UpdateProgressBar(typingGui)
    if not typingGui then return end
    
    local bar = typingGui:FindFirstChild("Bar")
    if not bar then return end
    
    local fill = bar:FindFirstChild("Fill")
    if not fill then return end
    
    local progress = (self.currentIndex - 1) / #self.currentWords
    progress = math.clamp(progress, 0, 1)
    
    local TweenService = game:GetService("TweenService")
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(fill, tweenInfo, {Size = UDim2.new(progress, 0, 1, 0)})
    tween:Play()
end

function BoothController:UpdatePreviewColors(preview, currentTyping)
    if not preview then 
        warn("Preview is nil")
        return 
    end
    
    currentTyping = currentTyping or ""
    local displayCount = math.min(35, #self.currentWords)
    local newText = ""
    
    for i = 1, displayCount do
        local word = self.currentWords[i]
        
        if i < self.currentIndex then
            newText = newText .. '<font color="#00FF00">' .. word .. '</font>'
        elseif i == self.currentIndex and #currentTyping > 0 then
            local matchLength = 0
            for j = 1, math.min(#currentTyping, #word) do
                if string.sub(currentTyping, j, j) == string.sub(word, j, j) then
                    matchLength = j
                else
                    break
                end
            end
            
            if matchLength > 0 then
                local yellowChars = string.sub(word, 1, matchLength)
                local remainingChars = string.sub(word, matchLength + 1)
                newText = newText .. '<font color="rgb(255,255,0)">' .. yellowChars .. '</font>' .. remainingChars
            else
                newText = newText .. word
            end
        else
            newText = newText .. word
        end
        
        if i < displayCount then
            newText = newText .. " "
        end
    end
    
    preview.Text = newText
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

function BoothController:SetupTypingInput(typingGui, preview)
    local textBox = typingGui:FindFirstChild("TextBox")
    if not textBox or not textBox:IsA("TextBox") then return end
    
    if self.typingConnection then
        self.typingConnection:Disconnect()
    end
    
    local lastTextLength = 0
    local lastValidationTime = 0
    local VALIDATION_COOLDOWN = 0.05
    
    self.typingConnection = textBox:GetPropertyChangedSignal("Text"):Connect(function()
        if not self.gameActive then
            return
        end
        
        local currentTime = tick()
        if currentTime - lastValidationTime < VALIDATION_COOLDOWN then
            return
        end
        
        local text = textBox.Text
        
        if self.currentIndex <= #self.currentWords then
            local expectedWord = self.currentWords[self.currentIndex]
            local isCorrectSoFar = string.sub(expectedWord, 1, #text) == text
            
            if isCorrectSoFar then
                textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
            else
                textBox.TextColor3 = Color3.fromRGB(255, 0, 0)
            end
            
            self:UpdatePreviewColors(preview, text)
            
            if text == expectedWord then
                if self.currentIndex == #self.currentWords then
                    lastValidationTime = currentTime
                    self.BoothService.ValidateWordCompletion:Fire(self.currentIndex, expectedWord)
                    
                    self.currentIndex = self.currentIndex + 1
                    textBox.Text = ""
                    textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
                    lastTextLength = 0
                    self:UpdatePreviewColors(preview, "")
                    self:UpdateProgressBar(typingGui)
                    
                    self.gameActive = false
                    local screenGui = self:GetScreenGui()
                    if screenGui then
                        local typingGui = screenGui:FindFirstChild("TypingGame")
                        if typingGui then
                            typingGui.Visible = false
                        end
                    end
                    
                    self.BoothService.PlayerWon:Fire()
                    return
                end
            end
        end
        
        lastTextLength = #text
        
        if string.sub(text, -1) == " " then
            local typedWord = string.sub(text, 1, -2)
            
            if self.currentIndex <= #self.currentWords then
                local expectedWord = self.currentWords[self.currentIndex]
                
                if typedWord == expectedWord then
                    lastValidationTime = currentTime
                    self.BoothService.ValidateWordCompletion:Fire(self.currentIndex, expectedWord)
                    
                    self.currentIndex = self.currentIndex + 1
                    textBox.Text = ""
                    textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
                    lastTextLength = 0
                    self:UpdatePreviewColors(preview, "")
                    self:UpdateProgressBar(typingGui)
                    self:ShowFeedback(true)
                    
                    if self.currentIndex > #self.currentWords then
                        self.gameActive = false
                        local screenGui = self:GetScreenGui()
                        if screenGui then
                            local typingGui = screenGui:FindFirstChild("TypingGame")
                            if typingGui then
                                typingGui.Visible = false
                            end
                        end
                        
                        self.BoothService.PlayerWon:Fire()
                        return
                    end
                else
                    self.errorCount = self.errorCount + 1
                    self:ShakeTextBox(textBox)
                    self:ShowFeedback(false)
                    textBox.Text = ""
                    textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
                    lastTextLength = 0
                    
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
    self.gameActive = true
    
    preview.RichText = true
    self:UpdatePreviewColors(preview, "")
    self:UpdateProgressBar(typingGui)
    
    typingGui.Visible = true
    self:SetupTypingInput(typingGui, preview)
    
    local textBox = typingGui:FindFirstChild("TextBox")
    if textBox then
        textBox.Text = ""
        task.wait(0.1)
        textBox:CaptureFocus()
    end
end

function BoothController:ShowGameResult(didWin: boolean, winnerName: string)
    self.gameActive = false
    
    local screenGui = self:GetScreenGui()
    if screenGui then
        local typingGui = screenGui:FindFirstChild("TypingGame")
        if typingGui then
            typingGui.Visible = false
            
            local bar = typingGui:FindFirstChild("Bar")
            if bar then
                local fill = bar:FindFirstChild("Fill")
                if fill then
                    fill.Size = UDim2.new(0, 0, 1, 0)
                end
                
                local playerTemplate = bar:FindFirstChild("PlayerTemplate")
                if playerTemplate and playerTemplate:IsA("ImageLabel") then
                    playerTemplate.Image = ""
                    playerTemplate.Position = UDim2.new(0, 0, playerTemplate.Position.Y.Scale, playerTemplate.Position.Y.Offset)
                end
            end
        end
    end
    
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
            
            self.currentWords = {}
            self.currentIndex = 1
            self.errorCount = 0
            self.gameActive = false
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
    
    if self.BoothService.UpdateWPM then
        self.BoothService.UpdateWPM:Connect(function(wpm)
            local screenGui = self:GetScreenGui()
            if not screenGui then return end
            
            local typingGui = screenGui:FindFirstChild("TypingGame")
            if not typingGui then return end
            
            local wpmLabel = typingGui:FindFirstChild("WPM")
            if wpmLabel and wpmLabel:IsA("TextLabel") then
                wpmLabel.Text = "WPM: " .. tostring(math.floor(wpm))
            end
        end)
    end
    
    if self.BoothService.UpdateOpponentProgress then
        self.BoothService.UpdateOpponentProgress:Connect(function(opponentUserId, progress)
            self:UpdateOpponentProgress(opponentUserId, progress)
        end)
    end
end

function BoothController:KnitInit()
    self.BoothService = Knit.GetService("BoothService")
end

return BoothController