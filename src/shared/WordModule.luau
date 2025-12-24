local WordModule = {}

WordModule.Difficulties = {
	Easy = {
		name = "Easy",
		description = "Simple words",
		words = {
			"apple","ball","cat","dog","egg","fish","goat","hat","ink","jam",
			"kite","lamp","map","nose","owl","pen","queen","rope","sun","tree",
			"umbrella","van","wall","xray","yak","zebra","ant","bird","car","door",
			"ear","fog","gum","hill","ice","jelly","key","leaf","milk","nest",
			"pig","quilt","ring","sock","toy","urn","vase","wind","yard","zip",
			"ace","bag","cup","dot","fan","gap","hen","island","jar","kid",
			"log","mud","net","oak","pond","quiz","rat","seat","tap","vet",
			"wig","yarn","zap","bed","coin","drum","edge","flag","glass","home",
			"iron","lion","moon","note","oval","park","road","ship","time","unit",
			"vote","wish","axe","zero","arrow","brush","clown","desk","engine","fruit",
			"grape","heart","isle","joke","knife","light","mouse","north","ocean","piano",
			"quiet","river","sleep","train","under","value","water","yellow","zoom","baby",
			"child","doll","earth","friend","garden","house","juice","kettle","ladder","market",
			"needle","orange","pencil","rocket","school","table","uncle","victory","window",
		},
	},
	Medium = {
		name = "Medium",
		description = "Common words with capitals",
		words = {
			"Hello","World","Apple","Cat","Dog","Fish","Lamp","Tree",
			"Sun","Moon","Star","Bird","Car","Door","Key","Book",
			"Phone","Water","Fire","Earth","Wind","Rain","Snow","Cloud",
			"House","Road","Path","Town","City","Park","Lake","River",
			"Mountain","Valley","Forest","Desert","Ocean","Beach","Island",
			"Bridge","Tower","Castle","Garden","School","Church","Store",
			"Market","Office","Hotel","Airport","Station","Harbor",
			"Today","Monday","Tuesday","Wednesday","Thursday","Friday",
			"Saturday","Sunday","Morning","Evening","Night","Afternoon",
			"January","March","April","Summer","Winter","Spring","Autumn",
			"Amazing","Brilliant","Creative","Delightful","Excellent",
			"Fantastic","Gorgeous","Helpful","Incredible","Joyful",
			"Happy","Funny","Quick","Slow","Big","Small","Tall","Short",
			"Red","Blue","Green","Yellow","Orange","Purple","Pink","Black",
		},
	},
	Hard = {
		name = "Hard",
		description = "Long challenging words",
		words = {
			"extraordinary","unbelievable","sophisticated","congratulations",
			"mediterranean","pharmaceutical","entrepreneurship","consciousness",
			"miscellaneous","unprecedented","simultaneously","enthusiastically",
			"responsibility","unfortunately","approximately","circumstances",
			"acknowledgment","accomplishment","disappointment","encouragement",
			"entertainment","establishment","fundamentally","independently",
			"manufactured","occasionally","opportunities","participating",
			"qualification","recommendation","strengthening","transformation",
			"understanding","visualization","characteristics","communication",
			"determination","experimentation","implementation","investigation",
			"knowledgeable","organizational","predominantly","revolutionary",
			"sustainability","technological","uncomfortable","unpredictable",
			"administration","archaeological","autobiography","collaboration",
			"comprehensive","Configuration","controversial","demonstration",
			"differentiation","electromagnetic","environmental","infrastructure",
			"interpretation","manufacturing","oceanographic","philosophical",
			"psychological","representative","straightforward","thermodynamics",
		},
	},
	Hardcore = {
		name = "Hardcore",
		description = "Complex words & phrases",
		words = {
			"Extraordinarily!","Unbelievable?","Sophisticated.","Congratulations!",
			"Mediterranean?","Pharmaceutical.","Entrepreneurship!","Consciousness?",
			"Miscellaneous.","Unprecedented!","Simultaneously?","Enthusiastically.",
			"Responsibility!","Unfortunately?","Approximately.","Circumstances!",
			"Acknowledgment?","Accomplishment.","Disappointment!","Encouragement?",
			"Entertainment.","Establishment!","Fundamentally?","Independently.",
			"Manufactured!","Occasionally?","Opportunities.","Participating!",
			"Qualification?","Recommendation.","Strengthening!","Transformation?",
			"Understanding.","Visualization!","Characteristics?","Communication.",
			"Determination!","Experimentation?","Implementation.","Investigation!",
			"Knowledgeable?","Organizational.","Predominantly!","Revolutionary?",
			"Sustainability.","Technological!","Uncomfortable?","Unpredictable.",
			"What's-his-name?","Self-conscious!","Well-established.","High-quality!",
		},
	},
	Numbers = {
		name = "Numbers",
		description = "Words with numbers",
		words = {
			"abc123","hello1","world2","test123","user456","pass789",
			"code42","level99","player1","score100","game2024","win500",
			"high5","lucky7","team10","room404","error500","version2",
			"update3","patch14","build99","alpha1","beta2","release3",
			"item001","quest50","stage12","round25","match77","point1000",
			"rank1st","top10","best100","pro360","elite99","master5000",
			"speed120","power9000","health100","mana50","gold999","exp1000",
			"day1","week52","year2025","hour24","min60","sec30",
			"file01","data256","byte1024","mega100","giga500","tera1",
			"id12345","pin4321","key9876","lock1234","safe5678","vault0000",
		},
	},
	Brainrot = {
		name = "Brainrot",
		description = "Internet memes",
		words = {
			"Skibidi","Rizz","Gyatt","Ohio","Sigma","Alpha","Beta","Bussin",
			"Slay","Yeet","Vibe","Drip","Sus","Cringe","Based","Poggers",
			"Sheesh","Bruh","Fanum","Tax","Mewing","Looksmaxxing",
		    "Aura","Delulu","Slay","Understood","Assignment",
			"Ate","Left","No","Crumbs","Main","Character","Energy","Vibes",
			"Hits","Different","Lowkey","Highkey","Lowkey","Snatched",
			"Glow","Up","Side","Eye","Ick","Beige","Flag","Oof","Yikes",
			"Bestie","Rent","Free","Living","Stan","Iconic","Legendary",
		    "Wagwan","Mandem","Ting","Bare",
			"Lirili","Larila","Bombardiro","Crocodilo","Cappuccino","Assassino",
			"Brr","Patapim","Ballerina","Cappuccina","Boneca","Ambalabu",
			"Chimpanzini","Bananini","Tralalero","Tralala","Tung","Sahur",
			"Bobrito","Bandito","Bombombini","Gusini","Frigo","Camello",
			"Saturno","Saturnita","Trippi","Troppi","Frulli","Frulla",
			"Trulimero","Trulicina","Blueberrinni","Octopussini","Bicus","Bombicus",
			"Burbaloni","Lulilolli","Girafa","Celestre","Ta","Default",
			"Cacto","Hipopotamo","Bananita","Dolphinita","Udin","Din",
		},
	},
}

