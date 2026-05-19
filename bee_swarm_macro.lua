--[[
    Bee Swarm Simulator — Full Smart Macro
    ──────────────────────────────────────
    Версія: 1.0.0
    Завантаження одним рядком:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/USER/REPO/main/bee_swarm_macro.lua"))()

    Сканує гру (workspace/PlayerGui), не використовує hardcoded координати.

    Можливості:
      • Авто-фарм поля + збір токенів по карті
      • Авто-конвертація на hive
      • Обхід усіх dispenser'ів
      • Авто-використання баффів (Field Boost, Gummy Mask, Pineapple Mask, Star Jelly)
      • Виявлення Vicious Bee / Mondo Chick / Aphid / Werewolf → втеча на hive
      • Авто-планетери (збір і повторна установка)
      • Збір мобів (spider, ladybug, mantis, scorpion, rhino beetle)
      • Бос-цикл (King Beetle, Tunnel Bear, Stump Snail, Werewolf, Coconut Crab)
      • Авто-крафт у Blender / Sticker Printer (claim готових)

    Гарячі клавіші:
      K — стоп                P — пауза               H — повернутись на hive
      B — бос-режим вкл/викл  M — фарм мобів вкл/викл J — крафт-цикл одразу
--]]

------------------------------------------------------------
-- СЕРВІСИ
------------------------------------------------------------
local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local RS               = game:GetService("ReplicatedStorage")
local UIS              = game:GetService("UserInputService")
local VirtualUser      = game:GetService("VirtualUser")
local RunService       = game:GetService("RunService")
local GuiService       = game:GetService("GuiService")
local PathfindingService = game:GetService("PathfindingService")

local LP = Players.LocalPlayer

------------------------------------------------------------
-- ДЕТЕКТОР ПЛАТФОРМИ
------------------------------------------------------------
local PLATFORM = {
    Touch    = UIS.TouchEnabled,
    Keyboard = UIS.KeyboardEnabled,
    Mouse    = UIS.MouseEnabled,
    Gamepad  = UIS.GamepadEnabled,
}
PLATFORM.Mobile  = PLATFORM.Touch and not PLATFORM.Keyboard
PLATFORM.Tablet  = PLATFORM.Touch and PLATFORM.Mouse  -- iPad / Surface
PLATFORM.Desktop = PLATFORM.Keyboard and PLATFORM.Mouse and not PLATFORM.Mobile

-- Розмір екрана (для адаптивного UI)
local function getViewport()
    local cam = Workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1280, 720)
end
local VP = getViewport()
local IS_SMALL_SCREEN = VP.X < 900 or PLATFORM.Mobile

print(string.format("[BSS Macro] Platform: %s | Viewport: %dx%d",
    PLATFORM.Mobile and "MOBILE" or PLATFORM.Tablet and "TABLET" or "DESKTOP",
    VP.X, VP.Y))

------------------------------------------------------------
-- DEBUG TOAST (з'являється одразу після виконання скрипта)
------------------------------------------------------------
local function debugToast(text, color, duration)
    local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui")
    local sg = Instance.new("ScreenGui")
    sg.Name = "BSSDebugToast_" .. tostring(math.random(1,99999))
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 99999
    sg.IgnoreGuiInset = true
    sg.Parent = pg

    -- Адаптивна ширина (на телефоні екран маленький)
    local cam = Workspace.CurrentCamera
    local screenW = cam and cam.ViewportSize.X or 1280
    local toastW = math.min(400, screenW - 40)

    local lbl = Instance.new("TextLabel", sg)
    lbl.Size = UDim2.new(0, toastW, 0, 50)
    lbl.Position = UDim2.new(0.5, -toastW/2, 0, 100)
    lbl.BackgroundColor3 = color or Color3.fromRGB(60, 180, 100)
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 14
    lbl.TextWrapped = true
    lbl.Text = text
    lbl.ZIndex = 999
    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)

    task.delay(duration or 4, function() sg:Destroy() end)
end

debugToast("🐝 BSS Macro: СКРИПТ ЗАПУЩЕНО", Color3.fromRGB(60, 180, 100), 3)
print("[BSS Macro] Script execution started")

local function getChar()
    local c = LP.Character or LP.CharacterAdded:Wait()
    return c, c:WaitForChild("HumanoidRootPart"), c:WaitForChild("Humanoid")
end
local char, hrp, hum = getChar()
LP.CharacterAdded:Connect(function()
    task.wait(0.5); char, hrp, hum = getChar()
end)

LP.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

------------------------------------------------------------
-- НАЛАШТУВАННЯ
------------------------------------------------------------
local CFG = {
    PreferredField   = nil,
    UseTokens        = true,
    TokenRadius      = 250,
    BagFullThreshold = 0.95,
    DoDispensers     = true,
    DoBuffs          = true,
    DoPlanters       = true,
    DoMobs           = true,
    -- Нові:
    DoQuests         = true,            -- авто-збирання нагород від ведмедів
    DoSprouts        = true,            -- садити та збирати sprout'и
    DoWealthClock    = true,            -- claim Wealth Clock щодня
    DoMemoryMatch    = true,            -- авто-розв'язок мінігри Black Bear
    AutoRejoin       = true,            -- повертатись у гру при відключенні
    WebhookURL       = "",              -- Discord webhook (пусто = вимкнено)
    TrackStats       = true,            -- лічильник pollen/honey за сесію
    DetectStorms     = true,            -- виявлення Honey/Pollen Storm

    -- Рух (Atlas-style):
    UseWalking       = true,
    UsePathfinding   = false,
    WalkAcceptRadius = 4,
    WalkTimeout      = 8,
    TeleportFallback = true,

    -- Atlas-style фічі:
    DoBeequips       = true,            -- авто-екіпірування beequip
    DoFeedBees       = true,            -- годувати бджіл treats
    DoStickerStack   = true,            -- claim Sticker Stack
    DoDailyBonus     = true,            -- щоденний bonus
    DoCodes          = true,            -- авто-redeem кодів
    DoCuckoo         = true,            -- збирати Cuckoo Bee drops
    DoMondoBelly     = true,            -- автоспам кнопки коли в животі
    DoHaste          = true,             -- використання Haste mode
    DoMountainTop    = true,             -- spawn на Mountain Top для Polar quest
    DoGoo            = true,             -- claim Goo deposits
    DoHoneysuckle    = true,             -- збирати Honeysuckle drops
    DoVicious        = false,            -- битись з Vicious Bee замість тікати (для досвідчених)
    DoStumpField     = true,             -- swap полів коли flowers depleted
    DoBuoy           = true,             -- claim Sea Buoy

    -- Coords для special локацій
    StayAtField      = false,            -- після збору — повертатись на те ж поле
    DoBoss           = false,
    PreferredBoss    = "King Beetle",
    DoCrafting       = true,
    FleeFromKillers  = true,
    KillerRadius     = 120,
    WalkSpeed        = 60,
    EClickInterval   = 0.06,
    BuffCheckMinutes = 4,
    PlanterCheckMin  = 10,
    CraftCheckMin    = 15,
}

local KILLER_NAMES = {
    "VICIOUS BEE", "Vicious Bee",
    "Mondo Chick", "MONDO CHICK",
    "Werewolf", "Aphid", "Beetle", "Mantis", "Scorpion",
}

local MOB_NAMES = {
    "Ladybug", "Rhino Beetle", "Spider", "Mantis", "Scorpion",
    "Werewolf", "Stump Snail",
}

local BOSS_NAMES = {
    "King Beetle", "Tunnel Bear", "Stump Snail",
    "Werewolf", "Coconut Crab",
}

local BUFF_ITEM_NAMES = {
    "Field Boost", "Gummy Mask", "Pineapple Mask",
    "Star Jelly", "Glitter", "Oil", "Enzymes",
}

------------------------------------------------------------
-- БАЗА ТОКЕНІВ — ТІЛЬКИ ВІД АБІЛОК БДЖІЛ
-- (без луту типу Royal Jelly, Ticket, Star Jelly, без pollen-токенів полів)
------------------------------------------------------------
------------------------------------------------------------
-- ОФІЦІЙНИЙ СПИСОК ABILITY TOKENS BSS (43 шт)
-- Категорії: Gather / Battle / Idle / Event / Beequip
-- Джерело: bee-swarm-simulator.fandom.com/wiki/Ability_Tokens
------------------------------------------------------------
local TOKEN_DB = {
    -- ═════ GATHER (boost pollen collection) ═════
    ["Token Link"]         = { gameValue = 100, range = 1200, category = "gather" },
    ["Haste"]              = { gameValue =  90, range =  800, category = "gather", buffName = "Haste" },
    ["Focus"]              = { gameValue =  85, range =  700, category = "gather", buffName = "Focus" },
    ["Boost"]              = { gameValue =  85, range =  700, category = "gather", buffName = "Boost" },
    ["Pollen Haze"]        = { gameValue =  80, range =  600, category = "gather" },
    ["Triangulate"]        = { gameValue =  75, range =  600, category = "gather" },
    ["Inspire"]            = { gameValue =  80, range =  600, category = "gather" },

    -- ═════ BATTLE (attack mobs) ═════
    ["Bomb"]               = { gameValue =  90, range =  800, category = "battle" },
    ["Rage"]               = { gameValue =  80, range =  600, category = "battle" },
    ["Inferno"]            = { gameValue =  85, range =  700, category = "battle" },
    ["Flame Fuel"]         = { gameValue =  75, range =  500, category = "battle" },
    ["Fuzz Bombs"]         = { gameValue =  75, range =  500, category = "battle" },
    ["Mark"]               = { gameValue =  85, range =  700, category = "battle" },
    ["Mark Surge"]         = { gameValue =  85, range =  700, category = "battle" },
    ["Target Practice"]    = { gameValue =  70, range =  500, category = "battle" },

    -- ═════ IDLE / SUPPORT ═════
    ["Honey Gift"]         = { gameValue =  75, range =  600, category = "idle" },
    ["Baby Love"]          = { gameValue =  70, range =  500, category = "idle" },
    ["Melody"]             = { gameValue =  70, range =  500, category = "idle" },
    ["Inflate Balloons"]   = { gameValue =  65, range =  450, category = "idle" },
    ["Surprise Party"]     = { gameValue =  70, range =  500, category = "idle" },
    ["Summon Frog"]        = { gameValue =  65, range =  450, category = "idle" },

    -- ═════ EVENT BEE TOKENS (Beesmas / Holiday) ═════
    ["Bear Morph"]         = { gameValue =  75, range =  500, category = "event" },
    ["Pulse"]              = { gameValue =  80, range =  600, category = "event" },
    ["Bomb Sync"]          = { gameValue =  80, range =  600, category = "event" },
    ["Festive Gift"]       = { gameValue =  75, range =  500, category = "event" },
    ["Festive Blessing"]   = { gameValue =  80, range =  600, category = "event" },
    ["Beesmas Cheer"]      = { gameValue =  75, range =  500, category = "event" },
    ["Glob"]               = { gameValue =  70, range =  500, category = "event" },
    ["Gumdrop Barrage"]    = { gameValue =  75, range =  500, category = "event" },
    ["Beamstorm"]          = { gameValue =  90, range =  800, category = "event" },
    ["Puppy Love"]         = { gameValue =  70, range =  500, category = "event" },
    ["Fetch"]              = { gameValue =  65, range =  450, category = "event" },
    ["Scratch"]            = { gameValue =  65, range =  450, category = "event" },
    ["Tabby Love"]         = { gameValue =  70, range =  500, category = "event" },
    ["Impale"]             = { gameValue =  80, range =  600, category = "event" },
    ["Rain Cloud"]         = { gameValue =  80, range =  600, category = "event" },
    ["Tornado"]            = { gameValue =  85, range =  700, category = "event" },
    ["Glitch"]             = { gameValue =  80, range =  600, category = "event" },
    ["Map Corruption"]     = { gameValue =  85, range =  700, category = "event" },
    ["Mind Hack"]          = { gameValue =  85, range =  700, category = "event" },
    ["Smiley"]             = { gameValue =  60, range =  400, category = "event" }, -- ☺

    -- ═════ BEEQUIP-EXCLUSIVE ═════
    ["Snowglobe Shake"]    = { gameValue =  70, range =  500, category = "beequip" },
    ["Festive Mark"]       = { gameValue =  75, range =  500, category = "beequip" },
}

