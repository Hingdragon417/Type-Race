local function deepCopy(t:table)
	local copy = {}
	for k, v in pairs(t) do
		if type(v) == "table" then
			copy[k] = deepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Assets = ReplicatedStorage:WaitForChild("Assets")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.Knit)

local DataService

local LeaderboardService = Knit.CreateService({
	Name = "LeaderboardService",
	Client = {},
})

local Leaderboards = {
	maxEntries = 10,
	SavedStats = {
		"Winstreak",
		"Wins"
	},
	StatColours = {
		Winstreak = Color3.fromRGB(255, 145, 0),
		Wins = Color3.fromRGB(42, 126, 194),
	},
	updateCooldowns = {},
	cooldownTime = 10,
	CachedUi = {},
	CachedPlayerStatPeaks = {},
	CachedLeaderboardData = {},
	CachedLowestValues = {}
}

local DataModule = {}

local LeaderboardData: DataStore = DataStoreService:GetDataStore("LeaderboardData_TEST3")

function DataModule:GetLeaderboardData(): any
	local success, data = pcall(function()
		local allData = LeaderboardData:GetAsync("Data")
        return allData or nil
	end)

	if success then
		return data
	else
		return nil
	end
end

function DataModule:GetStatData(statName: string): any
	local success, data = pcall(function()
		local allData = LeaderboardData:GetAsync("Data")
        return allData and allData[statName] or nil
	end)

	if success then
		return data
	else
		return nil
	end
end

function DataModule:SaveCache()
	local success, err = pcall(function()
		LeaderboardData:SetAsync("Data", Leaderboards.CachedLeaderboardData)
	end)

	if not success then
		-- intentionally left blank
	end

	if success then
		-- intentionally left blank
	end
end

local CacheUtil = {
	CachedFrameTemplate = nil
}

function CacheUtil:GetFrameTemplate(): Frame
	local template: Frame? = CacheUtil.CachedFrameTemplate
	if not template then
		template = Assets:WaitForChild("UIAssets"):WaitForChild("LeaderboardTemplate")
		CacheUtil.CachedFrameTemplate = template
	end
	return template:Clone()
end

function CacheUtil:isValueWorthy(player: Player, statName: string, value: number): boolean
	local leaderboardCache = Leaderboards.CachedLeaderboardData

	if not leaderboardCache then
		error("Leaderboard cache not initialized")
		return false
	end

	local statEntries = leaderboardCache[statName]
	if not statEntries or (statEntries and not next(statEntries)) then
		return true
	end

	local lowestValue: number = math.huge

	local cachedLowestValue: number? = Leaderboards.CachedLowestValues[statName]
	if cachedLowestValue then
		lowestValue = cachedLowestValue
	end

	if not cachedLowestValue then
		for _, entry in statEntries do
			local userId: number = entry[1]
			if not userId or type(userId) ~= "number" then
				continue
			end
			local entryValue: number = entry[2]
			if not entryValue or type(entryValue) ~= "number" then
				continue
			end
			if entryValue < lowestValue then
				lowestValue = entryValue
			end
		end
	end

	if not lowestValue or lowestValue == math.huge then
		return true
	end

	if lowestValue and not cachedLowestValue then
		Leaderboards.CachedLowestValues[statName] = lowestValue
	end

	local isIncludedValue = value > lowestValue

	if not isIncludedValue then
		if #statEntries >= Leaderboards.maxEntries then
			return false
		else
			return true
		end
	else
		return true
	end
end

function CacheUtil:isPlayerOnLeaderboard(playerId: number, statName: string): (boolean, number?)
	local leaderboardCache = Leaderboards.CachedLeaderboardData

	if not leaderboardCache then
		error("Leaderboard cache not initialized")
		return false, nil
	end

	local statEntries = leaderboardCache[statName]
	if not statEntries or (statEntries and not next(statEntries)) then
		return false, nil
	end

	for index, entry in ipairs(statEntries) do
		local userId: number = entry[1]
		if userId == playerId then
			return true, index
		end
	end

	return false, nil
end

local UI = {}

local leaderboardFolder: Folder = workspace:WaitForChild("Leaderboards")

