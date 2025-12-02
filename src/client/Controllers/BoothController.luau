
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)


local VALIDATION_COOLDOWN = 0.05
local COUNTDOWN_CHAR_DELAY = 0.03
local FEEDBACK_DISPLAY_TIME = 0.5
local RESULT_DISPLAY_TIME = 3
local TWEEN_DURATION = 0.3
local SHAKE_DURATION = 0.05
local MAX_DISPLAY_WORDS = 35
local DEFAULT_JUMP_POWER = 50
local DEFAULT_JUMP_HEIGHT = 7.2

local COLOR_WHITE = Color3.fromRGB(255, 255, 255)
local COLOR_GREEN = Color3.fromRGB(0, 255, 0)
local COLOR_RED = Color3.fromRGB(255, 0, 0)
local COLOR_YELLOW = Color3.fromRGB(255, 251, 0)

local BoothController = Knit.CreateController({
	Name = "BoothController",
	currentWords = {} :: {string},
	currentIndex = 1 :: number,
	typingConnection = nil :: RBXScriptConnection?,
	errorCount = 0 :: number,
	gameActive = false :: boolean,
	currentBooth = nil :: Model?,
	hiddenBillboards = {} :: {BillboardGui},
	_countdownCancel = false :: boolean,
	_playSoloButtonConnection = nil :: RBXScriptConnection?,
	

	_player = nil :: Player?,
	_playerGui = nil :: PlayerGui?,
	_screenGui = nil :: ScreenGui?,
	_camera = nil :: Camera?,
})


local function isDescendantOf(instance: Instance, ancestor: Instance): boolean
	local parent = instance.Parent
	while parent do
		if parent == ancestor then
			return true
		end
		parent = parent.Parent
	end
	return false
end


local function createTween(
	instance: Instance,
	duration: number,
	easingStyle: Enum.EasingStyle,
	easingDirection: Enum.EasingDirection,
	goalProperties: {[string]: any},
	repeatCount: number?,
	reverses: boolean?
): Tween
	local tweenInfo = TweenInfo.new(
		duration,
		easingStyle,
		easingDirection,
		repeatCount or 0,
		reverses or false
	)
	local tween = TweenService:Create(instance, tweenInfo, goalProperties)
	tween:Play()
	return tween
end

function BoothController:_getCachedPlayer(): Player
	if not self._player then
		self._player = Players.LocalPlayer
	end
	return self._player
end

function BoothController:_getCachedPlayerGui(): PlayerGui?
	if not self._playerGui then
		local player = self:_getCachedPlayer()
		self._playerGui = player:FindFirstChild("PlayerGui") :: PlayerGui?
	end
	return self._playerGui
end

function BoothController:_getCachedScreenGui(): ScreenGui?
	if not self._screenGui or not self._screenGui.Parent then
		local playerGui = self:_getCachedPlayerGui()
		if not playerGui then return nil end
		
		self._screenGui = playerGui:FindFirstChild("ScreenGui") :: ScreenGui?
		if not self._screenGui then
			for _, child in playerGui:GetChildren() do
				if child:IsA("ScreenGui") then
					self._screenGui = child :: ScreenGui
					break
				end
			end
		end
	end
	return self._screenGui
end

function BoothController:_getCachedCamera(): Camera
	if not self._camera then
		self._camera = workspace.CurrentCamera
	end
	return self._camera
end

function BoothController:HideOtherBoothBillboards(currentBoothModel: Model)

	for _, billboard in self.hiddenBillboards do
		if billboard.Parent then
			billboard.Enabled = true
		end
	end
	table.clear(self.hiddenBillboards)
	

	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("BillboardGui") and descendant.Enabled then
			if not isDescendantOf(descendant, currentBoothModel) then
				descendant.Enabled = false
				table.insert(self.hiddenBillboards, descendant)
			end
		end
	end
end

function BoothController:ShowAllBillboards()
	for _, billboard in self.hiddenBillboards do
		if billboard.Parent then
			billboard.Enabled = true
		end
	end
	table.clear(self.hiddenBillboards)
end

function BoothController:UpdateCamera(boothModel: Model)
	self.currentBooth = boothModel
	self:HideOtherBoothBillboards(boothModel)
	
	local camera = self:_getCachedCamera()
	local camPart = boothModel:FindFirstChild("Camera")
	if camPart then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camPart.CFrame
	end
end

function BoothController:RevertCamera()
	self.currentBooth = nil
	self:ShowAllBillboards()
	self:_getCachedCamera().CameraType = Enum.CameraType.Custom
end

function BoothController:SetJumpAbility(enabled: boolean)
	local player = self:_getCachedPlayer()
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpPower = enabled and DEFAULT_JUMP_POWER or 0
		humanoid.JumpHeight = enabled and DEFAULT_JUMP_HEIGHT or 0
	end
