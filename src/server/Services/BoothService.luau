local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local BoothService = Knit.CreateService({
	Name = "BoothService",
	Client = {
		UpdateCamera = Knit.CreateSignal(),
		RevertCamera = Knit.CreateSignal(),
		StartGame = Knit.CreateSignal(),
		BeginCountdown = Knit.CreateSignal(),
		PlayerWon = Knit.CreateSignal(),
		PlayerLost = Knit.CreateSignal(),
		ShowGameResult = Knit.CreateSignal(),
		ValidateWordCompletion = Knit.CreateSignal(),
		UpdateWPM = Knit.CreateSignal(),
		UpdateOpponentProgress = Knit.CreateSignal(),
		UpdateBoothPlayerCount = Knit.CreateSignal(),
		PlaySolo = Knit.CreateSignal(),
		StartVoting = Knit.CreateSignal(),
		CastVote = Knit.CreateSignal(),
		UpdateVotes = Knit.CreateSignal(),
		VotingComplete = Knit.CreateSignal(),
	}
})

local REQUIRED_PLAYERS = 2
local COUNTDOWN_SECONDS = 5
local VOTING_SECONDS = 10
local WORD_COUNT = 35
local MAX_ERRORS = 5
local BOT_AVATAR_ID = 9741864268
local BOT_NAME = "TypeBot"
local BOT_BASE_WPM = 45
local BOT_WPM_VARIANCE = 15
local BOT_UPDATE_INTERVAL = 0.15
local BOT_STUTTER_CHANCE = 0.08
local BOT_BURST_CHANCE = 0.05

local activeBooths = {}
local boothCountdowns = {}
local activeGames = {}
local playerErrors = {}
local playerWordsCompleted = {}
local spawnedKeyboards = {}
local playerWPM = {}
local playerTypingStats = {}
local wpmUpdateLoops = {}
local hasPlayerWon = {}
local soloGameBots = {}
local botUpdateLoops = {}
local boothVotes = {}
local playerVoted = {}
local DataService, TypewriterShopService, QuestService
local WordModule

local function getPlayersInBooth(boothModel: Model): {Player}
	local players = {}
	for player, booth in pairs(activeBooths) do
		if booth == boothModel then
			table.insert(players, player)
		end
	end
	return players
end

local function countPlayersInBooth(boothModel: Model): number
	return #getPlayersInBooth(boothModel)
end

local function isGameActive(boothModel: Model): boolean
	return activeGames[boothModel] ~= nil
end

local function calculateWPM(player: Player): number
	local stats = playerTypingStats[player]
	if not stats then return 0 end

	local elapsedMinutes = (tick() - stats.startTime) / 60
	if elapsedMinutes == 0 then return 0 end

	local timeSinceLastType = tick() - stats.lastTypeTime
	local decayFactor = timeSinceLastType > 2 and math.max(0.1, 1 - ((timeSinceLastType - 2) * 0.1)) or 1

	return math.floor((stats.correctWordCount / elapsedMinutes) * decayFactor)
end

local function stopLoop(loopTable: {[Model]: thread}, boothModel: Model)
	if loopTable[boothModel] then
		pcall(task.cancel, loopTable[boothModel])
		loopTable[boothModel] = nil
	end
end

local function setBoothHitboxCanCollide(boothModel: Model, canCollide: boolean)
	local hitbox = boothModel:FindFirstChild("Hitbox")
	if hitbox and hitbox:IsA("BasePart") then
		hitbox.CanCollide = canCollide
	end
end

local function setBoothRootCanCollide(boothModel: Model, canCollide: boolean)
	local root = boothModel:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		root.CanCollide = canCollide
	end
end

local function teleportPlayerToSpawn(player: Player)
	local character = player and player.Character
	if not character then return end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		hrp.CFrame = spawnLocation.CFrame + Vector3.new(0, 3, 0)
	else
		hrp.CFrame = CFrame.new(0, 10, 0)
	end
end

local function clearPlayerData(player: Player)
	playerErrors[player] = nil
	playerWordsCompleted[player] = nil
	playerWPM[player] = nil
	playerTypingStats[player] = nil
	hasPlayerWon[player] = nil
end