local TOKEN_FILTERS = {}
for name in pairs(TOKEN_DB) do TOKEN_FILTERS[name] = true end

------------------------------------------------------------
-- ФОРВАРД-ДЕКЛАРАЦІЇ (потрібні для anti-detect / walkTo функцій)
------------------------------------------------------------
local function setSpeed(v) pcall(function() if hum then hum.WalkSpeed = v end end) end

-- stats forward-declared (повний об'єкт нижче)
local stats = { tokensCollected = 0, honeyMade = 0, pollenCollected = 0,
                bossesKilled = 0, mobsKilled = 0, deaths = 0, fieldSwitches = 0,
                lastPollen = 0, lastHoney = 0, sessionStart = tick() }

local state = {
    running       = true,
    paused        = false,
    returnNow     = false,
    inDanger      = false,
    bossMode      = false,
    mobMode       = true,
    craftNow      = false,
    lastBuff      = 0,
    lastPlanter   = 0,
    lastCraft     = 0,
}

------------------------------------------------------------
-- ANTI-DETECTION (server-side anomaly avoidance)
------------------------------------------------------------
local AD = {
    MaxTpDistance      = 350,    -- макс відстань одного телепорту
    TpStepDistance     = 200,    -- довжина одного "стрибка" при ланцюговому TP
    StepDelayMin       = 0.08,
    StepDelayMax       = 0.18,
    HumanJitter        = true,   -- додавати випадкові зсуви в позиції
    ClickJitterMin     = 0.02,
    ClickJitterMax     = 0.08,
    SimulatedLatencyMs = 60,     -- імітація мережевої затримки
}

local function rnd(a, b) return a + math.random() * (b - a) end
local function humanWait(min, max) task.wait(rnd(min or 0.05, max or 0.15)) end

local function jitterCFrame(cf, amount)
    amount = amount or 1.5
    return cf * CFrame.new(rnd(-amount, amount), 0, rnd(-amount, amount))
end

------------------------------------------------------------
-- УТИЛІТИ
------------------------------------------------------------
local function chainTeleport(startPos, endPos)
    -- Розбиває один великий телепорт на ланцюг коротких,
    -- щоб не тригерити server-side anti-teleport чеки.
    local dir = (endPos - startPos)
    local d   = dir.Magnitude
    if d <= AD.TpStepDistance then
        hrp.CFrame = CFrame.new(endPos + Vector3.new(0, 4, 0))
        return
    end
    local steps = math.ceil(d / AD.TpStepDistance)
    local unit  = dir.Unit
    for i = 1, steps do
        if not state.running then return end
        local t = math.min(i * AD.TpStepDistance, d)
        local p = startPos + unit * t
        if AD.HumanJitter then
            p = p + Vector3.new(rnd(-2, 2), 0, rnd(-2, 2))
        end
        hrp.CFrame = CFrame.new(p + Vector3.new(0, 4, 0))
        task.wait(rnd(AD.StepDelayMin, AD.StepDelayMax))
    end
end

------------------------------------------------------------
-- РУХ: walkTo (як Atlas) і tpRaw (миттєвий)
------------------------------------------------------------
local function targetToCFrame(target)
    if typeof(target) == "Instance" then
        local ok, p = pcall(function() return target:GetPivot() end)
        return ok and p or nil
    elseif typeof(target) == "CFrame" then return target
    elseif typeof(target) == "Vector3" then return CFrame.new(target)
    end
end

-- Миттєвий телепорт (внутрішнє використання — fallback)
local function tpRaw(target)
    local cf = targetToCFrame(target)
    if not cf or not hrp or not hrp.Parent then return false end
    if AD.HumanJitter then cf = jitterCFrame(cf, 1.5) end
    local dist = (hrp.Position - cf.Position).Magnitude
    if dist > AD.MaxTpDistance then
        chainTeleport(hrp.Position, cf.Position)
    else
        hrp.CFrame = cf + Vector3.new(0, 4, 0)
    end
    task.wait(AD.SimulatedLatencyMs / 1000)
    return true
end

-- Реальний рух humanoid'ом (Atlas-style)
local function walkToPoint(pos)
    if not hum or not hrp then return false end
    local t0 = tick()
    hum:MoveTo(pos)
    while tick() - t0 < CFG.WalkTimeout do
        if not state.running then return false end
        local d = (hrp.Position - pos).Magnitude
        if d <= CFG.WalkAcceptRadius then return true end
        -- Якщо застряг — нагадуємо ціль
        if (tick() - t0) % 1 < 0.05 then hum:MoveTo(pos) end
        task.wait(0.1)
    end
    return false
end

-- Pathfinding (обхід перешкод)
local function walkPath(targetPos)
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentJumpHeight = 7,
        AgentMaxSlope = 45,
    })
    local ok = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)
    if not ok or path.Status ~= Enum.PathStatus.Success then
        return walkToPoint(targetPos)  -- fallback на пряму ходу
    end
    for _, wp in ipairs(path:GetWaypoints()) do
        if not state.running then return false end
        if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
        if not walkToPoint(wp.Position) then break end
    end
    return (hrp.Position - targetPos).Magnitude <= CFG.WalkAcceptRadius
end

-- Універсальний переміщувач: ХОДИТЬ, з телепорт-fallback'ом
local function tpTo(target)
    local cf = targetToCFrame(target)
    if not cf or not hrp or not hrp.Parent then return false end
    local goalPos = cf.Position

    if CFG.UseWalking then
        setSpeed(CFG.WalkSpeed)
        local reached
        if CFG.UsePathfinding then
            reached = walkPath(goalPos)
        else
            reached = walkToPoint(goalPos)
        end
        if reached then return true end
        if CFG.TeleportFallback then
            print("[Move] Не дійшов пішки — телепорт fallback")
            return tpRaw(target)
        end
        return false
    else
        return tpRaw(target)
    end
end

local function distTo(obj)
    local ok, p = pcall(function()
        if typeof(obj) == "Vector3" then return obj end
        return obj:GetPivot().Position
    end)
    if not ok then return math.huge end
    return (hrp.Position - p).Magnitude
end

-- Universal input: на ПК через keypress executor'а,
-- на мобілці — через VirtualInputManager (фейковий тач/клавіш) або ProximityPrompt
local VIM = nil
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local kp, kr
do
    local _kp = rawget(getfenv(), "keypress") or (Input and Input.KeyPress)
    local _kr = rawget(getfenv(), "keyrelease") or (Input and Input.KeyRelease)
    if _kp and _kr then
        kp, kr = _kp, _kr
    elseif VIM then
        -- VirtualInputManager доступний майже на всіх мобільних executor'ах
        kp = function(keycode) pcall(function() VIM:SendKeyEvent(true,  keycode, false, game) end) end
        kr = function(keycode) pcall(function() VIM:SendKeyEvent(false, keycode, false, game) end) end
    else
        kp = function() end
        kr = function() end
    end
end

-- На мобілці E-spam через клавіатуру може не працювати → fire ProximityPrompt напряму
local function fireProximityPromptsNearby(radius)
    radius = radius or 12
    if not hrp then return end
    for _, p in ipairs(Workspace:GetDescendants()) do
        if p:IsA("ProximityPrompt") and p.Enabled then
            local parent = p.Parent
            local ok, pos = pcall(function()
                if parent:IsA("BasePart") then return parent.Position end
                return parent:GetPivot().Position
            end)
            if ok and (hrp.Position - pos).Magnitude <= radius then
                pcall(function() fireproximityprompt(p) end)
            end
        end
    end
end
local function tap(k, d)
    kp(k)
    task.wait(d or rnd(AD.ClickJitterMin, AD.ClickJitterMax))
    kr(k)
end
local function hold(k, s)
    kp(k)
    task.wait(s + rnd(-0.05, 0.05))
    kr(k)
end
-- setSpeed визначено вище у форвард-декларації

local function nameContains(name, list)
    name = tostring(name):lower()
    for _, n in ipairs(list) do
        if name:find(n:lower(), 1, true) then return true end
    end
    return false