end

function BoothController:ShowPlaySoloButton()
	local screenGui = self:_getCachedScreenGui()
	if not screenGui then return end
	
	local playSoloButton = screenGui:FindFirstChild("PlaySolo") :: TextButton?
	if playSoloButton then
		playSoloButton.Visible = true
		
		-- Connect button click if not already connected
		if self._playSoloButtonConnection then
			self._playSoloButtonConnection:Disconnect()
			self._playSoloButtonConnection = nil
		end
		
		self._playSoloButtonConnection = playSoloButton.MouseButton1Click:Connect(function()
			self:HidePlaySoloButton()
			self.BoothService.PlaySolo:Fire()
		end)
	end
end

function BoothController:HidePlaySoloButton()
	local screenGui = self:_getCachedScreenGui()
	if not screenGui then return end
	
	local playSoloButton = screenGui:FindFirstChild("PlaySolo") :: TextButton?
	if playSoloButton then
		playSoloButton.Visible = false
	end
	
	if self._playSoloButtonConnection then
		self._playSoloButtonConnection:Disconnect()
		self._playSoloButtonConnection = nil
	end
end

function BoothController:UpdateBoothPlayerCount(playerCount: number)
	if playerCount == 1 then
		self:ShowPlaySoloButton()
	else
		self:HidePlaySoloButton()
	end
end

function BoothController:_findStatusLabel(): TextLabel?
	local screenGui = self:_getCachedScreenGui()
	if not screenGui then return nil end
	
	return screenGui:FindFirstChild("Status", true) :: TextLabel?
end

function BoothController:HideStatusLabel()
	local status = self:_findStatusLabel()
	if status then
		status.Visible = false
		status.Text = ""
	end
end

function BoothController:ShowFeedback(isCorrect: boolean)
	local statusLabel = self:_findStatusLabel()
	if not statusLabel then return end
	
	statusLabel.Visible = true
	statusLabel.Text = isCorrect and "Correct" or "Incorrect"
	statusLabel.TextColor3 = isCorrect and COLOR_GREEN or COLOR_RED
	

	local soundsFolder = SoundService:FindFirstChild("Sounds")
	if soundsFolder then
		local sound = soundsFolder:FindFirstChild(isCorrect and "Correct" or "Incorrect") :: Sound?
		if sound then
			sound:Play()
		end
	end
	
	task.delay(FEEDBACK_DISPLAY_TIME, function()
		if statusLabel.Parent then
			statusLabel.Visible = false
			statusLabel.TextColor3 = COLOR_YELLOW
		end
	end)
end

function BoothController:ShowStartCountdown(seconds: number?)
	seconds = seconds or 5
	self._countdownCancel = false
	
	local statusLabel = self:_findStatusLabel()
	if not statusLabel then return end
	
	statusLabel.Visible = true
	statusLabel.Text = ""
	

	local initialText = `Get ready to type in {seconds}`
	for j = 1, #initialText do
		if self._countdownCancel then
			statusLabel.Visible = false
			return
		end
		statusLabel.Text = string.sub(initialText, 1, j)
		task.wait(COUNTDOWN_CHAR_DELAY)
	end
	

	for i = seconds - 1, 1, -1 do
		if self._countdownCancel then
			statusLabel.Visible = false
			return
		end
		statusLabel.Text = `Get ready to type in {i}`
		task.wait(1)
	end
	
	statusLabel.Text = "Go!"
	task.wait(0.6)
	statusLabel.Visible = false
	self._countdownCancel = false
end

function BoothController:UpdateOpponentProgress(opponentUserId: number, progress: number)
	local screenGui = self:_getCachedScreenGui()
	if not screenGui then return end
	
	local typingGui = screenGui:FindFirstChild("TypingGame")
	if not typingGui or not typingGui.Visible then return end
	
	local bar = typingGui:FindFirstChild("Bar")
	if not bar then return end
	
	local playerTemplate = bar:FindFirstChild("PlayerTemplate") :: ImageLabel?
	if not playerTemplate then return end
	
	playerTemplate.Image = `rbxthumb://type=AvatarHeadShot&id={opponentUserId}&w=150&h=150`
	
	local targetX = progress * bar.AbsoluteSize.X
	createTween(
		playerTemplate,
		TWEEN_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		{Position = UDim2.new(0, targetX, playerTemplate.Position.Y.Scale, playerTemplate.Position.Y.Offset)}
	)
end

