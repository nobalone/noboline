local run = function(func) func() end
local cloneref = cloneref or function(obj) return obj end

-- Services
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local inputService = cloneref(game:GetService('UserInputService'))
local tweenService = cloneref(game:GetService('TweenService'))
local httpService = cloneref(game:GetService('HttpService'))
local collectionService = cloneref(game:GetService('CollectionService'))

local lplr = playersService.LocalPlayer
local gameCamera = workspace.CurrentCamera

-- Vape libraries
local vape = shared.vape
local entitylib = vape.Libraries.entity
local sessioninfo = vape.Libraries.sessioninfo
local targetinfo = vape.Libraries.targetinfo
local prediction = vape.Libraries.prediction

-- Game-specific table
local tsb = {}
local store = {
    character = nil,
    equipped = {
        character = '',
        style = '',
        moveset = ''
    },
    abilities = {},
    cooldowns = {},
    matchState = 0,
    stats = {
        kills = 0,
        deaths = 0,
        wins = 0,
        damage = 0
    }
}

-- Utility functions
local function notif(title, text, duration, type)
    return vape:CreateNotification(title, text, duration or 5, type or 'info')
end

local function getCharacterName()
    return lplr.Character and lplr.Character:GetAttribute('CharacterName') or 'Unknown'
end

local function getAbilityCooldown(abilityName)
    return store.cooldowns[abilityName] or 0
end

local function isAbilityReady(abilityName)
    return getAbilityCooldown(abilityName) <= 0
end

-- Initialize game systems
run(function()
    -- Find game modules
    local success, modules = pcall(function()
        return {
            Combat = replicatedStorage:FindFirstChild('Modules') and replicatedStorage.Modules:FindFirstChild('Combat'),
            Characters = replicatedStorage:FindFirstChild('Characters'),
            Moves = replicatedStorage:FindFirstChild('Moves'),
            Abilities = replicatedStorage:FindFirstChild('Abilities')
        }
    end)

    if success and modules then
        -- Store character data
        tsb.Characters = {}
        if modules.Characters then
            for _, char in modules.Characters:GetChildren() do
                if char:IsA('ModuleScript') then
                    local charData = require(char)
                    tsb.Characters[char.Name] = charData
                end
            end
        end

        -- Store moves/abilities
        tsb.Moves = {}
        if modules.Moves then
            for _, move in modules.Moves:GetChildren() do
                if move:IsA('ModuleScript') then
                    tsb.Moves[move.Name] = require(move)
                end
            end
        end

        -- Combat system
        if modules.Combat then
            tsb.Combat = require(modules.Combat)
        end
    end

    -- Session tracking
    local kills = sessioninfo:AddItem('Kills')
    local deaths = sessioninfo:AddItem('Deaths')
    local wins = sessioninfo:AddItem('Wins')
    local damage = sessioninfo:AddItem('Damage')

    -- Character tracking
    sessioninfo:AddItem('Character', 0, function()
        return getCharacterName()
    end, false)

    -- Track kills
    local function onKill(victim)
        if victim then
            kills:Increment()
            store.stats.kills += 1
        end
    end

    -- Track deaths
    local function onDeath()
        deaths:Increment()
        store.stats.deaths += 1
    end

    -- Character change detection
    if lplr.Character then
        store.character = lplr.Character
        store.equipped.character = getCharacterName()
    end

    lplr.CharacterAdded:Connect(function(char)
        store.character = char
        task.wait(0.5)
        store.equipped.character = getCharacterName()
    end)

    -- Attribute tracking for abilities
    task.spawn(function()
        while vape.Loaded do
            if entitylib.isAlive then
                -- Update cooldowns from character attributes
                for _, ability in {'Ability1', 'Ability2', 'Ability3', 'Ability4', 'Ultimate'} do
                    local cooldown = lplr.Character:GetAttribute(ability..'Cooldown')
                    if cooldown then
                        store.cooldowns[ability] = cooldown
                    end
                end

                -- Update moveset
                local moveset = lplr.Character:GetAttribute('CurrentMoveset')
                if moveset then
                    store.equipped.moveset = moveset
                end

                -- Update style
                local style = lplr.Character:GetAttribute('FightingStyle')
                if style then
                    store.equipped.style = style
                end
            end
            task.wait(0.1)
        end
    end)

    -- Cleanup
    vape:Clean(function()
        table.clear(tsb)
        table.clear(store)
    end)
end)

-- Remote finder
run(function()
    local remotes = {}
    
    local function findRemote(name)
        for _, v in replicatedStorage:GetDescendants() do
            if v:IsA('RemoteEvent') or v:IsA('RemoteFunction') then
                if v.Name:lower():find(name:lower()) then
                    return v
                end
            end
        end
    end

    -- Common remotes (adjust names based on actual game)
    remotes.Attack = findRemote('Attack')
    remotes.Ability = findRemote('Ability')
    remotes.Block = findRemote('Block')
    remotes.Dash = findRemote('Dash')
    remotes.Ultimate = findRemote('Ultimate')
    remotes.Emote = findRemote('Emote')

    tsb.Remotes = remotes
end)

