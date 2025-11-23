local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local StarterPlayer = game:GetService("StarterPlayer")

local HoverSound = SoundService.Sounds:WaitForChild("Hover")
local ClickSound = SoundService.Sounds:WaitForChild("Click")

local Packages = ReplicatedStorage.Packages
local Shared = ReplicatedStorage.Shared

local Knit = require(Packages.Knit)

local player = Players.LocalPlayer
local playerGUI = player:WaitForChild("PlayerGui")
local screenGui = playerGUI:WaitForChild("ScreenGui")
local leftContainer = screenGui:WaitForChild("LeftContainer")
local frames : Folder = screenGui:WaitForChild("Frames")

local startScale = 1
local hoverScale = 1.1
local clickedScale = 0.95
local hoverTweenTime = 0.15
local clickTweenTime = 0.1

local ButtonController = Knit.CreateController({
    Name = "ButtonController",
})

local buttonTweens = {}
local buttonHoverStates = {} 
local frameTweens = {}
local isTransitioning = false
local buttonClickDebounce = {}
local buttonConnections = {}

function ButtonController:CleanupFrameTweens()
    for frame, tween in pairs(frameTweens) do
        if tween then
            tween:Cancel()
        end
    end
    for frame, _ in pairs(frameTweens) do
        frameTweens[frame] = nil
    end
end

function ButtonController:CleanupButtonConnections()
    for button, connections in pairs(buttonConnections) do
        for _, connection in pairs(connections) do
            if connection then
                connection:Disconnect()
            end
        end
    end
    buttonConnections = {}
end

function ButtonController:TweenElement(element : GuiObject, targetScale : number, duration : number?, easingStyle : Enum.EasingStyle?, easingDirection : Enum.EasingDirection?, doWait : boolean?)
    duration = duration or hoverTweenTime
    easingStyle = easingStyle or Enum.EasingStyle.Quad
    easingDirection = easingDirection or Enum.EasingDirection.Out

    if buttonTweens[element] then
        buttonTweens[element]:Cancel()
    end
    
    local uiScale = element:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", element)
    
    local tweenInfo = TweenInfo.new(duration, easingStyle, easingDirection)
    local tween = TweenService:Create(uiScale, tweenInfo, {Scale = targetScale})

    buttonTweens[element] = tween

    tween.Completed:Connect(function()
        if buttonTweens[element] == tween then
            buttonTweens[element] = nil
        end
    end)
    
    tween:Play()
    HoverSound:Play()

    if doWait then
        tween.Completed:Wait()
    end
    return tween
end

local currentFrame : Frame

local isDebounce = false