function UI:GetLeaderboardUi(statName: string): SurfaceGui?
	local cachedUi: SurfaceGui? = Leaderboards.CachedUi[statName]
	if cachedUi then
		return cachedUi
	end

	local statModel: Model? = leaderboardFolder:FindFirstChild(statName)
	if not statModel then
		return nil
	end

	local ScreenPart: Part = statModel:FindFirstChild("Screen")
	if not ScreenPart then
		return nil
	end

	local surfaceGui: SurfaceGui = ScreenPart:FindFirstChild("SurfaceGui")
	if not surfaceGui then
		return nil
	end

	Leaderboards.CachedUi[statName] = surfaceGui

	return surfaceGui
end

local function commentNumber(numberValue: number): string
	local absValue = math.abs(numberValue)
	if absValue >= 1e9 then
		return string.format("%.1fB", numberValue / 1e9)
	elseif absValue >= 1e6 then
		return string.format("%.1fM", numberValue / 1e6)
	elseif absValue >= 1e3 then
		return string.format("%.1fK", numberValue / 1e3)
	else
		return tostring(numberValue)
	end
end

function UI.updateLeaderboardUi(statName: string?)
	local leaderboardCache = Leaderboards.CachedLeaderboardData
	if not leaderboardCache then
		error("Leaderboard cache not initialized")
		return
	end

	local statsToUpdate: { string } = {}

	if statName then
		table.insert(statsToUpdate, statName)
	else
		statsToUpdate = Leaderboards.SavedStats
	end

	for _, stat in ipairs(statsToUpdate) do
		local statEntries = leaderboardCache[stat]
		if not statEntries then
			continue
		end

		local surfaceGui: SurfaceGui? = UI:GetLeaderboardUi(stat)
		if not surfaceGui then
			continue
		end
		
		local frame: ScrollingFrame = surfaceGui:FindFirstChildOfClass("ScrollingFrame")
		if not frame then
			continue
		end

		local existingEntries = {}

		for _, element in frame:GetChildren() do
			if element:IsA("Frame") then
				table.insert(existingEntries, element)
			end
		end

		for _, child in existingEntries do
			child:Destroy()
		end

		for index, entry in ipairs(statEntries) do
			local userId: number = entry[1]
			local value: number = entry[2]

			local playerName = "Unknown"
			local player = Players:GetPlayerByUserId(userId)
			if player then
				playerName = player.Name
			else
				local success, fetchedName = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				if success and fetchedName then
					playerName = fetchedName
				end
			end

			local entryFrame: Frame = CacheUtil:GetFrameTemplate()
			entryFrame.Name = "Entry_" .. tostring(index)

			local RankLabel: TextLabel = entryFrame:WaitForChild("Rank")
			local UsernameLabel: TextLabel = entryFrame:WaitForChild("Username")
			local ScoreLabel: TextLabel = entryFrame:WaitForChild("Score")

			local rankPrefix = "#"
			
			local GoalRankText = rankPrefix .. tostring(index)

			local GoalUsernameText = playerName
			local GoalScoreText = tostring(commentNumber(value))

			local PlayerNameTooLong = false
			if #playerName > 15 then
				PlayerNameTooLong = true
			end
			if PlayerNameTooLong then
				GoalUsernameText = playerName:sub(1, 12) .. "..."
			end

			RankLabel.Text = GoalRankText
			UsernameLabel.Text = GoalUsernameText
			ScoreLabel.Text = GoalScoreText

			local statColor = Leaderboards.StatColours[stat] or Color3.fromRGB(255, 255, 255)
			RankLabel.BackgroundColor3 = statColor
			ScoreLabel.BackgroundColor3 = statColor
			UsernameLabel.BackgroundColor3 = statColor

			entryFrame.Parent = frame

			entryFrame.LayoutOrder = index
		end
	end
end

function Leaderboards:ValidatePlayerStatPeak(player: Player, statName: string, newValue: number)
	local highestPeak: number = Leaderboards.CachedPlayerStatPeaks[player.UserId] and Leaderboards.CachedPlayerStatPeaks[player.UserId][statName] or 0
	if newValue > highestPeak then
		Leaderboards.CachedPlayerStatPeaks[player.UserId] = Leaderboards.CachedPlayerStatPeaks[player.UserId] or {}
		Leaderboards.CachedPlayerStatPeaks[player.UserId][statName] = newValue
		return true
	end
	return false