local function endGame(boothModel: Model)
	print("[Server] Ending game for booth:", boothModel.Name)
	stopLoop(wpmUpdateLoops, boothModel)
	stopLoop(botUpdateLoops, boothModel)
	soloGameBots[boothModel] = nil
	activeGames[boothModel] = nil
	setBoothHitboxCanCollide(boothModel, false)
	setBoothRootCanCollide(boothModel, false)

	for _, player in ipairs(getPlayersInBooth(boothModel)) do
		print("[Server] Clearing player data for:", player.Name)
		clearPlayerData(player)
	end
end

local function kickPlayerFromSeat(player: Player)
	local character = player and player.Parent and player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid and humanoid.SeatPart then
		humanoid.Sit = false
	end
end

local function updatePlayerStats(player: Player, won: boolean, averageWPM: number, isSolo: boolean)
	print("[Server] Updating stats for:", player.Name, "| Won:", won, "| WPM:", averageWPM, "| Solo:", isSolo)
	if not DataService then return end

	local session = DataService:getSession(player)
	if not session or not session.Data then return end

	local data = session.Data
	local coinMultiplier = data.DoubleCoins and 2 or 1
	print("[Server] Coin multiplier for", player.Name, ":", coinMultiplier)

	if isSolo then
		local coins = won and 12 or 5
		data.Coins = (data.Coins or 0) + (coins * coinMultiplier)
		data.WPM = math.floor(averageWPM)
		DataService:Replicate(player, "Coins")
		DataService:Replicate(player, "WPM")
		return
	end

	if won then
		data.Coins = (data.Coins or 0) + (25 * coinMultiplier)
		data.Wins = (data.Wins or 0) + 1
		data.Winstreak = (data.Winstreak or 0) + 1

		if data.Winstreak > (data.HighestWinstreak or 0) then
			data.HighestWinstreak = data.Winstreak
		end

		if QuestService then
			QuestService:TrackWin(player)
			QuestService:TrackWinStreak(player, data.Winstreak)
		end
	else
		data.Coins = (data.Coins or 0) + (10 * coinMultiplier)
		data.Losses = (data.Losses or 0) + 1

		local previousWinstreak = data.Winstreak or 0
		if previousWinstreak > 0 then
			if TypewriterShopService then
				TypewriterShopService:registerWinstreakRestore(player.UserId, previousWinstreak)
			end
			data.Winstreak = 0
			pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, 3462811274)
		else
			data.Winstreak = 0
		end
	end

	data.WPM = math.floor(averageWPM)
	local totalGames = (data.Wins or 0) + (data.Losses or 0)
	data.WinRate = totalGames > 0 and math.floor((data.Wins / totalGames) * 100) or 0

	DataService:updateLeaderstats(player, "Winstreak", data.Winstreak)
	DataService:updateLeaderstats(player, "Wins", data.Wins)

	for _, key in {"Coins", "Wins", "Losses", "Winstreak", "HighestWinstreak", "WPM", "WinRate"} do
		DataService:Replicate(player, key)
	end
end

local function endSoloGame(boothModel: Model, player: Player, playerWon: boolean)
	print("[Server] Ending solo game | Player:", player and player.Name or "nil", "| Won:", playerWon)
	stopLoop(botUpdateLoops, boothModel)
	soloGameBots[boothModel] = nil

	if not player or not player.Parent then
		print("[Server] Player left during solo game, ending")
		endGame(boothModel)
		return
	end

	local wpm = playerWPM[player] or 0
	print("[Server] Solo game final WPM:", wpm)
	updatePlayerStats(player, playerWon, wpm, true)

	if playerWon and QuestService then
		local errors = playerErrors[player] or 0
		if errors == 0 then
			QuestService:TrackPerfectGame(player)
		end
	end

	local winnerName = playerWon and player.Name or BOT_NAME
	BoothService.Client.ShowGameResult:Fire(player, playerWon, winnerName)

	task.wait(3.5)
	kickPlayerFromSeat(player)
	BoothService:RemovePlayerFromBooth(player)
	endGame(boothModel)
end

local function endGameWithWinner(boothModel: Model, winner: Player)
	print("[Server] Game ended with winner:", winner.Name)
	local playersInBooth = getPlayersInBooth(boothModel)

	for _, player in ipairs(playersInBooth) do
		local wpm = playerWPM[player] or 0
		local won = player == winner
		print("[Server] Processing player:", player.Name, "| Won:", won, "| WPM:", wpm)
		updatePlayerStats(player, won, wpm, false)

		if won and QuestService then
			local errors = playerErrors[player] or 0
			if errors == 0 then
				QuestService:TrackPerfectGame(player)
			end
		end

		BoothService.Client.ShowGameResult:Fire(player, won, winner.Name)
	end

	task.wait(3.5)

	for _, player in ipairs(playersInBooth) do
		kickPlayerFromSeat(player)
		BoothService:RemovePlayerFromBooth(player)
	end

	endGame(boothModel)