end

------------------------------------------------------------
-- СТАН (доконфігурація)
------------------------------------------------------------
state.bossMode = CFG.DoBoss
state.mobMode  = CFG.DoMobs

------------------------------------------------------------
-- СКАНУВАННЯ
------------------------------------------------------------
local function findFields()
    local out = {}
    local fold = Workspace:FindFirstChild("FlowerZones")
              or Workspace:FindFirstChild("Fields")
              or Workspace:FindFirstChild("Zones")
    if fold then
        for _, f in ipairs(fold:GetChildren()) do out[f.Name] = f end
    end
    return out
end

local function findHive()
    local hives = Workspace:FindFirstChild("Hives") or Workspace:FindFirstChild("Honeycombs")
    if not hives then return nil end
    for _, h in ipairs(hives:GetChildren()) do
        local owner = h:FindFirstChild("Owner")
        if (owner and owner.Value == LP) or h.Name == LP.Name then return h end
    end
    return hives:GetChildren()[1]
end

local function findDispensers()
    local out = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if (obj:IsA("Model") or obj:IsA("BasePart")) and obj.Name:lower():find("dispenser") then
            table.insert(out, obj)
        end
    end
    return out
end

------------------------------------------------------------
-- BUFF TRACKER (читає активні баффи + час залишку)
------------------------------------------------------------
local activeBuffs = {}  -- { ["Glitter"] = endTime, ... }

local function parseDuration(text)
    -- "5:42" → 342, "1m 20s" → 80, "45s" → 45
    local m, s = text:match("(%d+):(%d+)")
    if m and s then return tonumber(m)*60 + tonumber(s) end
    local mm, ss = text:match("(%d+)m%s*(%d+)s")
    if mm and ss then return tonumber(mm)*60 + tonumber(ss) end
    local n = text:match("(%d+)s")
    if n then return tonumber(n) end
    return nil
end

local function refreshBuffs()
    activeBuffs = {}
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text then
            local txt = d.Text
            -- Шукаємо "Buff: X:XX" або текст з таймером
            for name, info in pairs(TOKEN_DB) do
                if info.buffName and txt:find(info.buffName, 1, true) then
                    local dur = parseDuration(txt)
                    if dur and dur > 0 then
                        activeBuffs[info.buffName] = tick() + dur
                    end
                end
            end
        end
    end
end

local function buffRemaining(buffName)
    if not buffName then return 0 end
    local endT = activeBuffs[buffName]
    if not endT then return 0 end
    return math.max(0, endT - tick())
end

local function isBuffActive(buffName)
    return buffRemaining(buffName) > 10  -- 10 сек запасу
end

-- Background updater
task.spawn(function()
    while task.wait(2) do
        if state.running then pcall(refreshBuffs) end
    end
end)

-- Мепинг між назвою об'єкта і токеном з TOKEN_DB
local function matchTokenFilter(objName)
    local n = objName:lower()
    for name, _ in pairs(TOKEN_DB) do
        if TOKEN_FILTERS[name] and n:find(name:lower(), 1, true) then
            return true, name
        end
    end
    if TOKEN_FILTERS["Honey Token"] and (n:find("honeytoken") or n:find("token_honey")) then
        return true, "Honey Token"
    end
    return false
end

local function findTokens(radius)
    radius = radius or CFG.TokenRadius
    local out = {}
    local fold = Workspace:FindFirstChild("Collectibles") or Workspace:FindFirstChild("Tokens")
    local search = fold and fold:GetChildren() or Workspace:GetDescendants()
    for _, obj in ipairs(search) do
        if obj:IsA("BasePart") or obj:IsA("Model") then
            local matched, kind = matchTokenFilter(obj.Name)
            if matched and distTo(obj) <= radius then
                table.insert(out, { obj = obj, kind = kind })
            end
        end
    end
    return out
end

local function findKillersNearby()
    local out = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and nameContains(obj.Name, KILLER_NAMES) then
            if obj:FindFirstChildWhichIsA("Humanoid") and distTo(obj) <= CFG.KillerRadius then
                table.insert(out, obj)
            end
        end
    end
    return out
end

local function findMobs()
    local out = {}
    local mobsFold = Workspace:FindFirstChild("Monsters") or Workspace:FindFirstChild("Mobs")
    local search = mobsFold and mobsFold:GetChildren() or Workspace:GetDescendants()
    for _, obj in ipairs(search) do
        if obj:IsA("Model") and nameContains(obj.Name, MOB_NAMES) then
            local hp = obj:FindFirstChildWhichIsA("Humanoid")
            if hp and hp.Health > 0 then table.insert(out, obj) end
        end
    end
    return out
end

local function findBoss(name)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name == name then
            local h = obj:FindFirstChildWhichIsA("Humanoid")
            if h and h.Health > 0 then return obj end
        end
    end
    return nil
end

local function findPlanters()
    local out = {}
    local fold = Workspace:FindFirstChild("Planters")
    if not fold then return out end
    for _, p in ipairs(fold:GetChildren()) do
        local owner = p:FindFirstChild("Owner")
        if owner and owner.Value == LP then
            table.insert(out, p)
        end
    end
    return out
end

local function findBlender()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:lower():find("blender") then
            return obj
        end
    end
end

local function findStickerPrinter()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:lower():find("sticker") then
            return obj
        end
    end
end

local function findCurrentField(fields)
    local best, bd
    for n, m in pairs(fields) do
        local d = distTo(m)
        if not bd or d < bd then bd = d; best = n end
    end
    return best
end

------------------------------------------------------------
-- POLLEN / CAPACITY
------------------------------------------------------------
local function readBagFill()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return 0 end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local t = d.Text or ""
            local cur, cap = t:match("([%d,%.]+)%s*/%s*([%d,%.]+)")
            if cur and cap then
                cur = tonumber((cur:gsub(",", ""))) or 0
                cap = tonumber((cap:gsub(",", ""))) or 1
                if cap > 100 then return cur / cap, cur, cap end
            end
        end
    end
    return 0
end

------------------------------------------------------------
-- INVENTORY / REMOTES
------------------------------------------------------------
local function findRemote(nameKeywords)
    for _, obj in ipairs(RS:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local n = obj.Name:lower()
            for _, kw in ipairs(nameKeywords) do
                if n:find(kw:lower()) then return obj end
            end
        end
    end
end

local UseItem = findRemote({"useitem", "consume"})

local function useItemByName(itemName)
    if not UseItem then return false end
    local ok = pcall(function()
        if UseItem:IsA("RemoteEvent") then UseItem:FireServer(itemName)
        else UseItem:InvokeServer(itemName) end
    end)
    return ok
end

local function useBuffs()
    if not CFG.DoBuffs then return end
    if tick() - state.lastBuff < CFG.BuffCheckMinutes * 60 then return end
    state.lastBuff = tick()
    for _, name in ipairs(BUFF_ITEM_NAMES) do
        useItemByName(name)
        task.wait(0.3)
    end
end

------------------------------------------------------------
-- E-SPAM І РУХ
------------------------------------------------------------
local function eSpam()
    task.spawn(function()
        while state.running do
            if not state.paused and not state.inDanger then
                tap(0x45, 0.02)
                -- Дублюємо через ProximityPrompt для мобілок
                if PLATFORM.Mobile then fireProximityPromptsNearby(14) end
            end
            task.wait(CFG.EClickInterval)
        end
    end)
end

local function snakeMove(duration)
    local t0 = tick()
    local keys = { 0x57, 0x44, 0x53, 0x41 }
    local i = 1
    while state.running and not state.paused and not state.returnNow
          and not state.inDanger and tick() - t0 < duration do
        hold(keys[i], 0.7 + math.random() * 0.6)
        i = i % #keys + 1
        if readBagFill() >= CFG.BagFullThreshold then break end
    end
end

------------------------------------------------------------
-- ДЕТЕКТОР НЕБЕЗПЕКИ
------------------------------------------------------------
local hive
local function dangerWatcher()
    task.spawn(function()
        while state.running do
            if CFG.FleeFromKillers and not state.paused then
                local killers = findKillersNearby()
                if #killers > 0 then
                    state.inDanger = true
                    warn("[Macro] Killer detected → flee to hive")
                    if hive then tpTo(hive); task.wait(2) end
                    task.wait(8)
                    state.inDanger = false
                end
            end
            task.wait(1.5)
        end
    end)
end

------------------------------------------------------------
-- ДІЇ
------------------------------------------------------------
------------------------------------------------------------
-- SMART TOKEN SCORING (внутрішня логіка вибору)
------------------------------------------------------------
local function scoreToken(entry, bagFill)
    local info = TOKEN_DB[entry.kind]
    if not info then return 0 end

    local base = info.gameValue                       -- 1-100
    local dist = distTo(entry.obj)

    -- 1) Distance penalty: чим далі, тим менший score
    --    Використовуємо range як "вікно інтересу"
    local rangeMul = math.max(0, 1 - (dist / info.range))
    if rangeMul <= 0 then return 0 end

    -- 2) Buff urgency: якщо токен дає буфф, і його вже немає або скоро закінчиться
    if info.buffName then
        local remain = buffRemaining(info.buffName)
        if remain < 30 then
            -- Буфф майже зник → ВЕЛИКИЙ бонус (потрібно поновити)
            base = base * 1.8
        elseif remain > (info.buffDur or 600) * 0.7 then
            -- Буфф ще довго діє → не варто витрачати (зменшуємо вартість)
            base = base * 0.4
        end
    end

    -- 3) Bag fullness: якщо мішок майже повний — небажано бігти за далеким Honey Token
    --    Зате rare-токени (gameValue > 70) досі варто, бо вони не йдуть у мішок
    if bagFill > 0.85 and info.gameValue < 60 then
        base = base * (1 - bagFill)  -- наближається до 0
    end

    -- 4) Storm boost: під час Honey/Pollen storm — все цінніше
    if state.stormActive then
        base = base * 1.3
    end

    -- 5) Final score: base * rangeMultiplier
    return base * rangeMul
end

