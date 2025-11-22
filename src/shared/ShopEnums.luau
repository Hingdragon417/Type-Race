local WordModule = {}

-- Simple list of easy words (common, short, kid-friendly)
WordModule.Words = {
    "apple","ball","cat","dog","egg","fish","goat","hat","ink","jam",
    "kite","lamp","map","nose","owl","pen","queen","rope","sun","tree",
    "umbrella","van","wall","xray","yak","zebra","ant","bird","car","door",
    "ear","fog","gum","hill","ice","jelly","key","leaf","milk","nest",
    "owl","pig","quilt","ring","sock","toy","urn","vase","wind","yard",
    "zip","ace","bag","cup","dot","ear","fan","gap","hen","island",
    "jar","kid","log","mud","net","oak","pond","quiz","rat","seat",
    "tap","urn","vet","wig","yarn","zap","bed","coin","drum","edge",
    "flag","glass","home","iron","jam","kite","lion","moon","note","oval",
    "park","quiz","road","ship","time","unit","vote","wish","axe","yak",
    "zero","arrow","brush","clown","desk","engine","fruit","grape","heart","isle",
    "joke","knife","light","mouse","north","ocean","piano","quiet","river","sleep",
    "train","under","value","water","xylophone","yellow","zoom","baby","child","doll",
    "earth","friend","garden","house","island","juice","kettle","ladder","market","needle",
    "orange","pencil","queen","rocket","school","table","uncle","victory","window","yard",
}

-- Return a random word; optional length filters
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
    -- Return a shallow copy to prevent accidental modification
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