WordModule.Words = WordModule.Difficulties.Easy.words

function WordModule.GetRandomWord(minLength, maxLength)
	minLength = minLength or 1
	maxLength = maxLength or math.huge

	local pool = {}
	for _, word in ipairs(WordModule.Words) do
		local l = #word
		if l >= minLength and l <= maxLength then
			table.insert(pool, word)
		end
	end

	if #pool == 0 then
		return nil
	end

	return pool[math.random(1, #pool)]
end

function WordModule.GetRandomWordFromDifficulty(difficulty: string, minLength: number?, maxLength: number?): string?
	local diffData = WordModule.Difficulties[difficulty]
	if not diffData then
		diffData = WordModule.Difficulties.Easy
	end

	minLength = minLength or 1
	maxLength = maxLength or math.huge

	local pool = {}
	for _, word in ipairs(diffData.words) do
		local l = #word
		if l >= minLength and l <= maxLength then
			table.insert(pool, word)
		end
	end

	if #pool == 0 then
		return nil
	end

	return pool[math.random(1, #pool)]
end

function WordModule.GenerateWordsFromDifficulty(difficulty: string, count: number): {string}
	local diffData = WordModule.Difficulties[difficulty]
	if not diffData then
		diffData = WordModule.Difficulties.Easy
	end

	local words = {}
	local wordList = diffData.words

	for _ = 1, count do
		local word = wordList[math.random(1, #wordList)]
		table.insert(words, word)
	end

	return words
end

function WordModule.GetDifficultyInfo(difficulty: string): {name: string, description: string}?
	local diffData = WordModule.Difficulties[difficulty]
	if diffData then
		return {name = diffData.name, description = diffData.description}
	end
	return nil
end

function WordModule.GetAllDifficulties(): {string}
	return {"Easy", "Medium", "Hard", "Hardcore", "Numbers", "Brainrot"}
end

function WordModule.GetRandomDifficulties(count: number): {string}
	local others = {"Medium", "Hard", "Hardcore", "Numbers", "Brainrot"}
	
	for i = #others, 2, -1 do
		local j = math.random(1, i)
		others[i], others[j] = others[j], others[i]
	end
	
	local result = {"Easy"}
	for i = 1, math.min(count - 1, #others) do
		table.insert(result, others[i])
	end

	return result
end

function WordModule.GetByLength(length)
	local out = {}
	for _, word in ipairs(WordModule.Words) do
		if #word == length then
			table.insert(out, word)
		end
	end
	return out
end

function WordModule.GetAll()
	local copy = {}
	for i, w in ipairs(WordModule.Words) do
		copy[i] = w
	end
	return copy
end

function WordModule.Count()
	return #WordModule.Words
end

return WordModule
