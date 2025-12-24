
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local DEBUG_ENABLED = true
local LOG_PREFIX = "[BoothController]"

local function Log(message: string, level: string?)
	if not DEBUG_ENABLED then return end
	
	level = level or "info"
	local output = LOG_PREFIX .. " " .. message
	
	if level == "warn" then
		warn(output)
	elseif level == "error" then
		warn(output .. " [ERROR]")
	else
		print(output)
	end
end

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
	_focusLostConnection = nil :: RBXScriptConnection?,
	errorCount = 0 :: number,
	gameActive = false :: boolean,
	currentBooth = nil :: Model?,
	hiddenBillboards = {} :: {BillboardGui},
	_countdownCancel = false :: boolean,
	_playSoloButtonConnection = nil :: RBXScriptConnection?,
	_votingConnections = {} :: {RBXScriptConnection},
	_votingContainer = nil :: Frame?,
	_hasVoted = false :: boolean,
	_currentVote = nil :: string?,

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
	Log("UpdateCamera - Setting camera for booth: " .. boothModel.Name)
	self.currentBooth = boothModel
	self:HideOtherBoothBillboards(boothModel)
	
	local camera = self:_getCachedCamera()
	local camPart = boothModel:FindFirstChild("Camera")
	if camPart then
		Log("Camera positioned to booth camera part")
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camPart.CFrame
	end
end

function BoothController:RevertCamera()
	Log("RevertCamera - Restoring default camera")
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
	Log("ShowPlaySoloButton - Displaying solo play button")
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
	Log("HidePlaySoloButton - Hiding solo play button")
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
	Log("UpdateBoothPlayerCount - Count: " .. tostring(playerCount))
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
	Log("ShowFeedback - Correct: " .. tostring(isCorrect))
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
	Log("ShowStartCountdown - Starting countdown")
	seconds = seconds or 5
	self._countdownCancel = false
	
	local statusLabel = self:_findStatusLabel()
	if not statusLabel then return end
	
	statusLabel.Visible = true
	statusLabel.Text = "Go!"
	task.wait(0.6)
	statusLabel.Visible = false
	self._countdownCancel = false
end

function BoothController:CleanupVotingUI()
	for _, conn in self._votingConnections do
		conn:Disconnect()
	end
	table.clear(self._votingConnections)
	
	local screenGui = self:_getCachedScreenGui()
	if screenGui then
		local voting = screenGui:FindFirstChild("Voting")
		if voting then
			voting.Visible = false
			local container = voting:FindFirstChild("Container")
			if container then
				for _, child in container:GetChildren() do
					if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") then
						child:Destroy()
					end
				end
			end
		end
	end
	
	self._votingContainer = nil
	self._hasVoted = false
	self._currentVote = nil
end

function BoothController:ShowVotingUI(difficulties: {string}, countdownSeconds: number)
	Log("ShowVotingUI - Difficulties: " .. table.concat(difficulties, ", ") .. " | Countdown: " .. tostring(countdownSeconds))
	self:CleanupVotingUI()
	self._hasVoted = false
	
	local screenGui = self:_getCachedScreenGui()
	if not screenGui then return end
	
	local voting = screenGui:FindFirstChild("Voting")
	if not voting then
		warn("Voting frame not found in ScreenGui")
		return
	end
	
	voting.Visible = true
	self._votingContainer = voting
	
	local container = voting:FindFirstChild("Container")
	if not container then
		warn("Container not found in Voting frame")
		return
	end
	
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local uiAssets = assets and assets:FindFirstChild("UIAssets")
	local votingTemplate = uiAssets and uiAssets:FindFirstChild("VotingTemplate")
	
	if not votingTemplate then
		warn("VotingTemplate not found in ReplicatedStorage.Assets.UIAssets")
		return
	end
	
	local countdownLabel = voting:FindFirstChild("Countdown") or voting:FindFirstChild("Timer")
	if countdownLabel and countdownLabel:IsA("TextLabel") then
		countdownLabel.Text = tostring(countdownSeconds)
	end
	
	local statusLabel = self:_findStatusLabel()
	if statusLabel then
		statusLabel.Visible = true
		statusLabel.TextColor3 = COLOR_YELLOW
		statusLabel.Text = `Vote! Time: {countdownSeconds}`
	end
	
	task.spawn(function()
		for i = countdownSeconds, 1, -1 do
			if not voting.Visible then break end
			if countdownLabel and countdownLabel:IsA("TextLabel") then
				countdownLabel.Text = tostring(i)
			end
			if statusLabel and statusLabel.Parent then
				statusLabel.Text = `Vote! Time: {i}`
			end
			task.wait(1)
		end
	end)
	
	for _, difficulty in ipairs(difficulties) do
		local option = votingTemplate:Clone()
		option.Name = difficulty
		option.Visible = true
		option.Parent = container
		
		local modeLabel = option:FindFirstChild("Mode")
		if modeLabel and modeLabel:IsA("TextLabel") then
			modeLabel.Text = difficulty
		end
		
		local votesLabel = option:FindFirstChild("Votes")
		if votesLabel and votesLabel:IsA("TextLabel") then
			votesLabel.Text = "0"
		end
		
		local voteButton = option:FindFirstChild("TextButton") or option:FindFirstChildWhichIsA("TextButton")
		if voteButton then
			local conn = voteButton.MouseButton1Click:Connect(function()
				if self._currentVote == difficulty then return end
				
				Log("Vote cast for: " .. difficulty .. " | Previous: " .. (self._currentVote or "none"))
				local previousVote = self._currentVote
				self._currentVote = difficulty
				self._hasVoted = true
				self.BoothService.CastVote:Fire(difficulty, previousVote)
				
				for _, child in container:GetChildren() do
					if child:IsA("Frame") or child:IsA("ImageLabel") then
						if child.Name == difficulty then
							child.BackgroundColor3 = COLOR_GREEN
						else
							child.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
						end
					end
				end
			end)
			table.insert(self._votingConnections, conn)
		end
	end
