local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)


Knit.OnStart():andThen(function()
	local DataService = Knit.GetService("DataService")
	local ReplicatedAssets = ReplicatedStorage:WaitForChild("Assets")
	local WinStreakTemplate = ReplicatedAssets:WaitForChild("Winstreak")

	local function UpdateWinCount(winStreakUI, newValue)
		if winStreakUI and winStreakUI:FindFirstChild("TextLabel") then
			if newValue == 0 then
				winStreakUI.Enabled = false
				winStreakUI.TextLabel.Text = ""
				return
			else
				winStreakUI.Enabled = true
			end
			winStreakUI.TextLabel.Text = "🔥 " .. tostring(newValue)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		local winStreakUI
		
		local function startWinstreakMonitor()
			task.spawn(function()
				while player.Parent == Players do
					if winStreakUI then
						local session = DataService.waitForSession(player, 5)
						if session and session.Data then
							local winStreak = session.Data.Winstreak or 0
							UpdateWinCount(winStreakUI, winStreak)
						end
					end
					task.wait(0.5)
				end
			end)
		end
		
		local function onCharAdded(character)
			local head = character:FindFirstChild("Head")
			if not head then
				character.ChildAdded:Wait()
				head = character:FindFirstChild("Head")
			end
			if head then
				winStreakUI = WinStreakTemplate:Clone()
				winStreakUI.Parent = head

				local session = DataService.waitForSession(player, 10)
				local winStreak = 0
				if session and session.Data then
					winStreak = session.Data.Winstreak or 0
				end
				UpdateWinCount(winStreakUI, winStreak)
			end
		end
		if player.Character then
			onCharAdded(player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			onCharAdded(character)
		end)
		
		startWinstreakMonitor()

		local leaderstats = player:WaitForChild("leaderstats", 10)
		if not leaderstats then
			warn("Leaderstats not found for player:", player.Name)
			return
		end

		local WinsStat = leaderstats:WaitForChild("Wins", 10)
		if not WinsStat then
			warn("Wins stat not found in leaderstats for player:", player.Name)
			return
		end

		WinsStat.Changed:Connect(function(newValue)
			if not winStreakUI then
				if not player.Character then
					return
				end
				local head = player.Character:FindFirstChild("Head")
				if not head then
					player.Character.ChildAdded:Wait()
					head = player.Character:FindFirstChild("Head")
				end
				if not head then
					return
				end
				winStreakUI = WinStreakTemplate:Clone()
				winStreakUI.Parent = head
			end

			local session = DataService.waitForSession(player, 10)
			local winStreak = 0
			if session and session.Data then
				winStreak = session.Data.Winstreak or 0
			end
			UpdateWinCount(winStreakUI, winStreak)
		end)


	end)
end)

return {}