end

local function startBotProgress(boothModel: Model, player: Player, totalWords: number)
	print("[Server] Starting bot progress for player:", player.Name, "| Words:", totalWords)
	soloGameBots[boothModel] = {
		progress = 0,
		isStuttering = false,
		stutterEndTime = 0,
		isBursting = false,
		burstEndTime = 0,
		lastUpdateTime = tick(),
	}

	stopLoop(botUpdateLoops, boothModel)

	botUpdateLoops[boothModel] = task.spawn(function()
		local bot = soloGameBots[boothModel]

		while isGameActive(boothModel) and bot and bot.progress < 1 do
			local currentTime = tick()
			local deltaTime = currentTime - bot.lastUpdateTime
			bot.lastUpdateTime = currentTime

			if bot.isStuttering and currentTime > bot.stutterEndTime then
				bot.isStuttering = false
			end
			if bot.isBursting and currentTime > bot.burstEndTime then
				bot.isBursting = false
			end

			local roll = math.random()
			if not bot.isStuttering and not bot.isBursting then
				if roll < BOT_STUTTER_CHANCE then
					bot.isStuttering = true
					bot.stutterEndTime = currentTime + math.random() * 1.5 + 0.3
				elseif roll < BOT_STUTTER_CHANCE + BOT_BURST_CHANCE then
					bot.isBursting = true
					bot.burstEndTime = currentTime + math.random() * 1.0 + 0.5
				end
			end

			local effectiveWPM = BOT_BASE_WPM + (math.random() - 0.5) * BOT_WPM_VARIANCE * 2

			if bot.isStuttering then
				effectiveWPM = effectiveWPM * 0.1
				if math.random() < 0.15 then
					bot.progress = math.max(0, bot.progress - 0.005)
				end
			elseif bot.isBursting then
				effectiveWPM = effectiveWPM * 1.4
			end

			local progressIncrement = (effectiveWPM / 60 / totalWords) * deltaTime
			local fluctuation = (math.random() - 0.5) * 0.003
			bot.progress = math.clamp(bot.progress + progressIncrement + fluctuation, 0, 1)

			if player and player.Parent then
				BoothService.Client.UpdateOpponentProgress:Fire(player, BOT_AVATAR_ID, bot.progress)
			else
				break
			end

			if bot.progress >= 1 and not hasPlayerWon[player] then
				hasPlayerWon[player] = false
				task.spawn(endSoloGame, boothModel, player, false)
				break
			end

			task.wait(BOT_UPDATE_INTERVAL)
		end
	end)
end

local function startWPMUpdates(boothModel: Model)
	stopLoop(wpmUpdateLoops, boothModel)

	wpmUpdateLoops[boothModel] = task.spawn(function()
		while isGameActive(boothModel) do
			for _, player in ipairs(getPlayersInBooth(boothModel)) do
				local wpm = calculateWPM(player)
				BoothService.Client.UpdateWPM:Fire(player, wpm)
			end
			task.wait(0.1)
		end
	end)
end

local function initializePlayerStats(player: Player)
	playerErrors[player] = 0
	playerWordsCompleted[player] = 0
	hasPlayerWon[player] = nil
	playerTypingStats[player] = {
		startTime = tick(),
		lastTypeTime = tick(),
		correctWordCount = 0,
	}
end

local function startGame(boothModel: Model, words: {string})
	if isGameActive(boothModel) then return end

	activeGames[boothModel] = { words = words, startTime = tick() }
	setBoothHitboxCanCollide(boothModel, true)

	local playersInBooth = getPlayersInBooth(boothModel)
	for _, player in ipairs(playersInBooth) do
		initializePlayerStats(player)
		local opponentUserId = nil
		for _, otherPlayer in ipairs(playersInBooth) do
			if otherPlayer ~= player then
				opponentUserId = otherPlayer.UserId
				break
			end
		end
		BoothService.Client.StartGame:Fire(player, boothModel, words, opponentUserId)
	end

	startWPMUpdates(boothModel)
end