end

function BoothController:UpdateVotes(voteTable: {[string]: number})
	Log("UpdateVotes - Received vote update")
	if not self._votingContainer then return end
	
	local container = self._votingContainer:FindFirstChild("Container")
	if not container then return end
	
	for difficulty, count in pairs(voteTable) do
		local option = container:FindFirstChild(difficulty)
		if option then
			local votesLabel = option:FindFirstChild("Votes")
			if votesLabel and votesLabel:IsA("TextLabel") then
				votesLabel.Text = tostring(count)
			end
		end
	end
end

function BoothController:ShowVotingResult(chosenDifficulty: string)
	Log("ShowVotingResult - Chosen: " .. chosenDifficulty)
	local statusLabel = self:_findStatusLabel()
	if statusLabel then
		statusLabel.Visible = true
		statusLabel.Text = `Playing: {chosenDifficulty}!`
		statusLabel.TextColor3 = COLOR_GREEN
	end
	
	self:CleanupVotingUI()
	
	task.delay(1.5, function()
		if statusLabel and statusLabel.Parent then
			statusLabel.Visible = false
			statusLabel.TextColor3 = COLOR_WHITE
		end
	end)
end

function BoothController:UpdateOpponentProgress(opponentUserId: number, progress: number)
	if not self.gameActive then return end
	Log("UpdateOpponentProgress - Opponent: " .. tostring(opponentUserId) .. " | Progress: " .. string.format("%.1f%%", progress * 100))
	
	local screenGui = self:_getCachedScreenGui()
	if not screenGui then return end
	
	local typingGui = screenGui:FindFirstChild("TypingGame")
	if not typingGui or not typingGui.Visible then return end
	
	local bar = typingGui:FindFirstChild("Bar")
	if not bar then return end
	
	local playerTemplate = bar:FindFirstChild("PlayerTemplate") :: ImageLabel?
	if not playerTemplate then return end
	
	if playerTemplate.Image == "" then
		playerTemplate.Image = `rbxthumb://type=AvatarHeadShot&id={opponentUserId}&w=150&h=150`
	end
	
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
	Log("Word completed: " .. tostring(self.currentIndex) .. "/" .. tostring(#self.currentWords) .. " | Word: " .. expectedWord)
	self.BoothService.ValidateWordCompletion:Fire(self.currentIndex, expectedWord)
	
	self.currentIndex += 1
	textBox.Text = ""
	textBox.TextColor3 = COLOR_WHITE
	self:UpdatePreviewColors(preview, "")
	self:UpdateProgressBar(typingGui)
	
	if self.currentIndex > #self.currentWords then
		Log("All words completed - Sending PlayerWon signal")
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
	
	if self._focusLostConnection then
		self._focusLostConnection:Disconnect()
		self._focusLostConnection = nil
	end
	
	local lastValidationTime = 0
	
	self._focusLostConnection = textBox.FocusLost:Connect(function(enterPressed)
		if not self.gameActive then return end
		
		if enterPressed then
			local text = string.gsub(textBox.Text, "%s+", "")
			local expectedWord = self.currentWords[self.currentIndex]
			
			if text == expectedWord then
				Log("Enter pressed - Word correct: " .. text)
				self:_handleWordCompletion(textBox, typingGui, preview, expectedWord, tick())
				self:ShowFeedback(true)
			elseif #text > 0 then
				self.errorCount += 1
				Log("Enter pressed - Typing error: " .. tostring(self.errorCount) .. "/5 | Typed: " .. text .. " | Expected: " .. expectedWord)
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
			
			task.wait()
			if self.gameActive then
				textBox:CaptureFocus()
			end
		end
	end)
	
	self.typingConnection = textBox:GetPropertyChangedSignal("Text"):Connect(function()
		if not self.gameActive then return end
		
		local currentTime = tick()
		if currentTime - lastValidationTime < VALIDATION_COOLDOWN then return end
		
		local text = textBox.Text
		if self.currentIndex > #self.currentWords then return end
		
		local expectedWord = self.currentWords[self.currentIndex]
		
		-- Auto-correct first character case to fix mobile auto-capitalization
		if #text == 1 and #expectedWord > 0 then
			local expectedFirstChar = string.sub(expectedWord, 1, 1)
			local typedFirstChar = string.sub(text, 1, 1)
			-- If only case differs, auto-correct it
			if string.lower(expectedFirstChar) == string.lower(typedFirstChar) and expectedFirstChar ~= typedFirstChar then
				textBox.Text = expectedFirstChar
				return
			end
		end
		
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
				Log("Typing error: " .. tostring(self.errorCount) .. "/5 | Typed: " .. tostring(typedWord) .. " | Expected: " .. expectedWord)
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

function BoothController:CreateTypingGame(words: {string}, opponentUserId: number?)
	Log("CreateTypingGame - Words: " .. tostring(#words) .. " | Opponent: " .. tostring(opponentUserId or "none"))
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
	
	if opponentUserId then
		local bar = typingGui:FindFirstChild("Bar")
		if bar then
			local playerTemplate = bar:FindFirstChild("PlayerTemplate") :: ImageLabel?
			if playerTemplate then
				playerTemplate.Image = `rbxthumb://type=AvatarHeadShot&id={opponentUserId}&w=150&h=150`
			end
		end
	end
	

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

function BoothController:ResetProgressBar()
	local screenGui = self:_getCachedScreenGui()
	if not screenGui then return end
	
	local typingGui = screenGui:FindFirstChild("TypingGame")
	if not typingGui then return end
	
	local bar = typingGui:FindFirstChild("Bar")
	if not bar then return end
	
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

function BoothController:ShowGameResult(didWin: boolean, winnerName: string)
	Log("ShowGameResult - Won: " .. tostring(didWin) .. " | Winner: " .. winnerName)
	self.gameActive = false
	
	local screenGui = self:_getCachedScreenGui()
	if screenGui then
		local typingGui = screenGui:FindFirstChild("TypingGame")
		if typingGui then
			typingGui.Visible = false
		end
	end
	
	self:ResetProgressBar()
	
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
	Log("_cleanup - Resetting all game state")
	self._countdownCancel = true
	self.gameActive = false
	self:HideStatusLabel()
	self:HidePlaySoloButton()
	self:CleanupVotingUI()
	self:RevertCamera()
	self:SetJumpAbility(true)
	self:ResetProgressBar()
	
	if self.typingConnection then
		self.typingConnection:Disconnect()
		self.typingConnection = nil
	end
	
	if self._focusLostConnection then
		self._focusLostConnection:Disconnect()
		self._focusLostConnection = nil
	end
	
	table.clear(self.currentWords)
	self.currentIndex = 1
	self.errorCount = 0
end

function BoothController:KnitStart()
	Log("BoothController started - Setting up signal connections")
	local service = self.BoothService
	
	if service.UpdateCamera then
		service.UpdateCamera:Connect(function(boothModel)
			Log("Signal received: UpdateCamera")
			self:UpdateCamera(boothModel)
		end)
	end
	
	if service.RevertCamera then
		service.RevertCamera:Connect(function()
			Log("Signal received: RevertCamera")
			self:_cleanup()
		end)
	end
	
	if service.StartGame then
		service.StartGame:Connect(function(boothModel, words, opponentUserId)
			Log("Signal received: StartGame")
			self:CreateTypingGame(words, opponentUserId)
		end)
	end
	
	if service.StartVoting then
		service.StartVoting:Connect(function(difficulties, countdownSeconds)
			Log("Signal received: StartVoting")
			self:HidePlaySoloButton()
			self:ShowVotingUI(difficulties, countdownSeconds)
		end)
	end
	
	if service.UpdateVotes then
		service.UpdateVotes:Connect(function(voteTable)
			Log("Signal received: UpdateVotes")
			self:UpdateVotes(voteTable)
		end)
	end
	
	if service.VotingComplete then
		service.VotingComplete:Connect(function(chosenDifficulty)
			Log("Signal received: VotingComplete")
			self:ShowVotingResult(chosenDifficulty)
		end)
	end
	
	if service.BeginCountdown then
		service.BeginCountdown:Connect(function(seconds)
			Log("Signal received: BeginCountdown")
			self:HidePlaySoloButton()
			self:ShowStartCountdown(seconds)
		end)
	end
	
	if service.ShowGameResult then
		service.ShowGameResult:Connect(function(didWin, winnerName)
			Log("Signal received: ShowGameResult")
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
			Log("Signal received: UpdateBoothPlayerCount")
			self:UpdateBoothPlayerCount(playerCount)
		end)
	end
end

function BoothController:KnitInit()
	self.BoothService = Knit.GetService("BoothService")
end

return BoothController