local function hideFrame(frame)
    if frameTweens[frame] then
        frameTweens[frame]:Cancel()
        frameTweens[frame] = nil
    end
    
    local uiScale = frame:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", frame)
    
    if not frame.Visible and uiScale.Scale <= 0 then
        return nil
    end
    
    frame.Visible = true
    
    if uiScale.Scale <= 0 then
        uiScale.Scale = 1
    end
    
    local tweenInfo = TweenInfo.new(hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    local tween = TweenService:Create(uiScale, tweenInfo, {Scale = 0})
    
    frameTweens[frame] = tween
    
    tween.Completed:Connect(function()
        frame.Visible = false
        if frameTweens[frame] == tween then
            frameTweens[frame] = nil
        end
    end)
    
    tween:Play()
    return tween
end

local function showFrame(frame)
    if frameTweens[frame] then
        frameTweens[frame]:Cancel()
        frameTweens[frame] = nil
    end
    
    local uiScale = frame:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", frame)
    uiScale.Scale = 0
    frame.Visible = true
    
    local tweenInfo = TweenInfo.new(hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(uiScale, tweenInfo, {Scale = 1})
    
    frameTweens[frame] = tween
    
    tween.Completed:Connect(function()
        if frameTweens[frame] == tween then
            frameTweens[frame] = nil
        end
    end)
    
    tween:Play()
    return true
end


function ButtonController.onFrameInvisible()
    local SelectedFrame = currentFrame
    
    if SelectedFrame then
        isTransitioning = true
        local hideTween = hideFrame(SelectedFrame)
        
        if hideTween then
            hideTween.Completed:Connect(function()
                isTransitioning = false
            end)
        else
            isTransitioning = false
        end
        
        previousFrame = currentFrame
        currentFrame = nil
    end
end

function ButtonController.onFrameVisible(SelectedFrame : Frame)
    if currentFrame == SelectedFrame then
        return
    end
    
    if isTransitioning then
        return
    end

    local targetFrame = SelectedFrame
    isTransitioning = true
    
    if currentFrame then
        local frameToHide = currentFrame
        previousFrame = currentFrame
        currentFrame = nil
        
        local hideTween = hideFrame(frameToHide)
        
        if hideTween then
            hideTween.Completed:Wait()
        end
        
        currentFrame = targetFrame
        showFrame(currentFrame)
        isTransitioning = false
    else
        currentFrame = targetFrame
        showFrame(currentFrame)
        isTransitioning = false
    end
    
    if frames then
        for _, frame in pairs(frames:GetChildren()) do
            if frame:IsA("Frame") and frame ~= targetFrame and frame ~= currentFrame and frame.Visible then
                hideFrame(frame)
            end
        end
    end
end

function ButtonController:ClickedButtonTween(button : GuiButton)
    if buttonClickDebounce[button] then
        return
    end
    
    buttonClickDebounce[button] = true
    task.delay(0.3, function()
        buttonClickDebounce[button] = false
    end)
    
	ClickSound:Play()
    
    if not frames then
        return
    end
    
    local SelectedFrame = frames:FindFirstChild(button.Name)
    
    if not SelectedFrame then
        return
    end

    local isCurrentlyActive = (currentFrame == SelectedFrame)

    if not isCurrentlyActive then
        self.onFrameVisible(SelectedFrame)
    else
        self.onFrameInvisible()
    end
end

function ButtonController:PressButton(button : GuiButton | ImageButton)
	if buttonTweens[button] then
        buttonTweens[button]:Cancel()
    end
    
    local uiScale = button:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", button)
    
    local clickDownTween = TweenService:Create(
        uiScale, 
        TweenInfo.new(clickTweenTime * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), 
        {Scale = clickedScale}
    )
    
    buttonTweens[button] = clickDownTween
    clickDownTween:Play()
end

function ButtonController:ReleaseButton(button : GuiButton | ImageButton)
	if buttonTweens[button] then
        buttonTweens[button]:Cancel()
    end
    
    local uiScale = button:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", button)
    local targetScale = buttonHoverStates[button] and hoverScale or startScale
    
    local clickUpTween = TweenService:Create(
        uiScale, 
        TweenInfo.new(clickTweenTime * 1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), 
        {Scale = targetScale}
    )
    
    buttonTweens[button] = clickUpTween
    clickUpTween:Play()

    clickUpTween.Completed:Connect(function()
        if buttonTweens[button] == clickUpTween then
            buttonTweens[button] = nil
        end
    end)
end

function ButtonController:SetupButtons(uiScreen: Instance) : any
    for _, descendant in ipairs(uiScreen:GetDescendants()) do
        if descendant:IsA("GuiButton") then
            descendant.Active = true
            local uiScale = descendant:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", descendant)
            uiScale.Scale = 1

            local scaleHover = 1.2
            local scalePressed = 1 / 1.2
            local originalScale = 1

            descendant.MouseEnter:Connect(function()
                buttonHoverStates[descendant] = true
                if not buttonTweens[descendant] then
                    self:TweenElement(descendant, scaleHover, hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                end
            end)

            descendant.MouseLeave:Connect(function()
                buttonHoverStates[descendant] = false
                if buttonTweens[descendant] then
                    buttonTweens[descendant]:Cancel()
                    buttonTweens[descendant] = nil
                end
                self:TweenElement(descendant, originalScale, hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            end)

            descendant.MouseButton1Up:Connect(function()
                local targetScale = buttonHoverStates[descendant] and scaleHover or originalScale
                self:TweenElement(descendant, targetScale, hoverTweenTime)
            end)

            descendant.MouseButton1Down:Connect(function()
                self:TweenElement(descendant, scalePressed, hoverTweenTime)
            end)

            descendant.Activated:Connect(function()
                ClickSound:Play()
            end)
        end
    end
end

function ButtonController:KnitStart()
    local setupButtons = {}
    
    for _, descendant in ipairs(playerGUI:GetDescendants()) do
        if CollectionService:HasTag(descendant, "Tween") then
            if descendant:IsA("GuiButton") or descendant:IsA("ImageButton") then
                if setupButtons[descendant] then
                    continue
                end
                
                setupButtons[descendant] = true
                
                local uiScale = descendant:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", descendant)
                uiScale.Scale = 1

                buttonConnections[descendant] = {}
                
                buttonConnections[descendant].MouseEnter = descendant.MouseEnter:Connect(function()
                    buttonHoverStates[descendant] = true

                    if not buttonTweens[descendant] then
                        self:TweenElement(descendant, hoverScale, hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                    end
                end)

                buttonConnections[descendant].MouseLeave = descendant.MouseLeave:Connect(function()
                    buttonHoverStates[descendant] = false

                    if buttonTweens[descendant] then
                        buttonTweens[descendant]:Cancel()
                        buttonTweens[descendant] = nil
                    end
                    
                    self:TweenElement(descendant, startScale, hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                end)

                buttonConnections[descendant].MouseButton1Down = descendant.MouseButton1Down:Connect(function()
                    self:PressButton(descendant)
                end)
                
                buttonConnections[descendant].MouseButton1Up = descendant.MouseButton1Up:Connect(function()
                    self:ReleaseButton(descendant)
                end)
                
                buttonConnections[descendant].MouseButton1Click = descendant.MouseButton1Click:Connect(function()
                    self:ClickedButtonTween(descendant)
                end)
            end
        end
    end
    
    for _, button in ipairs(leftContainer:GetChildren()) do
        if button:IsA("GuiButton") or button:IsA("ImageButton") then
            if setupButtons[button] then
                continue
            end
            
            setupButtons[button] = true
            
            buttonConnections[button] = {}
            
            buttonConnections[button].MouseEnter = button.MouseEnter:Connect(function()
                buttonHoverStates[button] = true

                if not buttonTweens[button] then
                    self:TweenElement(button, hoverScale, hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                end
            end)

            buttonConnections[button].MouseLeave = button.MouseLeave:Connect(function()
                buttonHoverStates[button] = false

                if buttonTweens[button] then
                    buttonTweens[button]:Cancel()
                    buttonTweens[button] = nil
                end
                
                self:TweenElement(button, startScale, hoverTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            end)

            buttonConnections[button].MouseButton1Down = button.MouseButton1Down:Connect(function()
                self:PressButton(button)
            end)
            
            buttonConnections[button].MouseButton1Up = button.MouseButton1Up:Connect(function()
                self:ReleaseButton(button)
            end)
            
            buttonConnections[button].MouseButton1Click = button.MouseButton1Click:Connect(function()
                self:ClickedButtonTween(button)
            end)
        end
    end
end

function ButtonController:KnitInit()
    self:CleanupFrameTweens()
    self:CleanupButtonConnections()
    isTransitioning = false
    currentFrame = nil
end

return ButtonController