local function getBoothStatusLabel(boothModel: Model): TextLabel?
	local root = boothModel:FindFirstChild("Root")
	local billboard = root and root:FindFirstChild("BillboardGui")
	local holder = billboard and billboard:FindFirstChild("Holder")
	return holder and holder:FindFirstChild("Status")
end

local function updateBoothStatus(boothModel: Model, playerCount: number, displayText: string?)
	local statusLabel = getBoothStatusLabel(boothModel)
	if statusLabel then
		statusLabel.Visible = true
		statusLabel.Text = displayText or (playerCount .. "/2")
	end
end

local function hideBoothStatus(boothModel: Model)
	local statusLabel = getBoothStatusLabel(boothModel)
	if statusLabel then
		statusLabel.Visible = false
	end
end

local function loadWordModule()
	if WordModule then return WordModule end

	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local wordModuleScript = shared and (shared:FindFirstChild("WordModule") or shared:FindFirstChild("WordModula"))
	wordModuleScript = wordModuleScript or ReplicatedStorage:FindFirstChild("WordModule") or ReplicatedStorage:FindFirstChild("WordModula")

	if wordModuleScript then
		local success, module = pcall(require, wordModuleScript)
		if success then
			WordModule = module
			return module
		end
	end
	return nil
end

local function generateWords(count: number, difficulty: string?): {string}
	local wordModule = loadWordModule()
	if not wordModule then
		local words = {}
		for i = 1, count do
			table.insert(words, "word" .. i)
		end
		return words
	end

	if difficulty and wordModule.GenerateWordsFromDifficulty then
		return wordModule.GenerateWordsFromDifficulty(difficulty, count)
	end

	local words = {}
	for i = 1, count do
		local word = wordModule.GetRandomWord and wordModule.GetRandomWord()
		if type(word) ~= "string" or #word == 0 then
			word = "word" .. i
		end
		table.insert(words, word)
	end

	return words
end

local function getRandomDifficulties(): {string}
	local wordModule = loadWordModule()
	if wordModule and wordModule.GetRandomDifficulties then
		return wordModule.GetRandomDifficulties(3)
	end
	return {"Easy", "Medium", "Hard"}
end

local function getDifficultyInfo(difficulty: string): {name: string, description: string}?
	local wordModule = loadWordModule()
	if wordModule and wordModule.GetDifficultyInfo then
		return wordModule.GetDifficultyInfo(difficulty)
	end
	return {name = difficulty, description = ""}
end