-- Entity system override for TSB
run(function()
    local oldTargetCheck = entitylib.targetCheck
    
    entitylib.targetCheck = function(ent)
        if ent.NPC then return true end
        if ent.Friend then return false end
        -- TSB doesn't have teams in most modes
        return true
    end

    entitylib.getEntityColor = function(ent)
        if ent.Friend then
            return Color3.fromRGB(85, 255, 85)
        elseif ent.Target then
            return Color3.fromRGB(255, 85, 85)
        end
        return Color3.fromRGB(255, 255, 255)
    end
end)

-- Combat tracking
run(function()
    -- Track damage dealt
    local damageConnection
    
    local function trackDamage()
        -- Hook into damage events
        for _, remote in replicatedStorage:GetDescendants() do
            if remote:IsA('RemoteEvent') and remote.Name:lower():find('damage') then
                damageConnection = remote.OnClientEvent:Connect(function(...)
                    local args = {...}
                    -- Adjust based on actual damage event structure
                    if args[1] and typeof(args[1]) == 'number' then
                        store.stats.damage += args[1]
                    end
                end)
            end
        end
    end

    task.spawn(trackDamage)

    vape:Clean(function()
        if damageConnection then
            damageConnection:Disconnect()
        end
    end)
end)

-- Helper functions for abilities
tsb.useAbility = function(abilityKey)
    if not entitylib.isAlive then return false end
    
    local cooldown = getAbilityCooldown('Ability'..abilityKey)
    if cooldown > 0 then return false end
    
    -- Simulate key press
    local key = Enum.KeyCode['Key'..abilityKey]
    vim:SendKeyEvent(true, key, false, game)
    task.wait(0.05)
    vim:SendKeyEvent(false, key, false, game)
    
    return true
end

tsb.useUltimate = function()
    if not entitylib.isAlive then return false end
    
    local ultReady = lplr.Character:GetAttribute('UltimateReady')
    if not ultReady then return false end
    
    vim:SendKeyEvent(true, Enum.KeyCode.V, false, game)
    task.wait(0.05)
    vim:SendKeyEvent(false, Enum.KeyCode.V, false, game)
    
    return true
end

tsb.performCombo = function(sequence)
    if not entitylib.isAlive then return end
    
    for _, action in sequence do
        if action.type == 'M1' then
            mouse1click()
        elseif action.type == 'Ability' then
            tsb.useAbility(action.key)
        elseif action.type == 'Dash' then
            vim:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
            task.wait(0.05)
            vim:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
        end
        
        if action.delay then
            task.wait(action.delay)
        end
    end
end

tsb.getCharacterStats = function()
    if not entitylib.isAlive then return nil end
    
    return {
        character = store.equipped.character,
        moveset = store.equipped.moveset,
        style = store.equipped.style,
        health = lplr.Character:GetAttribute('Health') or 100,
        maxHealth = lplr.Character:GetAttribute('MaxHealth') or 100,
        stamina = lplr.Character:GetAttribute('Stamina') or 100,
        ultimateReady = lplr.Character:GetAttribute('UltimateReady') or false
    }
end

-- Remove irrelevant modules
for i, v in vape.Modules do
    if v.Category == 'Minigames' or i:find('Bed') or i:find('bed') then
        vape:Remove(i)
    end
end

-- Example modules starter
run(function()
    local AutoBlock
    local Range
    local Targets
    
    AutoBlock = vape.Categories.Combat:CreateModule({
        Name = 'AutoBlock',
        Function = function(callback)
            if callback then
                AutoBlock:Clean(runService.Heartbeat:Connect(function()
                    if entitylib.isAlive then
                        local plr = entitylib.EntityPosition({
                            Range = Range.Value,
                            Part = 'RootPart',
                            Players = Targets.Players.Enabled,
                            NPCs = Targets.NPCs.Enabled
                        })
                        
                        local blocking = lplr.Character:GetAttribute('Blocking')
                        
                        if plr and not blocking then
                            -- Start blocking
                            vim:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                        elseif not plr and blocking then
                            -- Stop blocking
                            vim:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                        end
                    end
                end))
            else
                -- Release block key
                vim:SendKeyEvent(false, Enum.KeyCode.F, false, game)
            end
        end,
        Tooltip = 'Automatically blocks when enemies are nearby'
    })
    
    Targets = AutoBlock:CreateTargets({
        Players = true,
        NPCs = false
    })
    
    Range = AutoBlock:CreateSlider({
        Name = 'Range',
        Min = 5,
        Max = 30,
        Default = 15,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
end)

run(function()
    local Sprint
    
    Sprint = vape.Categories.Combat:CreateModule({
        Name = 'Sprint',
        Function = function(callback)
            if callback then
                Sprint:Clean(runService.Heartbeat:Connect(function()
                    if entitylib.isAlive and entitylib.character.Humanoid.MoveDirection.Magnitude > 0 then
                        local sprinting = lplr.Character:GetAttribute('Sprinting')
                        if not sprinting then
                            vim:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
                            task.wait(0.05)
                            vim:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
                        end
                    end
                end))
            end
        end,
        Tooltip = 'Automatically sprint when moving'
    })
end)

-- Export
_G.TSB = tsb
_G.TSBStore = store