end

function LeaderboardService.onServerStart()
	local leaderboardData = DataModule:GetLeaderboardData()

	if leaderboardData then
		Leaderboards.CachedLeaderboardData = leaderboardData
	elseif not leaderboardData then
		leaderboardData = {}
		for _, statName in ipairs(Leaderboards.SavedStats) do
			leaderboardData[statName] = {}
		end
		Leaderboards.CachedLeaderboardData = leaderboardData
		DataModule:SaveCache()
	end

	UI.updateLeaderboardUi()

	for _, statLeaderboard: Model in leaderboardFolder:GetChildren() do
		if statLeaderboard:IsA("Model") and table.find(Leaderboards.SavedStats, statLeaderboard.Name) then
			local surfaceUi: SurfaceGui? = UI:GetLeaderboardUi(statLeaderboard.Name)
			if surfaceUi then
				local TopTextLabel: TextLabel = surfaceUi:FindFirstChild("Title")
				if TopTextLabel then
					local statColor = Leaderboards.StatColours[statLeaderboard.Name] or Color3.fromRGB(255, 255, 255)
					TopTextLabel.BackgroundColor3 = statColor
					TopTextLabel.Text = statLeaderboard.Name
				end
			end
		end
	end

	Players.PlayerAdded:Connect(function(player: Player)
		local session = DataService.waitForSession(player)
		if not session or not session.Data then
			return
		end

		for _, statName in ipairs(Leaderboards.SavedStats) do
			local playerStatValue = session.Data[statName]
			if playerStatValue and type(playerStatValue) == "number" then
				Leaderboards:ValidatePlayerStatPeak(player, statName, playerStatValue)
			end
		end
	end)

	local currentPlayers = Players:GetPlayers()
	for _, player in ipairs(currentPlayers) do
		local session = DataService.waitForSession(player)
		if not session or not session.Data then
			return
		end

		for _, statName in ipairs(Leaderboards.SavedStats) do
			local playerStatValue = session.Data[statName]
			if playerStatValue and type(playerStatValue) == "number" then
				Leaderboards:ValidatePlayerStatPeak(player, statName, playerStatValue)
			end
		end
	end

	MessagingService:SubscribeAsync("LeaderboardUpdated", function(message)
		local msgData = message.Data
		if msgData and type(msgData) == "table" then
			local playerId: number? = msgData.playerId
			if not playerId or type(playerId) ~= "number" then
				return
			end
			local player: Player? = Players:GetPlayerByUserId(playerId)
			if player then
				return
			end
			player = nil
			local statName: string? = msgData.statName
			local newValue: number? = msgData.playerValue
			local playerEntryIndex: number? = msgData.playerEntryIndex
			if statName and type(statName) == "string" then
				local deepCopiedCache = deepCopy(Leaderboards.CachedLeaderboardData)
				if not deepCopiedCache[statName] then
					deepCopiedCache[statName] = {}
				end
				
				local statEntries = deepCopiedCache[statName]
				
				local isOnLeaderboard, existingIndex = CacheUtil:isPlayerOnLeaderboard(playerId, statName)
				if isOnLeaderboard and existingIndex then
					if newValue and type(newValue) == "number" then
						statEntries[existingIndex] = { playerId, newValue }
					end
				else
					if playerEntryIndex and type(playerEntryIndex) == "number" and newValue and type(newValue) == "number" then
						if #statEntries+1 > Leaderboards.maxEntries then
							table.remove(statEntries, #statEntries)
						end
						table.insert(statEntries, playerEntryIndex, { playerId, newValue })
					end
				end

				table.sort(statEntries, function(a, b)
					return a[2] > b[2]
				end)

				Leaderboards.CachedLeaderboardData = deepCopiedCache

				if playerEntryIndex == #statEntries then
					if newValue and type(newValue) == "number" then
						Leaderboards.CachedLowestValues[statName] = newValue
					end
				end

				DataModule:SaveCache()
				UI.updateLeaderboardUi(statName)
			end
		else
			return
		end
	end)
end

function LeaderboardService.onPlayerDataChange(player: Player, statName: string, newValue: number)
	if not table.find(Leaderboards.SavedStats, statName) then
		return
	end

	local s: boolean = Leaderboards:ValidatePlayerStatPeak(player, statName, newValue)
	if not s then
		return
	end

	local worthy: boolean = CacheUtil:isValueWorthy(player, statName, newValue)
	if not worthy then
		return
	end

	local activePlayerCooldown = Leaderboards.updateCooldowns[player.UserId] and Leaderboards.updateCooldowns[player.UserId][statName]
	if activePlayerCooldown then
		local timeSinceLastUpdate = os.time() - activePlayerCooldown
		if timeSinceLastUpdate < Leaderboards.cooldownTime then
			return
		end
	end

	Leaderboards.updateCooldowns[player.UserId] = Leaderboards.updateCooldowns[player.UserId] or {}
	Leaderboards.updateCooldowns[player.UserId][statName] = os.time()

	LeaderboardService.onPlayerWorthy(player, statName, newValue)
end

function LeaderboardService.onPlayerLeaderboardDataChanged(player: Player, statName: string, newValue: number, playerEntryIndex: number?)
	local leaderboardCache = Leaderboards.CachedLeaderboardData
	if not leaderboardCache then
		error("Leaderboard cache not initialized")
		return
	end

	local deepCopiedCache = deepCopy(leaderboardCache)

	local statEntries = deepCopiedCache[statName]
	if not statEntries then
		deepCopiedCache[statName] = {}
		statEntries = deepCopiedCache[statName]
	end

	local isOnLeaderboard, existingIndex = CacheUtil:isPlayerOnLeaderboard(player.UserId, statName)
	if isOnLeaderboard and existingIndex then
		statEntries[playerEntryIndex] = { player.UserId, newValue }
	else
		if #statEntries+1 > Leaderboards.maxEntries then
			table.remove(statEntries, #statEntries)
		end
		table.insert(statEntries, playerEntryIndex, { player.UserId, newValue })
	end

	table.sort(statEntries, function(a, b)
		return a[2] > b[2]
	end)

	if playerEntryIndex == #statEntries then
		Leaderboards.CachedLowestValues[statName] = newValue
	end

	Leaderboards.CachedLeaderboardData = deepCopiedCache
	DataModule:SaveCache()

	UI.updateLeaderboardUi()

	local success, err = pcall(function()
		MessagingService:PublishAsync("LeaderboardUpdated", {
			playerId = player.UserId,
			statName = statName,
			playerValue = newValue,
			playerEntryIndex = playerEntryIndex,
		})
	end)

	if not success then
		-- intentionally left blank
	end
end

function LeaderboardService.onPlayerWorthy(player: Player, statName: string, newValue: number)
	local leaderboardCache = Leaderboards.CachedLeaderboardData
	if not leaderboardCache then
		error("Leaderboard cache not initialized")
		return
	end

	local statEntries = leaderboardCache[statName]
	if not statEntries then
		leaderboardCache[statName] = {}
		statEntries = leaderboardCache[statName]
	end

	local playerEntryIndex: number = 0

	local isOnLeaderboard, existingIndex = CacheUtil:isPlayerOnLeaderboard(player.UserId, statName)
	if isOnLeaderboard and existingIndex then
		playerEntryIndex = existingIndex
	else
		for index, entry in ipairs(statEntries) do
			local entryValue: number = entry[2]
			if newValue > entryValue then
				playerEntryIndex = index
				break
			end
		end
		if not playerEntryIndex or playerEntryIndex == 0 then
			local targetSlot = #statEntries + 1
			if targetSlot > Leaderboards.maxEntries then
				return
			end
			playerEntryIndex = targetSlot
		end
	end

	if isOnLeaderboard and existingIndex and statEntries[existingIndex] then
		local existingValue: number = statEntries[existingIndex][2]
		if newValue <= existingValue then
			return
		end
	end

	LeaderboardService.onPlayerLeaderboardDataChanged(player, statName, newValue, playerEntryIndex)
end

function LeaderboardService:KnitStart()
	LeaderboardService.onServerStart()
end

function LeaderboardService:KnitInit()
	DataService = Knit.GetService("DataService")
end

return LeaderboardService