local function disablePlayerJump(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
end

local function enablePlayerJump(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7.2
	end
end

local function startVotingPhase(boothModel: Model, isSolo: boolean)
	print("[Server] Starting voting phase | Solo:", isSolo)
	local playersInBooth = getPlayersInBooth(boothModel)
	local difficulties = getRandomDifficulties()
	print("[Server] Voting difficulties:", table.concat(difficulties, ", "))

	boothVotes[boothModel] = {
		difficulties = difficulties,
		votes = {},
		isSolo = isSolo,
	}

	for _, difficulty in ipairs(difficulties) do
		boothVotes[boothModel].votes[difficulty] = 0
	end

	for _, player in ipairs(playersInBooth) do
		playerVoted[player] = false
		disablePlayerJump(player)
		BoothService.Client.StartVoting:Fire(player, difficulties, VOTING_SECONDS)
	end

	task.spawn(function()
		local startTime = tick()
		local votingData = boothVotes[boothModel]

		while tick() - startTime < VOTING_SECONDS do
			if not votingData or not boothVotes[boothModel] then return end

			local allVoted = true
			for _, player in ipairs(getPlayersInBooth(boothModel)) do
				if not playerVoted[player] then
					allVoted = false
					break
				end
			end

			if allVoted and not isSolo then
				break
			end

			task.wait(0.25)
		end

		if not boothVotes[boothModel] then return end

		local votes = boothVotes[boothModel].votes
		local chosenDifficulty = nil
		local highestVotes = 0

		for difficulty, voteCount in pairs(votes) do
			if voteCount > highestVotes then
				highestVotes = voteCount
				chosenDifficulty = difficulty
			end
		end

		if highestVotes == 0 then
			chosenDifficulty = difficulties[math.random(1, #difficulties)]
			print("[Server] No votes cast, randomly selected:", chosenDifficulty)
		end

		print("[Server] Voting complete! Chosen difficulty:", chosenDifficulty, "| Votes:", highestVotes)
		for _, player in ipairs(getPlayersInBooth(boothModel)) do
			BoothService.Client.VotingComplete:Fire(player, chosenDifficulty)
		end

		task.wait(1.5)

		local words = generateWords(WORD_COUNT, chosenDifficulty)

		if isSolo then
			local player = playersInBooth[1]
			if player and player.Parent then
				activeGames[boothModel] = {
					words = words,
					startTime = tick(),
					isSoloGame = true,
					difficulty = chosenDifficulty,
				}

				setBoothHitboxCanCollide(boothModel, true)
				initializePlayerStats(player)
				BoothService.Client.StartGame:Fire(player, boothModel, words, BOT_AVATAR_ID)
				startWPMUpdates(boothModel)

				task.delay(0.1, function()
					local game = activeGames[boothModel]
					if game and game.isSoloGame then
						startBotProgress(boothModel, player, WORD_COUNT)
					end
				end)
			end
		else
			activeGames[boothModel] = {
				words = words,
				startTime = tick(),
				difficulty = chosenDifficulty,
			}
			setBoothHitboxCanCollide(boothModel, true)

			local allPlayers = getPlayersInBooth(boothModel)
			for _, player in ipairs(allPlayers) do
				initializePlayerStats(player)
				local opponentUserId = nil
				for _, otherPlayer in ipairs(allPlayers) do
					if otherPlayer ~= player then
						opponentUserId = otherPlayer.UserId
						break
					end
				end
				BoothService.Client.StartGame:Fire(player, boothModel, words, opponentUserId)
			end

			startWPMUpdates(boothModel)
		end

		for _, player in ipairs(getPlayersInBooth(boothModel)) do
			playerVoted[player] = nil
		end
		boothVotes[boothModel] = nil
	end)
end

local function startBoothCountdown(boothModel: Model)
	if boothCountdowns[boothModel] then return end
	if boothVotes[boothModel] then return end
	if isGameActive(boothModel) then return end

	boothCountdowns[boothModel] = true

	task.spawn(function()
		for i = COUNTDOWN_SECONDS, 1, -1 do
			local playerCount = countPlayersInBooth(boothModel)

			if playerCount < REQUIRED_PLAYERS then
				updateBoothStatus(boothModel, playerCount)
				boothCountdowns[boothModel] = nil
				return
			end

			updateBoothStatus(boothModel, playerCount, "Game Starting in " .. i)
			task.wait(1)
		end

		if countPlayersInBooth(boothModel) >= REQUIRED_PLAYERS then
			hideBoothStatus(boothModel)
			startVotingPhase(boothModel, false)
		end

		boothCountdowns[boothModel] = nil
	end)
end

local function removeSpawnedKeyboard(player: Player, boothModel: Model)
	local keyboards = spawnedKeyboards[boothModel]
	if not keyboards then return end

	local keyboardModel = keyboards[player]
	if keyboardModel and keyboardModel.Parent then
		keyboardModel:Destroy()
	end
	keyboards[player] = nil
end

local function spawnKeyboardForPlayer(player: Player, boothModel: Model, seatName: string)
	local session = DataService and DataService:getSession(player)
	if not session or not session.Data then return end

	local equippedKeyboard = session.Data.EquippedKeyboard
	if not equippedKeyboard then return end

	local keyboardsFolder = ReplicatedStorage:FindFirstChild("Assets")
	keyboardsFolder = keyboardsFolder and keyboardsFolder:FindFirstChild("Keyboards")
	if not keyboardsFolder then return end

	local keyboardModel = keyboardsFolder:FindFirstChild(equippedKeyboard)
	if not keyboardModel then return end

	local spawnName = seatName == "Seat" and "KeyboardSpawn" or "KeyboardSpawn2"
	local spawnPoint = boothModel:FindFirstChild(spawnName, true)
	if not spawnPoint then return end

	local clonedKeyboard = keyboardModel:Clone()
	clonedKeyboard:PivotTo(CFrame.lookAt(spawnPoint.Position, spawnPoint.Position + spawnPoint.CFrame.LookVector))
	clonedKeyboard.Parent = boothModel

	spawnedKeyboards[boothModel] = spawnedKeyboards[boothModel] or {}
	spawnedKeyboards[boothModel][player] = clonedKeyboard
end

function BoothService:AddPlayerToBooth(player: Player, boothModel: Model): boolean
	if not player or not player.Parent or activeBooths[player] then return false end

	-- Reject players trying to join a solo voting phase or solo game
	local votingData = boothVotes[boothModel]
	local gameData = activeGames[boothModel]
	if (votingData and votingData.isSolo) or (gameData and gameData.isSoloGame) or isGameActive(boothModel) then
		print("[Server] Rejected player from booth (game/solo in progress):", player.Name)
		task.defer(function()
			kickPlayerFromSeat(player)
			task.wait(0.1)
			teleportPlayerToSpawn(player)
		end)
		self.Client.RevertCamera:Fire(player)
		return false
	end

	print("[Server] Adding player to booth:", player.Name, "| Booth:", boothModel.Name)
	activeBooths[player] = boothModel
	local playerCount = countPlayersInBooth(boothModel)
	print("[Server] Booth player count:", playerCount)

	self.Client.UpdateCamera:Fire(player, boothModel)
	updateBoothStatus(boothModel, playerCount)

	for _, p in ipairs(getPlayersInBooth(boothModel)) do
		self.Client.UpdateBoothPlayerCount:Fire(p, playerCount)
	end

	if playerCount >= REQUIRED_PLAYERS and not boothVotes[boothModel] and not isGameActive(boothModel) then
		startBoothCountdown(boothModel)
	end

	return true
end

function BoothService:RemovePlayerFromBooth(player: Player)
	if not player then return end

	local boothModel = activeBooths[player]
	if not boothModel then return end

	print("[Server] Removing player from booth:", player.Name)
	if isGameActive(boothModel) and hasPlayerWon[player] == nil then
		print("[Server] Player left during active game, marking as loss")
		updatePlayerStats(player, false, playerWPM[player] or 0, false)

		for _, otherPlayer in ipairs(getPlayersInBooth(boothModel)) do
			if otherPlayer ~= player and otherPlayer.Parent and not hasPlayerWon[otherPlayer] then
				hasPlayerWon[otherPlayer] = true
				task.delay(0.1, endGameWithWinner, boothModel, otherPlayer)
				break
			end
		end
	end

	removeSpawnedKeyboard(player, boothModel)
	enablePlayerJump(player)

	activeBooths[player] = nil
	clearPlayerData(player)

	local playerCount = countPlayersInBooth(boothModel)
	updateBoothStatus(boothModel, playerCount)

	for _, p in ipairs(getPlayersInBooth(boothModel)) do
		self.Client.UpdateBoothPlayerCount:Fire(p, playerCount)
	end

	boothCountdowns[boothModel] = nil

	if isGameActive(boothModel) and playerCount == 0 then
		endGame(boothModel)
	end

	self.Client.RevertCamera:Fire(player)
end

local function onSeatOccupancyChanged(seat: Seat, boothModel: Model)
	local occupant = seat.Occupant

	if occupant then
		local player = Players:GetPlayerFromCharacter(occupant.Parent)
		if player then
			local accepted = BoothService:AddPlayerToBooth(player, boothModel)
			if accepted then
				spawnKeyboardForPlayer(player, boothModel, seat.Name)
			end
		end
	else
		for _, player in ipairs(getPlayersInBooth(boothModel)) do
			local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
			if humanoid and humanoid.SeatPart == seat then
				BoothService:RemovePlayerFromBooth(player)
				break
			end
		end
	end
end

local function setupBoothListeners(boothModel: Model)
	local seatsFolder = boothModel:WaitForChild("Seats")
	for _, seat in pairs(seatsFolder:GetChildren()) do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			seat:GetPropertyChangedSignal("Occupant"):Connect(function()
				onSeatOccupancyChanged(seat, boothModel)
			end)
		end
	end
end

function BoothService:KnitStart()
	TypewriterShopService = Knit.GetService("TypewriterShopService")
	QuestService = Knit.GetService("QuestService")

	for _, booth in ipairs(workspace:WaitForChild("BoothsFolder"):GetChildren()) do
		setupBoothListeners(booth)
	end

	self.Client.PlayerWon:Connect(function(player)
		print("[Server] PlayerWon signal received from:", player and player.Name or "nil")
		if not player or not player.Parent then return end

		local boothModel = activeBooths[player]
		local gameData = boothModel and activeGames[boothModel]
		if not gameData or hasPlayerWon[player] then 
			print("[Server] PlayerWon ignored - no game data or already won")
			return 
		end

		hasPlayerWon[player] = true
		print("[Server] Player won the game:", player.Name, "| Solo:", gameData.isSoloGame)

		if gameData.isSoloGame then
			endSoloGame(boothModel, player, true)
		else
			endGameWithWinner(boothModel, player)
		end
	end)

	self.Client.PlayerLost:Connect(function(player)
		print("[Server] PlayerLost signal received from:", player and player.Name or "nil")
		if not player or not player.Parent then return end

		local boothModel = activeBooths[player]
		if not boothModel or not isGameActive(boothModel) or not playerErrors[player] then return end
		if hasPlayerWon[player] ~= nil then return end

		playerErrors[player] = playerErrors[player] + 1
		print("[Server] Player error count:", player.Name, "|", playerErrors[player], "/", MAX_ERRORS)

		if playerErrors[player] >= MAX_ERRORS and hasPlayerWon[player] == nil then
			print("[Server] Player reached max errors, triggering loss:", player.Name)
			hasPlayerWon[player] = false

			local gameData = activeGames[boothModel]
			if gameData and gameData.isSoloGame then
				task.spawn(endSoloGame, boothModel, player, false)
			else
				for _, otherPlayer in ipairs(getPlayersInBooth(boothModel)) do
					if otherPlayer ~= player then
						hasPlayerWon[otherPlayer] = hasPlayerWon[otherPlayer] or true
						endGameWithWinner(boothModel, otherPlayer)
						break
					end
				end
			end
		end
	end)

	self.Client.ValidateWordCompletion:Connect(function(player, wordIndex, word)
		if not player or not player.Parent then return end

		local boothModel = activeBooths[player]
		local gameData = boothModel and activeGames[boothModel]
		if not gameData or not gameData.words then return end
		if wordIndex < 1 or wordIndex > #gameData.words or gameData.words[wordIndex] ~= word then return end

		print("[Server] Word completed:", player.Name, "| Word:", wordIndex, "/", #gameData.words)
		local stats = playerTypingStats[player]
		if stats then
			stats.correctWordCount = stats.correctWordCount + 1
			stats.lastTypeTime = tick()
			playerWPM[player] = calculateWPM(player)
		end

		if QuestService then
			QuestService:TrackWordTyped(player)
		end

		playerWordsCompleted[player] = (playerWordsCompleted[player] or 0) + 1
		local progress = playerWordsCompleted[player] / #gameData.words

		for _, otherPlayer in ipairs(getPlayersInBooth(boothModel)) do
			if otherPlayer ~= player then
				self.Client.UpdateOpponentProgress:Fire(otherPlayer, player.UserId, progress)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if activeBooths[player] then
			self:RemovePlayerFromBooth(player)
		end
	end)

	self.Client.PlaySolo:Connect(function(player)
		print("[Server] PlaySolo signal received from:", player and player.Name or "nil")
		if not player or not player.Parent then return end

		local boothModel = activeBooths[player]
		if not boothModel or countPlayersInBooth(boothModel) ~= 1 or isGameActive(boothModel) then 
			print("[Server] PlaySolo rejected - invalid state")
			return 
		end
		if boothVotes[boothModel] then return end

		print("[Server] Starting solo game for:", player.Name)
		hideBoothStatus(boothModel)
		setBoothRootCanCollide(boothModel, true)
		startVotingPhase(boothModel, true)
	end)

	self.Client.CastVote:Connect(function(player, difficulty, previousVote)
		print("[Server] CastVote received:", player and player.Name or "nil", "| Vote:", difficulty, "| Previous:", previousVote or "none")
		if not player or not player.Parent then return end

		local boothModel = activeBooths[player]
		if not boothModel then return end

		local votingData = boothVotes[boothModel]
		if not votingData then return end

		if not votingData.votes[difficulty] then return end

		if previousVote and votingData.votes[previousVote] then
			votingData.votes[previousVote] = math.max(0, votingData.votes[previousVote] - 1)
		end

		playerVoted[player] = true
		votingData.votes[difficulty] = votingData.votes[difficulty] + 1
		print("[Server] Vote registered for:", difficulty, "| New count:", votingData.votes[difficulty])

		for _, p in ipairs(getPlayersInBooth(boothModel)) do
			local voteTable = {}
			for diff, count in pairs(votingData.votes) do
				voteTable[diff] = count
			end
			self.Client.UpdateVotes:Fire(p, voteTable)
		end
	end)
end

function BoothService:KnitInit()
	DataService = Knit.GetService("DataService")
end

return BoothService