local function collectTokens()
    if not CFG.UseTokens then return end

    local bagFill = readBagFill() or 0
    refreshBuffs()  -- актуалізуємо стан буффів перед оцінкою

    local toks = findTokens(800)  -- ширший пошук, фільтр зробить scoring
    if #toks == 0 then return end

    -- Оцінюємо кожен токен
    local scored = {}
    for _, entry in ipairs(toks) do
        local s = scoreToken(entry, bagFill)
        if s > 0 then
            table.insert(scored, { entry = entry, score = s })
        end
    end

    -- Сортуємо: найкращий score спочатку
    table.sort(scored, function(a, b) return a.score > b.score end)

    -- Підбираємо. Після кожного — переоцінка (бо позиція гравця змінилась)
    local collected = 0
    for _ = 1, 20 do
        if not state.running or state.returnNow or state.inDanger then break end
        if #scored == 0 then break end

        -- Переоцінюємо топ-5 з урахуванням нової позиції
        local top = {}
        for i = 1, math.min(5, #scored) do
            local e = scored[i].entry
            if e.obj and e.obj.Parent then
                table.insert(top, { entry = e, score = scoreToken(e, bagFill) })
            end
        end
        if #top == 0 then break end
        table.sort(top, function(a, b) return a.score > b.score end)

        local best = top[1]
        if best.score < 10 then break end  -- нічого вартого поряд

        tpTo(best.entry.obj)
        stats.tokensCollected = (stats.tokensCollected or 0) + 1
        collected = collected + 1
        task.wait(0.1)

        -- Видаляємо зібраний з scored
        for i = #scored, 1, -1 do
            if scored[i].entry == best.entry then table.remove(scored, i); break end
        end

        bagFill = readBagFill() or bagFill
        if bagFill >= CFG.BagFullThreshold then break end
    end
end

local function farmField(fm)
    if not fm then return end
    tpTo(fm); task.wait(0.4)
    setSpeed(CFG.WalkSpeed)
    local farmEnd = tick() + 240
    while state.running and not state.returnNow and not state.inDanger and tick() < farmEnd do
        snakeMove(7)
        collectTokens()
        if readBagFill() >= CFG.BagFullThreshold then break end
    end
    setSpeed(16)
end

local function convertAtHive()
    if not hive then return end
    tpTo(hive); task.wait(0.6)
    for _ = 1, 10 do tap(0x45, 0.05); task.wait(0.25) end
    task.wait(1)
end

local function visitDispensers(disp)
    for _, d in ipairs(disp) do
        if not state.running or state.inDanger then return end
        if d.Parent then
            tpTo(d); task.wait(0.6)
            tap(0x45, 0.05); task.wait(0.3)
            tap(0x45, 0.05); task.wait(0.3)
        end
    end
end

local function killMob(mob)
    if not mob or not mob.Parent then return end
    local h = mob:FindFirstChildWhichIsA("Humanoid")
    if not h then return end
    local timeout = tick() + 30
    while h.Health > 0 and tick() < timeout and state.running and not state.inDanger do
        local ok, p = pcall(function() return mob:GetPivot().Position end)
        if not ok then break end
        hrp.CFrame = CFrame.new(p + Vector3.new(0, 6, 0))
        tap(0x45, 0.03)
        task.wait(0.2)
    end
    task.wait(0.5)
    collectTokens()
end

local function huntMobs()
    if not state.mobMode then return end
    local mobs = findMobs()
    for _, m in ipairs(mobs) do
        if not state.running or state.inDanger then return end
        if distTo(m) < 400 then killMob(m) end
    end
end

local function fightBoss()
    if not state.bossMode then return end
    local b = findBoss(CFG.PreferredBoss)
    if not b then return end
    print("[Macro] Boss: " .. CFG.PreferredBoss)
    killMob(b)
    convertAtHive()
end

local function processPlanters()
    if not CFG.DoPlanters then return end
    if tick() - state.lastPlanter < CFG.PlanterCheckMin * 60 then return end
    state.lastPlanter = tick()
    local planters = findPlanters()
    for _, p in ipairs(planters) do
        local growth = p:FindFirstChild("Growth")
        local ready = growth and growth.Value and tonumber(tostring(growth.Value)) and tonumber(tostring(growth.Value)) >= 100
        if ready or not growth then
            tpTo(p); task.wait(0.5)
            tap(0x45, 0.05); task.wait(0.4) -- collect
            tap(0x45, 0.05); task.wait(0.4) -- replace
        end
    end
end

local function processCrafting()
    if not CFG.DoCrafting and not state.craftNow then return end
    if not state.craftNow and tick() - state.lastCraft < CFG.CraftCheckMin * 60 then return end
    state.lastCraft = tick()
    state.craftNow = false

    local blender = findBlender()
    if blender then
        tpTo(blender); task.wait(0.6)
        for _ = 1, 5 do tap(0x45, 0.05); task.wait(0.4) end
    end

    local printer = findStickerPrinter()
    if printer then
        tpTo(printer); task.wait(0.6)
        for _ = 1, 5 do tap(0x45, 0.05); task.wait(0.4) end
    end
end

------------------------------------------------------------
-- STATS TRACKER (нова фіча) — об'єкт stats форвард-декларований вище
------------------------------------------------------------
local function readGameStats()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") then
            local t = d.Text or ""
            -- Honey: "1,234,567" або "1.23M"
            local honeyNum = t:match("Honey%s*:?%s*([%d,%.MBkK]+)")
            if honeyNum then
                local n = tonumber((honeyNum:gsub(",", "")))
                if n and n > 0 then
                    if stats.lastHoney > 0 and n > stats.lastHoney then
                        stats.honeyMade = stats.honeyMade + (n - stats.lastHoney)
                    end
                    stats.lastHoney = n
                end
            end
        end
    end
end

local function sessionTime()
    local elapsed = tick() - stats.sessionStart
    local h = math.floor(elapsed / 3600)
    local m = math.floor((elapsed % 3600) / 60)
    local s = math.floor(elapsed % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function honeyPerHour()
    local elapsed = tick() - stats.sessionStart
    if elapsed < 60 then return 0 end
    return math.floor(stats.honeyMade * 3600 / elapsed)
end

------------------------------------------------------------
-- DISCORD WEBHOOK (нова фіча)
------------------------------------------------------------
local HttpService = game:GetService("HttpService")
local sendRequest = (syn and syn.request) or http_request or request
                 or (http and http.request) or function() end

local function webhook(message, color)
    if not CFG.WebhookURL or CFG.WebhookURL == "" then return end
    local payload = {
        embeds = {{
            title = "🐝 BSS Macro",
            description = message,
            color = color or 0xFFC83C,
            footer = { text = "Session: " .. sessionTime() },
            timestamp = DateTime.now():ToIsoDate(),
        }}
    }
    local body
    local ok = pcall(function() body = HttpService:JSONEncode(payload) end)
    if not ok then return end
    pcall(function()
        sendRequest({
            Url = CFG.WebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    end)
end

------------------------------------------------------------
-- QUESTS (Bears) — нова фіча
------------------------------------------------------------
local BEAR_NAMES = {
    "Black Bear", "Brown Bear", "Polar Bear", "Mother Bear",
    "Panda Bear", "Science Bear", "Honey Bear", "Spirit Bear",
    "Bee Bear", "Gummy Bear", "Onett", "Bucko Bee", "Riley Bee", "Stick Bug",
}

local function findBears()
    local out = {}
    for _, name in ipairs(BEAR_NAMES) do
        local m = Workspace:FindFirstChild(name, true)
        if m then table.insert(out, m) end
    end
    return out
end

local function talkToBear(bear)
    if not bear then return end
    tpTo(bear)
    task.wait(0.8)
    -- Пробуємо всі способи активації:
    tap(0x45, 0.05); task.wait(0.3)        -- E key
    fireProximityPromptsNearby(20)         -- ProximityPrompt
    -- ClickDetector fallback
    for _, cd in ipairs(bear:GetDescendants()) do
        if cd:IsA("ClickDetector") then
            pcall(function() fireclickdetector(cd) end)
        end
    end
    task.wait(0.5)
end

------------------------------------------------------------
-- ATLAS-STYLE ФІЧІ
------------------------------------------------------------

-- BEEQUIPS — авто-екіпірування
local function processBeequips()
    if not CFG.DoBeequips then return end
    if state.lastBeequip and tick() - state.lastBeequip < 600 then return end
    state.lastBeequip = tick()
    -- Beequips зберігаються у backpack, активуються через UseItem remote
    local backpack = LP:FindFirstChild("Backpack")
    if not backpack then return end
    for _, item in ipairs(backpack:GetChildren()) do
        if item.Name:lower():find("beequip") then
            pcall(function() useItemByName(item.Name) end)
            task.wait(0.2)
        end
    end
end

-- FEED BEES — годівля бджіл treats
local function feedBees()
    if not CFG.DoFeedBees then return end
    if state.lastFeed and tick() - state.lastFeed < 1200 then return end -- 20 хв
    state.lastFeed = tick()
    -- Стоїмо на hive і використовуємо Treat
    if hive then
        tpTo(hive); task.wait(0.5)
        local items = { "Treat", "Blueberry", "Strawberry", "Pineapple", "Sunflower Seed" }
        for _, it in ipairs(items) do
            pcall(function() useItemByName(it) end)
            task.wait(0.4)
        end
    end
end

-- STICKER STACK — claim
local function claimStickerStack()
    if not CFG.DoStickerStack then return end
    if state.lastSticker and tick() - state.lastSticker < 1800 then return end
    state.lastSticker = tick()
    local stack = Workspace:FindFirstChild("Sticker Stack", true)
                  or Workspace:FindFirstChild("StickerStack", true)
    if not stack then return end
    tpTo(stack); task.wait(0.5)
    fireProximityPromptsNearby(15)
    tap(0x45, 0.05); task.wait(0.4)
    webhook("✨ Sticker Stack claimed", 0xFF80FF)
end

-- DAILY BONUS — щоденне
local function claimDailyBonus()
    if not CFG.DoDailyBonus then return end
    if state.lastDaily and tick() - state.lastDaily < 3600 then return end
    state.lastDaily = tick()
    -- Daily bonus звичайно з'являється як ScreenGui автоматично
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextButton") and (d.Text:lower():find("claim") or d.Text:lower():find("collect")) then
            local parent = d.Parent
            if parent and parent.Name:lower():find("daily") then
                pcall(function() d:Activate() end)
                task.wait(0.3)
                webhook("🎁 Daily bonus claimed", 0x66FF66)
                return
            end
        end
    end
end

-- CODES — авто-redeem нових кодів
local KNOWN_CODES = {
    "38club", "Bopmaster", "BeesBeesBees", "WhirligigPalace",
    "ImABee", "Sundae", "PrinceBee", "PorportShop", "OnettsHome",
    "buoyantbuoy", "feelthepower", "smoothiepartynow", "1MLikes",
    "200811", "100mil", "MovieFiveMillion",  -- старі/міксовані, реальні можуть змінитись
}

local function redeemCodes()
    if not CFG.DoCodes then return end
    if state.codesDone then return end
    state.codesDone = true
    -- Code redemption через Submit Code button у GUI
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    -- Просто warning користувачу — повний auto-redeem потребує remote events що змінюються
    print("[Macro] Спробуй редім кодів вручну — список: " .. table.concat(KNOWN_CODES, ", "))
    webhook("🎟 Codes ready to redeem: " .. table.concat(KNOWN_CODES, ", "), 0xFFAA00)
end

-- MONDO BELLY — коли тебе зжує Mondo Chick, спам клік для виходу
task.spawn(function()
    while task.wait(0.5) do
        if CFG.DoMondoBelly then
            local pg = LP:FindFirstChild("PlayerGui")
            if pg then
                for _, d in ipairs(pg:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text and d.Text:lower():find("mondo") then
                        for _ = 1, 30 do
                            tap(0x45, 0.02)
                            pcall(function() VIM:SendMouseButtonEvent(VP.X/2, VP.Y/2, 0, true, game, 0) end)
                            pcall(function() VIM:SendMouseButtonEvent(VP.X/2, VP.Y/2, 0, false, game, 0) end)
                            task.wait(0.1)
                        end
                        break
                    end
                end
            end
        end
    end
end)

-- HASTE MODE
local function activateHaste()
    if not CFG.DoHaste then return end
    if state.lastHaste and tick() - state.lastHaste < 600 then return end
    state.lastHaste = tick()
    pcall(function() useItemByName("Haste") end)
end

-- MOUNTAIN TOP — спавн нагорі (для Polar Bear quests)
local function goMountainTop()
    if not CFG.DoMountainTop then return end
    if state.lastMtTop and tick() - state.lastMtTop < 600 then return end
    state.lastMtTop = tick()
    local mt = Workspace:FindFirstChild("Mountain Top", true)
              or Workspace:FindFirstChild("MountainTop", true)
    if mt then
        tpTo(mt); task.wait(0.4)
        collectTokens()
    end
end

-- GOO DEPOSITS
local function claimGoo()
    if not CFG.DoGoo then return end
    if state.lastGoo and tick() - state.lastGoo < 1800 then return end
    state.lastGoo = tick()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name:lower():find("goo") and (obj:IsA("BasePart") or obj:IsA("Model")) then
            if distTo(obj) < 1000 then
                tpTo(obj); task.wait(0.3)
                fireProximityPromptsNearby(15)
                tap(0x45, 0.05); task.wait(0.3)
            end
        end
    end
end

-- HONEYSUCKLE BOTTLE
local function claimHoneysuckle()
    if not CFG.DoHoneysuckle then return end
    local bottle = Workspace:FindFirstChild("Honeysuckle", true)
                or Workspace:FindFirstChild("Honeysuckle Bottle", true)
    if bottle and distTo(bottle) < 500 then
        tpTo(bottle); task.wait(0.3)
        fireProximityPromptsNearby(15)
        tap(0x45, 0.05); task.wait(0.3)
    end
end

-- SEA BUOY
local function claimBuoy()
    if not CFG.DoBuoy then return end
    if state.lastBuoy and tick() - state.lastBuoy < 1800 then return end
    state.lastBuoy = tick()
    local buoy = Workspace:FindFirstChild("Buoy", true)
              or Workspace:FindFirstChild("Sea Buoy", true)
    if buoy then
        tpTo(buoy); task.wait(0.5)
        fireProximityPromptsNearby(20)
        tap(0x45, 0.05); task.wait(0.4)
        webhook("⛵ Sea Buoy claimed", 0x00BFFF)
    end
end

-- CUCKOO BEE drops collection
local function collectCuckooDrops()
    if not CFG.DoCuckoo then return end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name:lower():find("cuckoo") and (obj:IsA("BasePart") or obj:IsA("Model")) then
            if distTo(obj) < 300 then
                tpTo(obj); task.wait(0.2)
            end
        end
    end
end

-- VICIOUS BEE hunt (для досвідчених — high reward)
local function huntVicious()
    if not CFG.DoVicious then return end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:lower():find("vicious") then
            local h = obj:FindFirstChildWhichIsA("Humanoid")
            if h and h.Health > 0 and distTo(obj) < 2000 then
                print("[Macro] Vicious Bee detected — hunting")
                webhook("⚔️ Hunting Vicious Bee", 0xFF4040)
                state.inDanger = false  -- override danger watcher
                killMob(obj)
                stats.viciousKilled = (stats.viciousKilled or 0) + 1
                return
            end
        end
    end
end

local function processQuests()
    if not CFG.DoQuests then return end
    if state.lastQuests and tick() - state.lastQuests < 300 then return end -- раз на 5 хв
    state.lastQuests = tick()

    local bears = findBears()
    if #bears == 0 then return end
    print("[Macro] Quests: знайдено " .. #bears .. " bears")
    for _, b in ipairs(bears) do
        if not state.running then return end
        if (hrp.Position - b:GetPivot().Position).Magnitude < 1000 then
            talkToBear(b)
        end
    end
end

------------------------------------------------------------
-- SPROUTS (нова фіча)
------------------------------------------------------------
local SPROUT_TYPES = { "Pineapple Sprout", "Sunflower Sprout", "Mushroom Sprout",
                       "Strawberry Sprout", "Blueberry Sprout", "Cactus Sprout",
                       "Spider Sprout", "Pumpkin Sprout", "Pine Tree Sprout" }

local function findSprouts()
    local out = {}
    local fold = Workspace:FindFirstChild("Sprouts")
    if not fold then return out end
    for _, s in ipairs(fold:GetChildren()) do
        local owner = s:FindFirstChild("Owner")
        if owner and owner.Value == LP then
            table.insert(out, s)
        end
    end
    return out
end

local function plantSprout()
    -- Шукаємо sprout в інвентарі та "садимо" його
    if not VIM then return end
    -- Use Item Number 5 (стандартна слот для sprout'ів)
    pcall(function()
        local backpack = LP:FindFirstChild("Backpack")
        if not backpack then return end
        for _, item in ipairs(backpack:GetChildren()) do
            for _, st in ipairs(SPROUT_TYPES) do
                if item.Name:find(st, 1, true) then
                    -- Equip + use
                    hum:EquipTool(item)
                    task.wait(0.3)
                    VIM:SendMouseButtonEvent(VP.X/2, VP.Y/2, 0, true, game, 0)
                    task.wait(0.1)
                    VIM:SendMouseButtonEvent(VP.X/2, VP.Y/2, 0, false, game, 0)
                    return
                end
            end
        end
    end)
end

local function processSprouts()
    if not CFG.DoSprouts then return end
    if state.lastSprouts and tick() - state.lastSprouts < 900 then return end -- раз на 15 хв
    state.lastSprouts = tick()

    -- Збираємо готові sprout'и (вони стають collectibles)
    local sprouts = findSprouts()
    for _, s in ipairs(sprouts) do
        if (hrp.Position - s:GetPivot().Position).Magnitude < 500 then
            tpTo(s)
            task.wait(0.3)
            fireProximityPromptsNearby(15)
            tap(0x45, 0.1); task.wait(0.3)
        end
    end
end

------------------------------------------------------------
-- WEALTH CLOCK (нова фіча)
------------------------------------------------------------
local function findWealthClock()
    return Workspace:FindFirstChild("Wealth Clock", true)
end

local function claimWealthClock()
    if not CFG.DoWealthClock then return end
    if state.lastWealth and tick() - state.lastWealth < 3600 then return end -- раз на годину перевіряємо
    state.lastWealth = tick()

    local clock = findWealthClock()
    if not clock then return end
    tpTo(clock)
    task.wait(0.6)
    fireProximityPromptsNearby(15)
    tap(0x45, 0.05); task.wait(0.4)
    tap(0x45, 0.05); task.wait(0.4)
    webhook("💰 Wealth Clock claim attempted", 0xFFD700)
end

------------------------------------------------------------
-- MEMORY MATCH (Black Bear minigame solver) — нова фіча
------------------------------------------------------------
local function solveMemoryMatch()
    if not CFG.DoMemoryMatch then return end
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end

    local mmGui = pg:FindFirstChild("MemoryMatchGUI") or pg:FindFirstChild("MemoryMatch")
    if not mmGui or not mmGui.Enabled then return end

    -- Шукаємо board з картками
    local cards = {}
    for _, d in ipairs(mmGui:GetDescendants()) do
        if d:IsA("ImageButton") or d:IsA("TextButton") then
            local img = d:FindFirstChildWhichIsA("ImageLabel")
            local id  = img and img.Image or d.Image
            if id and id ~= "" then
                table.insert(cards, { btn = d, id = id, idx = #cards + 1 })
            end
        end
    end

    if #cards < 4 then return end

    -- Групуємо по id, клікаємо пари
    local seen = {}
    for _, c in ipairs(cards) do
        if seen[c.id] then
            pcall(function() seen[c.id].btn:Activate() end)
            task.wait(0.2)
            pcall(function() c.btn:Activate() end)
            task.wait(0.4)
            seen[c.id] = nil
        else
            seen[c.id] = c
        end
    end
end

------------------------------------------------------------
-- AUTO-REJOIN (нова фіча)
------------------------------------------------------------
local TeleportService = game:GetService("TeleportService")

------------------------------------------------------------
-- SERVER HOP (стрибок на новий сервер для свіжих токенів)
------------------------------------------------------------
local function serverHop()
    debugToast("🚀 Server hop...", Color3.fromRGB(80, 120, 200), 3)
    webhook("🚀 Server hopping", 0x00BFFF)

    local req = (syn and syn.request) or http_request or request
              or (http and http.request)
    local placeId = game.PlaceId
    local currentJob = game.JobId

    -- Спроба 1: API публічних серверів
    if req then
        local cursor = ""
        for _ = 1, 5 do
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(placeId)
            if cursor ~= "" then url = url .. "&cursor=" .. cursor end
            local ok, response = pcall(req, { Url = url, Method = "GET" })
            if not ok or not response or not response.Body then break end

            local ok, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
            if not ok or not data or not data.data then break end

            -- Шукаємо сервер з вільним слотом
            for _, server in ipairs(data.data) do
                if server.id ~= currentJob
                   and server.playing < server.maxPlayers
                   and server.playing >= 1 then
                    pcall(function()
                        TeleportService:TeleportToPlaceInstance(placeId, server.id, LP)
                    end)
                    return true
                end
            end
            cursor = data.nextPageCursor or ""
            if cursor == "" then break end
        end
    end

    -- Спроба 2: TeleportToPlaceInstance з порожнім jobId → випадковий
    pcall(function() TeleportService:Teleport(placeId, LP) end)
    return true
end

-- Тригер: коли мало токенів спавниться (поле "захоплене" іншим гравцем)
-- або вручну з GUI
local function setupAutoRejoin()
    if not CFG.AutoRejoin then return end

    -- Перехоплюємо kick/disconnect
    game:GetService("CoreGui").RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(child)
        task.wait(0.5)
        if child.Name == "ErrorPrompt" then
            webhook("⚠️ Disconnected — rejoining", 0xFF6666)
            local placeId = game.PlaceId
            local jobId = game.JobId
            pcall(function() TeleportService:Teleport(placeId, LP) end)
        end
    end)

    -- Альтернатива через GuiService
    pcall(function()
        GuiService.ErrorMessageChanged:Connect(function(msg)
            if msg and msg ~= "" then
                task.wait(1)
                pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
            end
        end)
    end)
end

------------------------------------------------------------
-- STORMS DETECTION (нова фіча)
------------------------------------------------------------
local function detectStorms()
    if not CFG.DetectStorms then state.stormActive = false; return false end
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then state.stormActive = false; return false end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") then
            local t = (d.Text or ""):lower()
            if t:find("honey storm") or t:find("pollen storm")
               or t:find("mountain top") or t:find("blue blossom")
               or t:find("red rose") then
                state.stormActive = true
                return true, t
            end
        end
    end
    state.stormActive = false
    return false
end

------------------------------------------------------------
-- ANTI-AFK покращений
------------------------------------------------------------
task.spawn(function()
    while task.wait(60) do
        if state.running then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
                -- Маленький рух щоб гра нас бачила
                if hrp then
                    hrp.CFrame = hrp.CFrame * CFrame.new(0.1, 0, 0)
                    task.wait(0.1)
                    hrp.CFrame = hrp.CFrame * CFrame.new(-0.1, 0, 0)
                end
            end)
        end
    end
end)

------------------------------------------------------------
-- PRESETS (нова фіча) — збереження конфігів
------------------------------------------------------------
local function savePreset(name)
    if not writefile then return false end
    local data = {
        CFG = CFG,
        version = "1.1",
        savedAt = os.time(),
    }
    pcall(function()
        local json = HttpService:JSONEncode(data)
        writefile("bss_preset_" .. name .. ".json", json)
    end)
    return true
end

local function loadPreset(name)
    if not readfile then return false end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile("bss_preset_" .. name .. ".json"))
    end)
    if ok and data and data.CFG then
        for k, v in pairs(data.CFG) do CFG[k] = v end
        return true
    end
    return false
end

------------------------------------------------------------
-- ГАРЯЧІ КЛАВІШІ
------------------------------------------------------------
_G.BSSMacroGuiRef = _G.BSSMacroGuiRef or {}

UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    local kc = input.KeyCode
    if kc == Enum.KeyCode.K then state.running = false; warn("[Macro] STOP")
    elseif kc == Enum.KeyCode.P then state.paused = not state.paused; warn("[Macro] " .. (state.paused and "PAUSE" or "RESUME"))
    elseif kc == Enum.KeyCode.H then state.returnNow = true
    elseif kc == Enum.KeyCode.B then state.bossMode = not state.bossMode; warn("[Macro] Boss=" .. tostring(state.bossMode))
    elseif kc == Enum.KeyCode.M then state.mobMode = not state.mobMode; warn("[Macro] Mobs=" .. tostring(state.mobMode))
    elseif kc == Enum.KeyCode.J then state.craftNow = true; warn("[Macro] Craft now")
    elseif kc == Enum.KeyCode.RightShift or kc == Enum.KeyCode.Insert then
        -- Toggle GUI видимості
        local gui = _G.BSSMacroGuiRef.gui
        if gui and gui.Parent then
            local f = gui:FindFirstChildOfClass("Frame")
            if f then
                f.Visible = not f.Visible
                debugToast(f.Visible and "GUI показано" or "GUI сховано",
                           Color3.fromRGB(80, 120, 200), 1.5)
            end
        else
            debugToast("GUI не існує — переекс'ютуй скрипт",
                       Color3.fromRGB(220, 60, 60), 3)
        end
    end
end)

------------------------------------------------------------
-- INIT
------------------------------------------------------------
print("[Macro] Сканування...")
debugToast("Сканування гри...", Color3.fromRGB(80, 120, 200), 2)
local fields     = findFields()
local dispensers = CFG.DoDispensers and findDispensers() or {}
hive             = findHive()

local fieldCount = 0; for _ in pairs(fields) do fieldCount = fieldCount + 1 end
print(("[Macro] Fields=%d  Hive=%s  Dispensers=%d  UseItem=%s")
      :format(fieldCount, hive and hive.Name or "nil", #dispensers, tostring(UseItem ~= nil)))

------------------------------------------------------------
-- GUI
------------------------------------------------------------
local function buildGUI()
    -- PlayerGui — найнадійніший варіант, його точно видно
    local function getGuiParent()
        return LP:WaitForChild("PlayerGui"), "PlayerGui"
    end

    local parent, parentName = getGuiParent()
    print("[BSS Macro] GUI parent: " .. parentName)

    -- Видалити старий
    for _, p in ipairs({parent, LP:FindFirstChild("PlayerGui"), game:GetService("CoreGui")}) do
        if p then
            local old = p:FindFirstChild("BSSMacroGUI")
            if old then pcall(function() old:Destroy() end) end
        end
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BSSMacroGUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 9999            -- поверх усього іншого
    gui.IgnoreGuiInset = true          -- ігнорувати top-bar offset
    gui.Parent = parent

    -- Якщо не вдалось примонтувати — пробуємо ще раз через PlayerGui
    if not gui.Parent then
        warn("[BSS Macro] Primary parent failed → PlayerGui")
        gui.Parent = LP:WaitForChild("PlayerGui")
    end

    -- Перевірка що ScreenGui реально активний
    if not gui.Parent then
        warn("[BSS Macro] КРИТИЧНО: не вдалось примонтувати GUI взагалі!")
        return
    end

    -- Зберегти референс для toggle-хоткея
    _G.BSSMacroGuiRef = _G.BSSMacroGuiRef or {}
    _G.BSSMacroGuiRef.gui = gui

    -- АДАПТИВНІ РОЗМІРИ
    local W, H, BTN_H, TITLE_H, FONT, PAD
    if IS_SMALL_SCREEN then
        -- Мобільний UI: вище кнопки, більший текст, ширше
        W       = math.min(VP.X * 0.8, 320)
        H       = math.min(VP.Y * 0.85, 520)
        BTN_H   = 38
        TITLE_H = 42
        FONT    = 14
        PAD     = 8
    else
        -- Desktop
        W, H    = 280, 430
        BTN_H   = 28
        TITLE_H = 32
        FONT    = 13
        PAD     = 6
    end

    local main = Instance.new("Frame", gui)
    main.Size = UDim2.new(0, W, 0, H)
    main.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
    main.ZIndex = 100
    main.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(255, 200, 60); stroke.Thickness = 1.5

    local title = Instance.new("TextLabel", main)
    title.Size = UDim2.new(1, 0, 0, TITLE_H)
    title.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
    title.BorderSizePixel = 0
    title.Text = PLATFORM.Mobile and "🐝 BSS Macro 📱" or "🐝  BSS Macro"
    title.Font = Enum.Font.GothamBold
    title.TextSize = FONT + 2
    title.TextColor3 = Color3.fromRGB(25, 25, 25)
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)

    -- Кнопка згорнути (більша на мобілці)
    local minBtnSize = IS_SMALL_SCREEN and 36 or 28
    local minBtn = Instance.new("TextButton", title)
    minBtn.Size = UDim2.new(0, minBtnSize, 0, minBtnSize)
    minBtn.Position = UDim2.new(1, -(minBtnSize+4), 0, (TITLE_H-minBtnSize)/2)
    minBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    minBtn.Text = "—"; minBtn.TextColor3 = Color3.new(1,1,1)
    minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = FONT + 2
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

    -- SCROLLING FRAME для контенту (важливо на маленьких екранах)
    local content = Instance.new("ScrollingFrame", main)
    content.Position = UDim2.new(0, 0, 0, TITLE_H)
    content.Size = UDim2.new(1, 0, 1, -TITLE_H)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = IS_SMALL_SCREEN and 6 or 4
    content.ScrollBarImageColor3 = Color3.fromRGB(255, 200, 60)
    content.CanvasSize = UDim2.new(0, 0, 0, 0)  -- авто
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    content.ScrollingDirection = Enum.ScrollingDirection.Y

    local layout = Instance.new("UIListLayout", content)
    layout.Padding = UDim.new(0, PAD)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    local pad = Instance.new("UIPadding", content)
    pad.PaddingTop = UDim.new(0, PAD)
    pad.PaddingBottom = UDim.new(0, PAD)

    minBtn.MouseButton1Click:Connect(function()
        content.Visible = not content.Visible
        main.Size = content.Visible and UDim2.new(0,W,0,H) or UDim2.new(0,W,0,TITLE_H)
    end)

    -- Зберегти параметри в замиканні для використання в makeToggle/makeButton нижче
    _G.BSSMacroGuiRef.BTN_H = BTN_H
    _G.BSSMacroGuiRef.FONT  = FONT

    local order = 0
    local function nextOrder() order = order + 1; return order end

    local function makeToggle(label, getVal, setVal)
        local btn = Instance.new("TextButton", content)
        btn.Size = UDim2.new(1, -16, 0, BTN_H)
        btn.LayoutOrder = nextOrder()
        btn.Font = Enum.Font.Gotham
        btn.TextSize = FONT
        btn.AutoButtonColor = false
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        local function refresh()
            local v = getVal()
            btn.Text = (v and "✓  " or "✗  ") .. label
            btn.BackgroundColor3 = v and Color3.fromRGB(60, 140, 80) or Color3.fromRGB(55, 55, 65)
            btn.TextColor3 = Color3.new(1, 1, 1)
        end
        -- На мобілці працює і Activated, і MouseButton1Click
        local function handler() setVal(not getVal()); refresh() end
        btn.MouseButton1Click:Connect(handler)
        btn.Activated:Connect(handler)
        refresh()
        return btn, refresh
    end

    local function makeButton(label, color, fn)
        local btn = Instance.new("TextButton", content)
        btn.Size = UDim2.new(1, -16, 0, BTN_H)
        btn.LayoutOrder = nextOrder()
        btn.BackgroundColor3 = color
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = FONT
        btn.Text = label
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        btn.MouseButton1Click:Connect(fn)
        btn.Activated:Connect(fn)
        return btn
    end

    local function makeLabel(text)
        local l = Instance.new("TextLabel", content)
        l.Size = UDim2.new(1, -16, 0, IS_SMALL_SCREEN and 28 or 18)
        l.LayoutOrder = nextOrder()
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.Gotham
        l.TextSize = FONT - 1
        l.TextColor3 = Color3.fromRGB(180, 180, 180)
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextWrapped = true
        l.Text = text
        return l
    end

    -- Колапсибельний розділ (як в Atlas / Owl Hub)
    local sectionState = {}  -- name -> {expanded=bool, items={}}
    local function makeSection(title, defaultOpen)
        if defaultOpen == nil then defaultOpen = true end

        local header = Instance.new("TextButton", content)
        header.Size = UDim2.new(1, -8, 0, BTN_H + 2)
        header.LayoutOrder = nextOrder()
        header.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        header.BorderSizePixel = 0
        header.Font = Enum.Font.GothamBold
        header.TextSize = FONT + 1
        header.TextColor3 = Color3.fromRGB(255, 200, 60)
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.AutoButtonColor = false
        Instance.new("UICorner", header).CornerRadius = UDim.new(0, 6)
        local pad = Instance.new("UIPadding", header)
        pad.PaddingLeft = UDim.new(0, 10)

        local items = {}
        local sec = { expanded = defaultOpen, items = items }
        sectionState[title] = sec

        local function refresh()
            header.Text = (sec.expanded and "▼  " or "▶  ") .. title
            for _, it in ipairs(items) do it.Visible = sec.expanded end
        end
        header.MouseButton1Click:Connect(function()
            sec.expanded = not sec.expanded; refresh()
        end)
        header.Activated:Connect(function()
            sec.expanded = not sec.expanded; refresh()
        end)
        refresh()

        return {
            add = function(element)
                table.insert(items, element)
                element.Visible = sec.expanded
            end
        }
    end

    local function makeDropdown(label, options, getVal, setVal)
        local box = Instance.new("Frame", content)
        box.Size = UDim2.new(1, -16, 0, 28)
        box.LayoutOrder = nextOrder()
        box.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

        local btn = Instance.new("TextButton", box)
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 12
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Text = label .. ": " .. tostring(getVal() or "—")

        local listFrame = Instance.new("ScrollingFrame", main)
        listFrame.Size = UDim2.new(0, 240, 0, math.min(#options * 26 + 6, 180))
        listFrame.BackgroundColor3 = Color3.fromRGB(35, 37, 45)
        listFrame.BorderSizePixel = 0
        listFrame.Visible = false
        listFrame.ZIndex = 5
        listFrame.CanvasSize = UDim2.new(0, 0, 0, #options * 26 + 6)
        listFrame.ScrollBarThickness = 4
        Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 6)
        local ll = Instance.new("UIListLayout", listFrame)
        ll.Padding = UDim.new(0, 2)

        for _, opt in ipairs(options) do
            local b = Instance.new("TextButton", listFrame)
            b.Size = UDim2.new(1, -8, 0, 24)
            b.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
            b.TextColor3 = Color3.new(1, 1, 1)
            b.Font = Enum.Font.Gotham
            b.TextSize = 12
            b.Text = tostring(opt)
            b.ZIndex = 6
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
            b.MouseButton1Click:Connect(function()
                setVal(opt)
                btn.Text = label .. ": " .. tostring(opt)
                listFrame.Visible = false
            end)
        end

        btn.MouseButton1Click:Connect(function()
            local p = box.AbsolutePosition - main.AbsolutePosition
            listFrame.Position = UDim2.new(0, p.X, 0, p.Y + 30)
            listFrame.Visible = not listFrame.Visible
        end)
    end

    -- Статус
    local statusLbl = Instance.new("TextLabel", content)
    statusLbl.Size = UDim2.new(1, -16, 0, 54)
    statusLbl.LayoutOrder = nextOrder()
    statusLbl.BackgroundColor3 = Color3.fromRGB(35, 37, 45)
    statusLbl.TextColor3 = Color3.fromRGB(180, 255, 180)
    statusLbl.Font = Enum.Font.GothamBold
    statusLbl.TextSize = 11
    statusLbl.Text = "Статус: запуск..."
    statusLbl.TextWrapped = true
    Instance.new("UICorner", statusLbl).CornerRadius = UDim.new(0, 6)

    -- =========================================================
    -- РОЗДІЛИ
    -- =========================================================

    -- ── MAIN ──
    local secMain = makeSection("⚙ Main", true)
    secMain.add(makeToggle("Running",         function() return state.running end,    function(v) state.running = v end))
    secMain.add(makeToggle("Pause auto-farm", function() return state.paused end,     function(v) state.paused = v end))

    local fieldOpts = { "Auto" }
    for n in pairs(fields) do table.insert(fieldOpts, n) end
    secMain.add(makeDropdown("Field", fieldOpts,
        function() return CFG.PreferredField or "Auto" end,
        function(v) CFG.PreferredField = (v ~= "Auto") and v or nil end))

    -- ── FARMING ──
    local secFarm = makeSection("🌻 Farming", true)
    secFarm.add(makeToggle("Collect tokens", function() return CFG.UseTokens end,    function(v) CFG.UseTokens = v end))
    secFarm.add(makeToggle("Dispensers",     function() return CFG.DoDispensers end, function(v) CFG.DoDispensers = v end))
    secFarm.add(makeToggle("Planters",       function() return CFG.DoPlanters end,   function(v) CFG.DoPlanters = v end))
    secFarm.add(makeToggle("Sprouts",        function() return CFG.DoSprouts end,    function(v) CFG.DoSprouts = v end))
    secFarm.add(makeToggle("Use buffs",      function() return CFG.DoBuffs end,      function(v) CFG.DoBuffs = v end))
    secFarm.add(makeToggle("Crafting (Blender/Stickers)", function() return CFG.DoCrafting end, function(v) CFG.DoCrafting = v end))

    -- ── COMBAT ──
    local secCombat = makeSection("⚔ Combat", false)
    secCombat.add(makeToggle("Hunt mobs",    function() return state.mobMode end,    function(v) state.mobMode = v end))
    secCombat.add(makeToggle("Boss mode",    function() return state.bossMode end,   function(v) state.bossMode = v end))
    secCombat.add(makeToggle("Flee killers", function() return CFG.FleeFromKillers end, function(v) CFG.FleeFromKillers = v end))
    secCombat.add(makeDropdown("Target boss", BOSS_NAMES,
        function() return CFG.PreferredBoss end,
        function(v) CFG.PreferredBoss = v end))

    -- ── TOKENS (пресети) ──
    local secTokens = makeSection("🎫 Tokens (auto-priority)", false)
    secTokens.add(makeToggle("✅ Збирати токени",
        function() return CFG.UseTokens end,
        function(v) CFG.UseTokens = v end))

    local function applyPreset(preset)
        for name in pairs(TOKEN_DB) do TOKEN_FILTERS[name] = false end

        if preset == "All" then
            for name in pairs(TOKEN_DB) do TOKEN_FILTERS[name] = true end
        elseif preset == "Best" then
            -- Топ-цінні (gameValue >= 80)
            for name, info in pairs(TOKEN_DB) do
                if info.gameValue >= 80 then TOKEN_FILTERS[name] = true end
            end
        elseif preset == "Gather" then
            for name, info in pairs(TOKEN_DB) do
                if info.category == "gather" then TOKEN_FILTERS[name] = true end
            end
        elseif preset == "Battle" then
            for name, info in pairs(TOKEN_DB) do
                if info.category == "battle" then TOKEN_FILTERS[name] = true end
            end
        elseif preset == "No events" then
            -- Все крім event-bee-exclusive
            for name, info in pairs(TOKEN_DB) do
                if info.category ~= "event" then TOKEN_FILTERS[name] = true end
            end
        elseif preset == "Events only" then
            for name, info in pairs(TOKEN_DB) do
                if info.category == "event" then TOKEN_FILTERS[name] = true end
            end
        end
        CFG.TokenPreset = preset
    end

    CFG.TokenPreset = CFG.TokenPreset or "All"

    secTokens.add(makeDropdown("Preset",
        { "All", "Best", "Gather", "Battle", "No events", "Events only", "Off" },
        function() return CFG.TokenPreset end,
        function(v) applyPreset(v) end))

    secTokens.add(makeLabel(
        "All — всі 43 ability tokens\n" ..
        "Best — найцінніші (Token Link, Bomb, Haste...)\n" ..
        "Gather — лише збір pollen (Haste, Focus, Boost...)\n" ..
        "Battle — атакуючі (Bomb, Rage, Inferno, Mark...)\n" ..
        "No events — всі крім event-exclusive\n" ..
        "Events only — Beesmas/Holiday tokens\n" ..
        "Off — не підбирати"
    ))

    -- ── QUESTS / EXTRAS ──
    local secQuests = makeSection("📜 Quests & Extras", false)
    secQuests.add(makeToggle("Quests (bears)", function() return CFG.DoQuests end,     function(v) CFG.DoQuests = v end))
    secQuests.add(makeToggle("Wealth Clock",   function() return CFG.DoWealthClock end,function(v) CFG.DoWealthClock = v end))
    secQuests.add(makeToggle("Memory Match",   function() return CFG.DoMemoryMatch end,function(v) CFG.DoMemoryMatch = v end))
    secQuests.add(makeToggle("Daily Bonus",    function() return CFG.DoDailyBonus end, function(v) CFG.DoDailyBonus = v end))
    secQuests.add(makeToggle("Sticker Stack",  function() return CFG.DoStickerStack end,function(v) CFG.DoStickerStack = v end))

    -- ── ATLAS-STYLE ──
    local secAtlas = makeSection("⭐ Atlas Features", false)
    secAtlas.add(makeToggle("Auto Beequips",      function() return CFG.DoBeequips end,    function(v) CFG.DoBeequips = v end))
    secAtlas.add(makeToggle("Feed bees",          function() return CFG.DoFeedBees end,    function(v) CFG.DoFeedBees = v end))
    secAtlas.add(makeToggle("Auto-codes",         function() return CFG.DoCodes end,       function(v) CFG.DoCodes = v end))
    secAtlas.add(makeToggle("Cuckoo drops",       function() return CFG.DoCuckoo end,      function(v) CFG.DoCuckoo = v end))
    secAtlas.add(makeToggle("Mondo Belly escape", function() return CFG.DoMondoBelly end,  function(v) CFG.DoMondoBelly = v end))
    secAtlas.add(makeToggle("Use Haste",          function() return CFG.DoHaste end,       function(v) CFG.DoHaste = v end))
    secAtlas.add(makeToggle("Mountain Top",       function() return CFG.DoMountainTop end, function(v) CFG.DoMountainTop = v end))
    secAtlas.add(makeToggle("Goo deposits",       function() return CFG.DoGoo end,         function(v) CFG.DoGoo = v end))
    secAtlas.add(makeToggle("Honeysuckle",        function() return CFG.DoHoneysuckle end, function(v) CFG.DoHoneysuckle = v end))
    secAtlas.add(makeToggle("Sea Buoy",           function() return CFG.DoBuoy end,        function(v) CFG.DoBuoy = v end))
    secAtlas.add(makeToggle("Hunt Vicious Bee",   function() return CFG.DoVicious end,     function(v) CFG.DoVicious = v end))
    secAtlas.add(makeToggle("Stump swap fields",  function() return CFG.DoStumpField end,  function(v) CFG.DoStumpField = v end))

    -- ── MOVEMENT ──
    local secMove = makeSection("🚶 Movement", false)
    secMove.add(makeToggle("Walk (Atlas-style)",     function() return CFG.UseWalking end,    function(v) CFG.UseWalking = v end))
    secMove.add(makeToggle("Pathfinding",            function() return CFG.UsePathfinding end,function(v) CFG.UsePathfinding = v end))
    secMove.add(makeToggle("Teleport fallback",      function() return CFG.TeleportFallback end,function(v) CFG.TeleportFallback = v end))

    -- ── STATS / MISC ──
    local secStats = makeSection("📊 Stats & Misc", false)
    secStats.add(makeToggle("Stats tracker", function() return CFG.TrackStats end,   function(v) CFG.TrackStats = v end))
    secStats.add(makeToggle("Detect storms", function() return CFG.DetectStorms end, function(v) CFG.DetectStorms = v end))
    secStats.add(makeToggle("Auto-rejoin",   function() return CFG.AutoRejoin end,   function(v) CFG.AutoRejoin = v end))

    -- ── ACTIONS ──
    local secAct = makeSection("⚡ Actions", true)
    secAct.add(makeButton("→ Hive & Convert", Color3.fromRGB(200, 140, 50), function()
        state.returnNow = true
    end))
    secAct.add(makeButton("Craft now", Color3.fromRGB(100, 120, 220), function()
        state.craftNow = true
    end))
    secAct.add(makeButton("🚀 Server Hop", Color3.fromRGB(80, 160, 200), function()
        task.spawn(serverHop)
    end))
    secAct.add(makeButton("⟳ Rejoin same server", Color3.fromRGB(140, 100, 180), function()
        pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
    end))
    secAct.add(makeButton("STOP", Color3.fromRGB(200, 60, 60), function()
        state.running = false
    end))

    if PLATFORM.Mobile then
        makeLabel("📱 Mobile mode: тапай по кнопках. Жовте коло справа = показати/сховати меню")
    else
        makeLabel("Hotkeys: K stop · P pause · H hive · B boss · M mobs · J craft · RShift hide")
    end

    -- Live статус
    task.spawn(function()
        while gui.Parent do
            local fill = readBagFill()
            local fieldName = CFG.PreferredField or findCurrentField(fields) or "—"
            statusLbl.Text = string.format(
                "Поле: %s  |  Мішок: %d%%\nЧас: %s  |  Honey/h: %s\nDanger: %s  |  Pause: %s",
                fieldName, math.floor(fill * 100),
                sessionTime(),
                tostring(honeyPerHour()),
                tostring(state.inDanger), tostring(state.paused)
            )
            task.wait(1)
        end
    end)

    ------------------------------------------------------------
    -- FLOATING TOGGLE BUTTON (для мобілки і для зручності на ПК)
    ------------------------------------------------------------
    local fabSize = IS_SMALL_SCREEN and 60 or 44
    local fab = Instance.new("TextButton", gui)
    fab.Name = "BSSFloatingToggle"
    fab.Size = UDim2.new(0, fabSize, 0, fabSize)
    fab.Position = UDim2.new(1, -(fabSize + 16), 0.5, -fabSize/2)
    fab.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
    fab.TextColor3 = Color3.fromRGB(25, 25, 25)
    fab.Font = Enum.Font.GothamBold
    fab.TextSize = IS_SMALL_SCREEN and 24 or 18
    fab.Text = "🐝"
    fab.AutoButtonColor = true
    fab.Active = true
    fab.Draggable = true   -- можна перетягувати на телефоні
    fab.ZIndex = 200
    Instance.new("UICorner", fab).CornerRadius = UDim.new(1, 0)  -- кругла
    local fabStroke = Instance.new("UIStroke", fab)
    fabStroke.Color = Color3.fromRGB(180, 140, 30); fabStroke.Thickness = 2

    local function toggleMain()
        main.Visible = not main.Visible
        if main.Visible then
            fab.Text = "✕"
            fab.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
            fab.TextColor3 = Color3.new(1, 1, 1)
        else
            fab.Text = "🐝"
            fab.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
            fab.TextColor3 = Color3.fromRGB(25, 25, 25)
        end
    end
    fab.MouseButton1Click:Connect(toggleMain)
    fab.Activated:Connect(toggleMain)

    -- Pulsing анімація щоб кнопку було помітно при першому запуску
    task.spawn(function()
        for i = 1, 6 do
            if not fab.Parent then return end
            fab.Size = UDim2.new(0, fabSize + 8, 0, fabSize + 8)
            task.wait(0.3)
            fab.Size = UDim2.new(0, fabSize, 0, fabSize)
            task.wait(0.3)
        end
    end)
end

local guiOk, guiErr = pcall(buildGUI)
if not guiOk then
    warn("[BSS Macro] GUI error: " .. tostring(guiErr))
    debugToast("❌ GUI ERROR: " .. tostring(guiErr):sub(1, 60),
               Color3.fromRGB(220, 60, 60), 10)
else
    debugToast("✓ GUI створено", Color3.fromRGB(60, 180, 100), 3)
end

eSpam()
dangerWatcher()

------------------------------------------------------------
-- ГОЛОВНИЙ ЦИКЛ
------------------------------------------------------------
-- Запуск auto-rejoin watcher
pcall(setupAutoRejoin)

webhook("🚀 Macro started", 0x66FF66)

while state.running do
    local ok, err = pcall(function()
        useBuffs()
        if CFG.TrackStats then readGameStats() end

        -- Storm boost (детект і використання)
        local storm, stormText = detectStorms()
        if storm then
            print("[Macro] Storm detected: " .. (stormText or ""))
            webhook("⛈️ Storm: " .. (stormText or ""), 0x00BFFF)
        end

        -- Memory Match minigame
        solveMemoryMatch()

        local fn = CFG.PreferredField or findCurrentField(fields)
        local fm = fn and fields[fn] or select(2, next(fields))
        if fm then
            print("[Macro] Field: " .. fm.Name)
            farmField(fm)
        end

        state.returnNow = false

        if hive then convertAtHive() end

        if CFG.DoDispensers and #dispensers > 0 then
            visitDispensers(dispensers)
            if hive then convertAtHive() end
        end

        if state.mobMode then huntMobs(); if hive then convertAtHive() end end
        if state.bossMode then
            fightBoss()
            stats.bossesKilled = stats.bossesKilled + 1
        end

        processPlanters()
        processCrafting()
        processQuests()
        processSprouts()
        claimWealthClock()

        -- Atlas-style фічі
        processBeequips()
        feedBees()
        claimStickerStack()
        claimDailyBonus()
        claimGoo()
        claimHoneysuckle()
        claimBuoy()
        activateHaste()
        goMountainTop()
        collectCuckooDrops()
        huntVicious()
        redeemCodes()
    end)
    if not ok then
        warn("[Macro] Err: " .. tostring(err))
        webhook("❌ Error: " .. tostring(err):sub(1, 200), 0xFF0000)
        task.wait(2)
    end
    task.wait(0.4)
end

webhook("⏹️ Macro stopped. Honey: " .. stats.honeyMade .. " | Time: " .. sessionTime(), 0xFF6666)

print("[Macro] Завершено.")