function BoothController:UpdateProgressBar(typingGui: Frame)
	local bar = typingGui:FindFirstChild("Bar")
	if not bar then return end
	
	local fill = bar:FindFirstChild("Fill") :: Frame?
	if not fill then return end
	
	local progress = math.clamp((self.currentIndex - 1) / #self.currentWords, 0, 1)
	
	createTween(
		fill,
		TWEEN_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		{Size = UDim2.new(progress, 0, 1, 0)}
	)
end

function BoothController:UpdatePreviewColors(preview: TextLabel, currentTyping: string)
	if not preview then 
		warn("Preview is nil")
		return 
	end
	
	local displayCount = math.min(MAX_DISPLAY_WORDS, #self.currentWords)
	local textParts = table.create(displayCount * 2)
	local partIndex = 1
	
	for i = 1, displayCount do
		local word = self.currentWords[i]
		
		if i < self.currentIndex then

			textParts[partIndex] = `<font color="#00FF00">{word}</font>`
		elseif i == self.currentIndex and #currentTyping > 0 then

			local matchLength = 0
			local minLen = math.min(#currentTyping, #word)
			
			for j = 1, minLen do
				if string.sub(currentTyping, j, j) == string.sub(word, j, j) then
					matchLength = j
				else
					break
				end
			end
			
			if matchLength > 0 then
				local yellowChars = string.sub(word, 1, matchLength)
				local remainingChars = string.sub(word, matchLength + 1)
				textParts[partIndex] = `<font color="rgb(255,255,0)">{yellowChars}</font>{remainingChars}`
			else
				textParts[partIndex] = word
			end
		else

			textParts[partIndex] = word
		end
		
		partIndex += 1
		
		if i < displayCount then
			textParts[partIndex] = " "
			partIndex += 1
		end
	end
	
	preview.Text = table.concat(textParts)
end

function BoothController:_shakeTextBox(textBox: TextBox)
	local originalPos = textBox.Position
	
	local shake = createTween(
		textBox,
		SHAKE_DURATION,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.InOut,
		{Position = originalPos + UDim2.new(0, 10, 0, 0)},
		0,
		true
	)
	
	shake.Completed:Once(function()
		textBox.Position = originalPos
	end)
end

function BoothController:_handleWordCompletion(textBox: TextBox, typingGui: Frame, preview: TextLabel, expectedWord: string, currentTime: number): number
	self.BoothService.ValidateWordCompletion:Fire(self.currentIndex, expectedWord)
	
	self.currentIndex += 1
	textBox.Text = ""
	textBox.TextColor3 = COLOR_WHITE
	self:UpdatePreviewColors(preview, "")
	self:UpdateProgressBar(typingGui)
	
	if self.currentIndex > #self.currentWords then
		self.gameActive = false
		typingGui.Visible = false
		self.BoothService.PlayerWon:Fire()
	end
	
	return currentTime
end

function BoothController:SetupTypingInput(typingGui: Frame, preview: TextLabel)
	local textBox = typingGui:FindFirstChild("TextBox") :: TextBox?
	if not textBox then return end
	

	if self.typingConnection then
		self.typingConnection:Disconnect()
		self.typingConnection = nil
	end
	
	local lastValidationTime = 0
	
	self.typingConnection = textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if not self.gameActive then return end
		
		local currentTime = tick()
		if currentTime - lastValidationTime < VALIDATION_COOLDOWN then return end
		
		local text = textBox.Text
		if self.currentIndex > #self.currentWords then return end
		
		local expectedWord = self.currentWords[self.currentIndex]
		local isCorrectSoFar = string.sub(expectedWord, 1, #text) == text
		

		textBox.TextColor3 = isCorrectSoFar and COLOR_WHITE or COLOR_RED
		self:UpdatePreviewColors(preview, text)
		

		if text == expectedWord then

			if self.currentIndex == #self.currentWords then
				lastValidationTime = self:_handleWordCompletion(textBox, typingGui, preview, expectedWord, currentTime)
				return
			end
		elseif string.sub(text, -1) == " " then

			local typedWord = string.match(text, "^%s*(.-)%s*$")
			
			if typedWord == expectedWord then
				lastValidationTime = self:_handleWordCompletion(textBox, typingGui, preview, expectedWord, currentTime)
				self:ShowFeedback(true)
			else

				self.errorCount += 1
				self:_shakeTextBox(textBox)
				self:ShowFeedback(false)
				textBox.Text = ""
				textBox.TextColor3 = COLOR_WHITE
				
				local errorsLabel = typingGui:FindFirstChild("Errors") :: TextLabel?
				if errorsLabel then
					errorsLabel.Text = `Errors {self.errorCount}/5`
				end
				
				self.BoothService.PlayerLost:Fire()
			end
		end
	end)
end

function BoothController:CreateTypingGame(words: {string})
	if not words or #words == 0 then return end
	
	local screenGui = self:_getCachedScreenGui()
	if not screenGui then return end
	
	local typingGui = screenGui:FindFirstChild("TypingGame") :: Frame?
	if not typingGui then return end
	
	local preview = typingGui:FindFirstChild("Preview") :: TextLabel?
	if not preview then return end
	

	self.currentWords = words
	self.currentIndex = 1
	self.errorCount = 0
	self.gameActive = true
	

	local errorsLabel = typingGui:FindFirstChild("Errors") :: TextLabel?
	if errorsLabel then
		errorsLabel.Text = "Errors 0/5"
	end
	
	preview.RichText = true
	self:UpdatePreviewColors(preview, "")
	self:UpdateProgressBar(typingGui)
	
	typingGui.Visible = true
	self:SetupTypingInput(typingGui, preview)
	

	local textBox = typingGui:FindFirstChild("TextBox") :: TextBox?
	if textBox then
		textBox.Text = ""
		task.wait(0.1)
		textBox:CaptureFocus()
	end
end

function BoothController:ShowGameResult(didWin: boolean, winnerName: string)
	self.gameActive = false
	
	local screenGui = self:_getCachedScreenGui()
	if screenGui then
		local typingGui = screenGui:FindFirstChild("TypingGame")
		if typingGui then
			typingGui.Visible = false
			

			local bar = typingGui:FindFirstChild("Bar")
			if bar then
				local fill = bar:FindFirstChild("Fill") :: Frame?
				if fill then
					fill.Size = UDim2.new(0, 0, 1, 0)
				end
				
				local playerTemplate = bar:FindFirstChild("PlayerTemplate") :: ImageLabel?
				if playerTemplate then
					playerTemplate.Image = ""
					playerTemplate.Position = UDim2.new(0, 0, playerTemplate.Position.Y.Scale, playerTemplate.Position.Y.Offset)
				end
			end
		end
	end
	
	local statusLabel = self:_findStatusLabel()
	if not statusLabel then return end
	
	statusLabel.Visible = true
	statusLabel.Text = didWin and "You Won!" or `{winnerName} Won!`
	statusLabel.TextColor3 = didWin and COLOR_GREEN or COLOR_RED
	
	task.wait(RESULT_DISPLAY_TIME)
	statusLabel.Visible = false
	statusLabel.TextColor3 = COLOR_WHITE
	
	self:SetJumpAbility(true)
end

function BoothController:_cleanup()
	self._countdownCancel = true
	self:HideStatusLabel()
	self:HidePlaySoloButton()
	self:RevertCamera()
	self:SetJumpAbility(true)
	
	if self.typingConnection then
		self.typingConnection:Disconnect()
		self.typingConnection = nil
	end
	

	table.clear(self.currentWords)
	self.currentIndex = 1
	self.errorCount = 0
	self.gameActive = false
end

function BoothController:KnitStart()
	local service = self.BoothService
	
	if service.UpdateCamera then
		service.UpdateCamera:Connect(function(boothModel)
			self:UpdateCamera(boothModel)
		end)
	end
	
	if service.RevertCamera then
		service.RevertCamera:Connect(function()
			self:_cleanup()
		end)
	end
	
	if service.StartGame then
		service.StartGame:Connect(function(boothModel, words)
			task.wait(5.5)
			self:CreateTypingGame(words)
		end)
	end
	
	if service.BeginCountdown then
		service.BeginCountdown:Connect(function(seconds)
			self:HidePlaySoloButton()
			self:ShowStartCountdown(seconds)
		end)
	end
	
	if service.ShowGameResult then
		service.ShowGameResult:Connect(function(didWin, winnerName)
			self:ShowGameResult(didWin, winnerName)
		end)
	end
	
	if service.UpdateWPM then
		service.UpdateWPM:Connect(function(wpm)
			local screenGui = self:_getCachedScreenGui()
			if not screenGui then return end
			
			local typingGui = screenGui:FindFirstChild("TypingGame")
			if not typingGui then return end
			
			local wpmLabel = typingGui:FindFirstChild("WPM") :: TextLabel?
			if wpmLabel then
				wpmLabel.Text = `WPM: {math.floor(wpm)}`
			end
		end)
	end
	
	if service.UpdateOpponentProgress then
		service.UpdateOpponentProgress:Connect(function(opponentUserId, progress)
			self:UpdateOpponentProgress(opponentUserId, progress)
		end)
	end
	
	if service.UpdateBoothPlayerCount then
		service.UpdateBoothPlayerCount:Connect(function(playerCount)
			self:UpdateBoothPlayerCount(playerCount)
		end)
	end
end

function BoothController:KnitInit()
	self.BoothService = Knit.GetService("BoothService")
end

return BoothController