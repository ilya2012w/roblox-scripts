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
    UsePathfinding   = true,            -- ввімкнено за замовч — обходить декор
    WalkAcceptRadius = 5,
    WalkTimeout      = 6,
    TeleportFallback = true,
    UnstuckTime      = 2,                -- якщо не рухається 2с — unstuck

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

-- Реальний рух humanoid'ом з unstuck-логікою
local function walkToPoint(pos)
    if not hum or not hrp then return false end
    local t0 = tick()
    local lastPos = hrp.Position
    local stuckSince = tick()
    local jumpAttempts = 0

    hum:MoveTo(pos)

    while tick() - t0 < CFG.WalkTimeout do
        if not state.running then return false end
        local cur = hrp.Position
        local d = (cur - pos).Magnitude
        if d <= CFG.WalkAcceptRadius then return true end

        -- UNSTUCK: чи рухаємось взагалі?
        local moved = (cur - lastPos).Magnitude
        if moved < 0.5 then
            if tick() - stuckSince > CFG.UnstuckTime then
                jumpAttempts = jumpAttempts + 1
                if jumpAttempts <= 2 then
                    -- Спроба 1-2: стрибок
                    hum.Jump = true
                    task.wait(0.3)
                    hum:MoveTo(pos)
                    stuckSince = tick()
                else
                    -- Спроба 3+: телепорт на 5 одиниць вгору і вперед
                    local dir = (pos - cur)
                    if dir.Magnitude > 0 then dir = dir.Unit else dir = Vector3.new(0,0,1) end
                    hrp.CFrame = CFrame.new(cur + Vector3.new(0, 5, 0) + dir * 3)
                    task.wait(0.2)
                    hum:MoveTo(pos)
                    stuckSince = tick()
                    if jumpAttempts > 5 then return false end  -- здаємось
                end
            end
        else
            stuckSince = tick()
            jumpAttempts = 0
        end
        lastPos = cur

        -- Нагадуємо ціль кожну секунду
        if (tick() - t0) % 1 < 0.1 then hum:MoveTo(pos) end
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

-- Шукає вже claim-нутий мій вулик
local function findMyHive()
    local hives = Workspace:FindFirstChild("Hives") or Workspace:FindFirstChild("Honeycombs")
    if not hives then return nil end
    for _, h in ipairs(hives:GetChildren()) do
        local owner = h:FindFirstChild("Owner")
        if (owner and owner.Value == LP) or h.Name == LP.Name then return h end
    end
    return nil
end

-- Шукає вільний вулик щоб claim'нути
local function findEmptyHive()
    local hives = Workspace:FindFirstChild("Hives") or Workspace:FindFirstChild("Honeycombs")
    if not hives then return nil end
    for _, h in ipairs(hives:GetChildren()) do
        local owner = h:FindFirstChild("Owner")
        if owner and (owner.Value == nil or owner.Value == "") then
            return h
        end
    end
    return nil
end

-- Ходьба до об'єкта з усіма захистами (pathfinding + unstuck)
-- Використовується для важливих цілей як hive, dispenser і т.д.
local function walkToObject(target, options)
    options = options or {}
    local cf = targetToCFrame(target)
    if not cf or not hrp or not hrp.Parent then return false end

    local pos = cf.Position
    -- Якщо це Model з BoundingBox — встаємо ЗВЕРХУ на нього (для hive)
    if options.onTop and typeof(target) == "Instance" then
        local ok, model_cf, size = pcall(function() return target:GetBoundingBox() end)
        if ok and size then
            pos = model_cf.Position + Vector3.new(0, size.Y/2 + 3, 0)
        end
    end

    -- Дуже близько вже? Просто стоїмо
    local d = (hrp.Position - pos).Magnitude
    if d <= 6 then return true end

    setSpeed(CFG.WalkSpeed)

    -- Кілька спроб ходити, з ескалацією
    for attempt = 1, options.maxAttempts or 3 do
        if not state.running then return false end

        local reached
        if CFG.UsePathfinding and attempt < 3 then
            reached = walkPath(pos)
        else
            reached = walkToPoint(pos)
        end

        if reached then return true end

        -- Не дійшли — спробуємо обходом
        if attempt < (options.maxAttempts or 3) then
            -- Стрибок + 2с на recover
            if hum then hum.Jump = true end
            task.wait(1)
            -- Якщо взагалі застрягли — телепорт на 30 одиниць ближче і знову ходити
            local toward = (pos - hrp.Position)
            if toward.Magnitude > 50 then
                local nearer = pos - toward.Unit * 30
                hrp.CFrame = CFrame.new(nearer + Vector3.new(0, 5, 0))
                task.wait(0.3)
            end
        end
    end

    -- Усі спроби провалились — тільки тут останній fallback
    if options.teleportFallback then
        hrp.CFrame = CFrame.new(pos)
        task.wait(0.3)
        return true
    end
    return false
end

-- Старий tpHard тепер просто wrapper (для backward compat)
local function tpHard(target)
    return walkToObject(target, { onTop = true, maxAttempts = 3, teleportFallback = true })
end

-- Шукає Claim ProximityPrompt біля гравця
local function tryClaimPrompts()
    for _, prompt in ipairs(Workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local parent = prompt.Parent
            local ok, pos = pcall(function()
                if parent:IsA("BasePart") then return parent.Position end
                return parent:GetPivot().Position
            end)
            if ok and (hrp.Position - pos).Magnitude < 25 then
                local txt = (prompt.ActionText or "") .. " " .. (prompt.ObjectText or "")
                if txt:lower():find("claim") or txt:lower():find("hive") then
                    pcall(function() fireproximityprompt(prompt) end)
                end
            end
        end
    end
end

-- Перевіряє чи реально на вулику стоїмо (для claim)
local function ensureHiveClaimed()
    local mine = findMyHive()
    if mine then
        print("[Macro] Hive вже claim-нутий: " .. mine.Name)
        return mine
    end

    print("[Macro] Hive не claim-нутий — шукаю вільний")
    debugToast("Шукаю вільний hive...", Color3.fromRGB(80, 120, 200), 3)

    local empty = findEmptyHive()
    if not empty then
        debugToast("❌ Нема вільних hive!", Color3.fromRGB(220, 60, 60), 4)
        warn("[Macro] Усі hive зайняті — макрос не зможе фармити")
        return nil
    end

    -- ХОДИМО до hive (з pathfinding + unstuck), TP лише як останній fallback
    debugToast("Йду до вулика...", Color3.fromRGB(80, 120, 200), 2)
    local reached = walkToObject(empty, {
        onTop = true,
        maxAttempts = 4,
        teleportFallback = true,  -- якщо геть не може дійти за 4 спроби
    })

    if not reached then
        debugToast("⚠ Не зміг дійти до hive", Color3.fromRGB(220, 80, 80), 4)
        return nil
    end

    task.wait(0.5)

    -- Спам усіх способів claim'у
    for attempt = 1, 15 do
        if not state.running then break end
        tap(0x45, 0.05)
        tryClaimPrompts()
        fireProximityPromptsNearby(25)

        for _, cd in ipairs(empty:GetDescendants()) do
            if cd:IsA("ClickDetector") then
                pcall(function() fireclickdetector(cd) end)
            end
        end

        mine = findMyHive()
        if mine then break end

        -- Якщо випали з hive — підходимо знову (walk, не tp)
        local hivePos = empty:GetPivot().Position
        if (hrp.Position - hivePos).Magnitude > 15 then
            walkToObject(empty, { onTop = true, maxAttempts = 1, teleportFallback = false })
        end
        task.wait(0.3)
    end

    if mine then
        debugToast("✓ Hive claimed: " .. mine.Name, Color3.fromRGB(60, 180, 100), 3)
        webhook("🏠 Claimed hive: " .. mine.Name, 0x66FF66)
        return mine
    else
        debugToast("⚠ Не вдалося claim автоматично — натисни E на hive", Color3.fromRGB(220, 140, 50), 5)
        return empty
    end
end

-- Стара назва для backward compat
local function findHive() return findMyHive() end

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

------------------------------------------------------------
-- 🧠 BRAIN: Token Heatmap — пам'ятає де токени спавняться частіше
------------------------------------------------------------
local heatmap = {}  -- { [fieldName] = { [gridKey] = count } }
local HEATMAP_GRID = 30  -- розмір клітинки в одиницях

local function heatKey(pos)
    return math.floor(pos.X / HEATMAP_GRID) .. ":" .. math.floor(pos.Z / HEATMAP_GRID)
end

local function recordTokenSpawn(fieldName, pos)
    if not heatmap[fieldName] then heatmap[fieldName] = {} end
    local k = heatKey(pos)
    heatmap[fieldName][k] = (heatmap[fieldName][k] or 0) + 1
end

-- Найгарячіша точка на полі
local function hottestSpot(fieldName)
    if not heatmap[fieldName] then return nil end
    local bestKey, bestCount = nil, 0
    for k, c in pairs(heatmap[fieldName]) do
        if c > bestCount then bestCount = c; bestKey = k end
    end
    if not bestKey then return nil end
    local gx, gz = bestKey:match("(-?%d+):(-?%d+)")
    return Vector3.new(tonumber(gx) * HEATMAP_GRID + HEATMAP_GRID/2,
                       hrp.Position.Y,
                       tonumber(gz) * HEATMAP_GRID + HEATMAP_GRID/2)
end

------------------------------------------------------------
-- 🧠 BRAIN: Bee Reader — читає твоїх бджіл
------------------------------------------------------------
local beeComposition = { types = {}, count = 0, pollenAffinity = {}, mythics = 0, legendaries = 0 }

local function readBeeComposition()
    beeComposition = { types = {}, count = 0, pollenAffinity = {}, mythics = 0, legendaries = 0 }
    -- Бджоли зберігаються в Workspace.Bees або як part of hive
    local hives = Workspace:FindFirstChild("Hives") or Workspace:FindFirstChild("Honeycombs")
    if not hives or not hive then return end

    for _, b in ipairs(hive:GetDescendants()) do
        if b:IsA("Model") and b:GetAttribute("Type") then
            local bType = b:GetAttribute("Type")
            beeComposition.types[bType] = (beeComposition.types[bType] or 0) + 1
            beeComposition.count = beeComposition.count + 1
            local rarity = b:GetAttribute("Rarity") or ""
            if rarity == "Mythic" then beeComposition.mythics = beeComposition.mythics + 1 end
            if rarity == "Legendary" then beeComposition.legendaries = beeComposition.legendaries + 1 end
        end
    end
    -- Pollen affinity: припускаємо що Brave/Demo/Tabby/Music/Frosty люблять red, тощо
    -- (спрощено)
end

------------------------------------------------------------
-- 🧠 BRAIN: Quest Parser — читає поточний quest
------------------------------------------------------------
local currentQuest = { text = "", giver = "", objective = nil }

local function parseCurrentQuest()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") then
            local t = d.Text or ""
            -- Шукаємо текст виду "Bring X pollen" / "Collect X token" / "Defeat X"
            local poll = t:match("(%d[%d,]*)%s*Pollen")
            local tok  = t:match("Collect%s+(%d+)%s*([%w%s]+)")
            local def  = t:match("Defeat%s+([%w%s]+)")
            if poll or tok or def then
                currentQuest.text = t
                if poll then currentQuest.objective = { type = "pollen", amount = tonumber((poll:gsub(",", ""))) } end
                if tok  then currentQuest.objective = { type = "token", name = tok, amount = tonumber(t:match("(%d+)")) } end
                if def  then currentQuest.objective = { type = "kill", target = def } end
                return
            end
        end
    end
end

------------------------------------------------------------
-- 🧠 BRAIN: Bag Predictor — ETA до повного мішка
------------------------------------------------------------
local bagHistory = {}  -- { {time, fill}, ... }

local function recordBagSample()
    local f = readBagFill() or 0
    table.insert(bagHistory, { tick(), f })
    if #bagHistory > 60 then table.remove(bagHistory, 1) end
end

-- Скільки секунд лишилось до повного мішка (приблизно)
local function bagETA()
    if #bagHistory < 5 then return math.huge end
    local last = bagHistory[#bagHistory]
    local first = bagHistory[1]
    local dt = last[1] - first[1]
    local df = last[2] - first[2]
    if dt < 10 or df <= 0 then return math.huge end
    local rate = df / dt  -- fill per second
    local remaining = (CFG.BagFullThreshold - last[2]) / rate
    return math.max(0, remaining)
end

-- Фоновий sampler
task.spawn(function()
    while task.wait(5) do
        if state.running then pcall(recordBagSample) end
    end
end)

------------------------------------------------------------
-- 🧠 BRAIN: Risk Assessor — оцінка небезпеки локації
------------------------------------------------------------
local function assessRisk()
    -- 0 = безпечно, 100 = смерть скоро
    local risk = 0
    local killers = findKillersNearby()
    risk = risk + #killers * 30

    -- HP перевірка
    if hum and hum.MaxHealth > 0 then
        local hpPercent = hum.Health / hum.MaxHealth
        if hpPercent < 0.3 then risk = risk + 40
        elseif hpPercent < 0.6 then risk = risk + 15 end
    end

    -- На небезпечних полях (Mountain Top, Coconut, Pepper) дефолтно вищий ризик
    local curField = findCurrentField(fields)
    if curField then
        local n = curField:lower()
        if n:find("mountain") or n:find("coconut") or n:find("pepper")
           or n:find("cactus") or n:find("rose") then
            risk = risk + 10
        end
    end

    return math.min(100, risk)
end

------------------------------------------------------------
-- 🧠 BRAIN: Field Depletion Detector
------------------------------------------------------------
local fieldDepletion = {}  -- { [fieldName] = { lastSpawnTime, recentSpawns } }

local function recordFieldActivity(fieldName, tokensFound)
    if not fieldDepletion[fieldName] then
        fieldDepletion[fieldName] = { lastSpawnTime = tick(), recentSpawns = {} }
    end
    local fd = fieldDepletion[fieldName]
    if tokensFound > 0 then
        fd.lastSpawnTime = tick()
        table.insert(fd.recentSpawns, { tick(), tokensFound })
        if #fd.recentSpawns > 20 then table.remove(fd.recentSpawns, 1) end
    end
end

local function isFieldDepleted(fieldName)
    local fd = fieldDepletion[fieldName]
    if not fd then return false end
    -- Якщо за останні 30с не було жодного нового токена — поле "вижате"
    return (tick() - fd.lastSpawnTime) > 30
end

------------------------------------------------------------
-- 🧠 BRAIN: Smart Token Combos
-- Якщо бачимо Token Link + інші токени поряд — спочатку Link потім інші
------------------------------------------------------------
local function detectTokenCombo()
    local toks = findTokens(150)
    if #toks < 3 then return nil end
    local hasLink, hasStorm = false, false
    for _, t in ipairs(toks) do
        if t.kind == "Token Link" then hasLink = true end
        if t.kind == "Token Storm" then hasStorm = true end
    end
    if hasLink or hasStorm then return "combo" end
    return nil
end

------------------------------------------------------------
-- 🧠 BRAIN: Adaptive Farm Time
------------------------------------------------------------
local function adaptiveFarmTime()
    local eta = bagETA()
    if eta == math.huge then return 180 end
    return math.max(30, math.min(300, eta + 10))
end

------------------------------------------------------------
-- 🧠 BRAIN: COST-BENEFIT ANALYZER
-- Кожна дія має cost (час, ризик) і benefit (нагорода).
-- Бот вибирає максимальне benefit / cost.
------------------------------------------------------------
local actionEV = {}  -- exponential moving average of expected value

local function evaluateAction(name, expectedReward, expectedTimeCost, risk)
    risk = risk or 0
    local rawEV = expectedReward / math.max(1, expectedTimeCost) * (1 - risk / 100)
    -- EMA з alpha = 0.3 (адаптивне навчання)
    actionEV[name] = (actionEV[name] or rawEV) * 0.7 + rawEV * 0.3
    return actionEV[name]
end

-- Записати реальний outcome дії (для навчання)
local function recordOutcome(actionName, actualReward, actualTime)
    if not actionEV[actionName] then actionEV[actionName] = 0 end
    local actualEV = actualReward / math.max(1, actualTime)
    actionEV[actionName] = actionEV[actionName] * 0.8 + actualEV * 0.2
end

------------------------------------------------------------
-- 🧠 BRAIN: GOAL QUEUE — список цілей з пріоритетами
------------------------------------------------------------
local goals = {}  -- { {id, type, priority, expires, data}, ... }

local function addGoal(id, gType, priority, ttl, data)
    -- Не дублюємо
    for _, g in ipairs(goals) do
        if g.id == id then return end
    end
    table.insert(goals, {
        id = id, type = gType,
        priority = priority,
        expires = ttl and (tick() + ttl) or math.huge,
        data = data or {}
    })
end

local function removeGoal(id)
    for i = #goals, 1, -1 do
        if goals[i].id == id then table.remove(goals, i); return true end
    end
    return false
end

local function pruneGoals()
    local now = tick()
    for i = #goals, 1, -1 do
        if goals[i].expires < now then table.remove(goals, i) end
    end
end

local function topGoal()
    pruneGoals()
    table.sort(goals, function(a, b) return a.priority > b.priority end)
    return goals[1]
end

------------------------------------------------------------
-- 🧠 BRAIN: PLANNER — багатокроковий план
------------------------------------------------------------
local currentPlan = {}  -- черга наступних дій

local function planAhead()
    currentPlan = {}
    local bagFill = readBagFill() or 0
    local eta = bagETA()
    local risk = assessRisk()

    -- Якщо мішок майже повний → конверт → потім фарм
    if bagFill > 0.85 then
        table.insert(currentPlan, "CONVERTING")
        table.insert(currentPlan, "FARMING")
        return
    end

    -- Якщо є event-токени поряд (Storm/Token Link) → пріоритет
    if detectTokenCombo() then
        table.insert(currentPlan, "FARMING")  -- бо там же
        return
    end

    -- Якщо storm активний → фарм поки не закінчиться
    if state.stormActive then
        table.insert(currentPlan, "FARMING")
        table.insert(currentPlan, "CONVERTING")
        return
    end

    -- Низький мішок + великі ETA → можна зробити боса між
    if state.bossMode and bagFill < 0.4 and tick() - FSM.lastBoss > 900 then
        table.insert(currentPlan, "BOSS")
    end

    -- Раз на 10 хв claim extras
    if tick() - FSM.lastClaims > 600 then
        table.insert(currentPlan, "CLAIMING_EXTRAS")
    end

    -- Default
    table.insert(currentPlan, "FARMING")
end

------------------------------------------------------------
-- 🧠 BRAIN: SMART FLEEING — тікаємо в напрямку ВІД killer'а
------------------------------------------------------------
local function smartFlee()
    local killers = findKillersNearby()
    if #killers == 0 then
        if hive then tpTo(hive) end
        return
    end

    -- Усереднена позиція killer'ів
    local avgKiller = Vector3.new(0, 0, 0)
    for _, k in ipairs(killers) do
        local ok, p = pcall(function() return k:GetPivot().Position end)
        if ok then avgKiller = avgKiller + p end
    end
    avgKiller = avgKiller / #killers

    -- Напрямок ВІД killer'ів до hive
    local fleeDir = (hrp.Position - avgKiller).Unit
    local fleeTarget = hrp.Position + fleeDir * 200

    -- Спочатку рух у напрямку від killer'а
    tpRaw(fleeTarget)
    task.wait(0.3)
    -- Потім на hive
    if hive then tpTo(hive); task.wait(5) end
end

------------------------------------------------------------
-- 🧠 BRAIN: COMBO ORCHESTRATOR
-- Синхронізує дорогі баффи + storm + Token Link для максимуму
------------------------------------------------------------
local function attemptMegaCombo()
    -- Умови: storm активний, мішок майже пустий, є дорогі items
    if not state.stormActive then return false end
    if (readBagFill() or 0) > 0.3 then return false end

    print("[Brain] MEGA COMBO: storm + buffs + farm")
    webhook("⚡ MEGA COMBO activated", 0xFF00FF)

    -- 1) Активуємо всі buffs
    useBuffs()
    activateHaste()
    pcall(function() useItemByName("Glitter") end)
    pcall(function() useItemByName("Oil") end)
    pcall(function() useItemByName("Enzymes") end)
    pcall(function() useItemByName("Glue") end)

    -- 2) Біжимо на найкраще storm-поле
    local _, fm = chooseBestField(fields)
    if fm then farmField(fm) end
    return true
end

------------------------------------------------------------
-- 🧠 BRAIN: HP RECOVERY
------------------------------------------------------------
local function needsHpRecovery()
    if not hum or hum.MaxHealth <= 0 then return false end
    return (hum.Health / hum.MaxHealth) < 0.3
end

local function recoverHP()
    if not hum then return end
    print("[Brain] HP low → recover")
    if hive then tpTo(hive) end
    local t0 = tick()
    while hum.Health < hum.MaxHealth * 0.95 and tick() - t0 < 30 do
        task.wait(0.5)
    end
end

------------------------------------------------------------
-- 🧠 BRAIN: PREDICTIVE TOKEN SPAWN
-- На основі heatmap передбачає де токен з'явиться раніше всіх
------------------------------------------------------------
local function predictNextTokenLocation(fieldName)
    local h = heatmap[fieldName]
    if not h then return nil end
    -- Точки відсортовані за частотою + recency
    local sorted = {}
    for k, c in pairs(h) do
        table.insert(sorted, { key = k, count = c })
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    if #sorted == 0 then return nil end
    -- Беремо top-3 і повертаємо ту куди ми ще не йшли
    for i = 1, math.min(3, #sorted) do
        local gx, gz = sorted[i].key:match("(-?%d+):(-?%d+)")
        if gx then
            return Vector3.new(
                tonumber(gx) * HEATMAP_GRID + HEATMAP_GRID/2,
                hrp.Position.Y,
                tonumber(gz) * HEATMAP_GRID + HEATMAP_GRID/2)
        end
    end
    return nil
end

------------------------------------------------------------
-- 🧠 BRAIN: EVENT DETECTOR (Honey Day, Bee Day, etc)
------------------------------------------------------------
local currentEvent = nil

local function detectEvents()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    for _, d in ipairs(pg:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text then
            local t = d.Text:lower()
            if t:find("honey day") then currentEvent = "honey_day"; return end
            if t:find("bee day") then currentEvent = "bee_day"; return end
            if t:find("tunnel bear day") then currentEvent = "tunnel_day"; return end
            if t:find("beesmas") then currentEvent = "beesmas"; return end
            if t:find("ant invasion") then currentEvent = "ant_invasion"; return end
        end
    end
    currentEvent = nil
end

------------------------------------------------------------
-- 🧠 BRAIN: PATIENT IDLE — щось корисне коли нема дій
------------------------------------------------------------
local function patientIdle()
    -- Раз на 3 сек перевіряємо чи з'явилось щось цінне поряд
    local nearby = findTokens(400)
    if #nearby > 0 then
        collectTokens()
        return
    end
    -- Йдемо до прогнозованої точки спавну
    local curField = findCurrentField(fields)
    if curField then
        local pred = predictNextTokenLocation(curField)
        if pred and (hrp.Position - pred).Magnitude > 30 then
            walkToPoint(pred)
            return
        end
    end
    task.wait(2)
end

------------------------------------------------------------
-- BRAIN: Yield tracker (пам'ять про прибутковість полів)
------------------------------------------------------------
local fieldStats = {}  -- { [fieldName] = { bagGained=N, timeSpent=N, lastVisit=T, killerCount=N } }

local function getFieldStat(name)
    if not fieldStats[name] then
        fieldStats[name] = { bagGained = 0, timeSpent = 0, lastVisit = 0, killerCount = 0, visits = 0 }
    end
    return fieldStats[name]
end

-- Rate = скільки заробляєш на секунду на цьому полі (емпірично)
local function fieldYieldRate(name)
    local s = getFieldStat(name)
    if s.timeSpent < 5 then return 0.5 end  -- невідомо, припускаємо середньо
    return s.bagGained / s.timeSpent
end

------------------------------------------------------------
-- БРЕЙН: Smart field selection
------------------------------------------------------------
local function chooseBestField(fields)
    if CFG.PreferredField and fields[CFG.PreferredField] then
        return CFG.PreferredField, fields[CFG.PreferredField]
    end

    -- Storm активний — на Mountain Top (найбільший boost від storm)
    if state.stormActive then
        for n, m in pairs(fields) do
            if n:lower():find("mountain") then return n, m end
        end
    end

    -- Quest active: якщо є quest на pollen у X-полі — йдемо туди
    if currentQuest.objective and currentQuest.objective.type == "pollen" then
        for n, m in pairs(fields) do
            if currentQuest.text:lower():find(n:lower()) then
                return n, m
            end
        end
    end

    -- Низький HP / висока небезпека — йдемо на safe поле
    if assessRisk() > 50 then
        local safe = { "Sunflower", "Dandelion", "Mushroom", "Blue Flower", "Clover" }
        for _, sn in ipairs(safe) do
            for n, m in pairs(fields) do
                if n:lower():find(sn:lower()) then return n, m end
            end
        end
    end

    -- Скорінг полів з усіма факторами
    local best, bestScore = nil, -math.huge
    for n, m in pairs(fields) do
        local s = getFieldStat(n)
        local rate = fieldYieldRate(n)
        local killerPenalty = (tick() - s.lastVisit < 60 and s.killerCount > 0) and -0.5 or 0
        local recencyBonus = (tick() - s.lastVisit > 600) and 0.15 or 0
        local depletionPenalty = isFieldDepleted(n) and -0.4 or 0
        local exploreBonus = s.visits == 0 and 0.35 or 0

        local score = rate + killerPenalty + recencyBonus + depletionPenalty + exploreBonus

        -- Bonus за rare bees: якщо у тебе багато mythics, краще rose/pepper/mountain
        if beeComposition.mythics > 5 then
            local hardN = n:lower()
            if hardN:find("rose") or hardN:find("pepper") or hardN:find("mountain")
               or hardN:find("cactus") then
                score = score + 0.2
            end
        end

        if score > bestScore then bestScore = score; best = n end
    end
    return best, best and fields[best] or nil
end

------------------------------------------------------------
-- FARM FIELD з yield-tracking + камп токенів
------------------------------------------------------------
local function farmField(fm, fieldName)
    if not fm then return end
    fieldName = fieldName or fm.Name
    local stat = getFieldStat(fieldName)
    stat.visits = stat.visits + 1
    stat.lastVisit = tick()

    tpTo(fm); task.wait(0.4)
    setSpeed(CFG.WalkSpeed)

    -- Адаптивний час фарму на основі швидкості наповнення мішка
    local farmDuration = adaptiveFarmTime()
    local farmStart = tick()
    local farmEnd = tick() + farmDuration
    local startBag = readBagFill() or 0
    local startKillers = #findKillersNearby()
    stat.killerCount = startKillers

    -- Якщо heatmap має гарячу точку — телепорт туди для камп'у
    local hotspot = hottestSpot(fieldName)
    if hotspot then
        tpRaw(hotspot)
        task.wait(0.3)
    end

    local lastTokenCount = 0
    local depletedChecks = 0

    while state.running and not state.returnNow and not state.inDanger and tick() < farmEnd do
        -- 1) Перевіряємо combo (Token Link + інші) — терміновий збір
        if detectTokenCombo() then
            collectTokens()
        end

        -- 2) Стандартний збір токенів
        collectTokens()

        -- 3) Записуємо heatmap: де ми знаходимо токени
        local nearby = findTokens(200)
        for _, t in ipairs(nearby) do
            if t.obj and t.obj.Parent then
                local ok, p = pcall(function() return t.obj:GetPivot().Position end)
                if ok then recordTokenSpawn(fieldName, p) end
            end
        end

        -- 4) Record activity для depletion detection
        recordFieldActivity(fieldName, #nearby)

        -- 5) Якщо токенів мало — рух
        if #nearby < 3 then
            -- Спочатку до гарячої точки якщо вона є і ми не там
            local hot = hottestSpot(fieldName)
            if hot and (hrp.Position - hot).Magnitude > 40 then
                walkToPoint(hot)
            else
                snakeMove(4)
            end
        end

        -- 6) Field depletion check
        if #nearby == 0 and lastTokenCount == 0 then
            depletedChecks = depletedChecks + 1
            if depletedChecks >= 3 then
                print("[Brain] Field depleted: " .. fieldName .. " — leaving")
                break
            end
        else
            depletedChecks = 0
        end
        lastTokenCount = #nearby

        -- 7) Risk re-check
        if assessRisk() > 70 then
            warn("[Brain] High risk → flee")
            break
        end

        if readBagFill() >= CFG.BagFullThreshold then break end
    end

    -- Зберігаємо статистику
    local timeSpent = tick() - farmStart
    local endBag = readBagFill() or 0
    local gained = math.max(0, endBag - startBag)
    stat.timeSpent = stat.timeSpent + timeSpent
    stat.bagGained = stat.bagGained + gained
    if #findKillersNearby() > startKillers then
        stat.killerCount = stat.killerCount + 1
    end

    setSpeed(16)
end

local function convertAtHive()
    if not hive then return end
    -- ХОДИМО до hive (walk, не tp)
    walkToObject(hive, { onTop = true, maxAttempts = 3, teleportFallback = true })
    task.wait(0.5)
    -- Перевірка дистанції
    local hivePos = hive:GetPivot().Position
    if (hrp.Position - hivePos).Magnitude > 20 then
        walkToObject(hive, { onTop = true, maxAttempts = 2, teleportFallback = true })
    end
    -- Конвертація: спам E + ProximityPrompt
    for _ = 1, 12 do
        tap(0x45, 0.05)
        fireProximityPromptsNearby(20)
        task.wait(0.25)
    end
    task.wait(0.5)
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

-- Чекаємо щоб персонаж повністю спавнувся
local function waitForChar(timeout)
    timeout = timeout or 15
    local t0 = tick()
    while tick() - t0 < timeout do
        if LP.Character
           and LP.Character:FindFirstChild("HumanoidRootPart")
           and LP.Character:FindFirstChildWhichIsA("Humanoid")
           and LP.Character.Humanoid.Health > 0 then
            return true
        end
        task.wait(0.2)
    end
    return false
end

debugToast("Чекаю спавн персонажа...", Color3.fromRGB(80, 120, 200), 2)
waitForChar(15)
char, hrp, hum = getChar()

local fields     = findFields()
local dispensers = CFG.DoDispensers and findDispensers() or {}

-- КРОК 1: Спочатку перевіряємо/клеймимо hive
hive = ensureHiveClaimed()

local fieldCount = 0; for _ in pairs(fields) do fieldCount = fieldCount + 1 end
print(("[Macro] Fields=%d  Hive=%s  Dispensers=%d  UseItem=%s")
      :format(fieldCount, hive and hive.Name or "nil", #dispensers, tostring(UseItem ~= nil)))

if not hive then
    debugToast("⚠ Без hive макрос обмежений (тільки збір токенів)", Color3.fromRGB(220, 140, 50), 6)
end

------------------------------------------------------------
-- GUI
------------------------------------------------------------
local function buildGUI()
    -- На мобілці PlayerGui перекривається Roblox UI →
    -- пробуємо gethui() (executor-контейнер), потім CoreGui, потім PlayerGui
    local function getGuiParent()
        -- 1. gethui() - найкращий варіант, його не перекриває Roblox
        local ok, hui = pcall(function() return gethui and gethui() end)
        if ok and hui then return hui, "gethui" end

        local ok2, hui2 = pcall(function() return get_hidden_gui and get_hidden_gui() end)
        if ok2 and hui2 then return hui2, "get_hidden_gui" end

        -- 2. CoreGui напряму
        local ok3 = pcall(function()
            local cg = game:GetService("CoreGui")
            local test = Instance.new("Folder")
            test.Parent = cg
            test:Destroy()
        end)
        if ok3 then return game:GetService("CoreGui"), "CoreGui" end

        -- 3. PlayerGui — fallback
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
        -- Мобільний UI: компактно щоб не перекриватись Roblox controls
        W       = math.min(VP.X * 0.55, 280)   -- вужче (раніше було 0.8)
        H       = math.min(VP.Y * 0.7,  420)   -- нижче
        BTN_H   = 36
        TITLE_H = 40
        FONT    = 13
        PAD     = 6
    else
        W, H    = 280, 430
        BTN_H   = 28
        TITLE_H = 32
        FONT    = 13
        PAD     = 6
    end

    local main = Instance.new("Frame", gui)
    main.Size = UDim2.new(0, W, 0, H)
    if IS_SMALL_SCREEN then
        main.Position = UDim2.new(0, 60, 0, 50)
    else
        main.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
    end
    main.ZIndex = 100
    main.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
    main.BorderSizePixel = 0
    -- НЕ Active, НЕ Draggable — не перехоплюємо тачі. Кнопки самі реагують.
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

    -- MANUAL DRAG за title — спрацьовує лише якщо реально рух пальцем > 5px
    -- Звичайний tap по title не активує drag → minBtn (всередині title) спрацьовує нормально
    do
        local pressing = false
        local pressPos = nil
        local pressStartPos = nil
        local dragging = false
        title.Active = true
        title.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                pressing = true
                dragging = false
                pressPos = input.Position
                pressStartPos = main.Position
            end
        end)
        title.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                pressing = false
                dragging = false
            end
        end)
        UIS.InputChanged:Connect(function(input)
            if not pressing then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - pressPos
                -- Активуємо drag лише після відчутного руху
                if not dragging and delta.Magnitude > 5 then dragging = true end
                if dragging then
                    main.Position = UDim2.new(
                        pressStartPos.X.Scale, pressStartPos.X.Offset + delta.X,
                        pressStartPos.Y.Scale, pressStartPos.Y.Offset + delta.Y)
                end
            end
        end)
    end

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
    content.Active = true                            -- приймає touch input
    content.ZIndex = 101
    content.ScrollBarThickness = IS_SMALL_SCREEN and 6 or 4
    content.ScrollBarImageColor3 = Color3.fromRGB(255, 200, 60)
    content.CanvasSize = UDim2.new(0, 0, 0, 0)
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    content.ScrollingDirection = Enum.ScrollingDirection.Y
    content.ElasticBehavior = Enum.ElasticBehavior.Always

    local layout = Instance.new("UIListLayout", content)
    layout.Padding = UDim.new(0, PAD)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    local pad = Instance.new("UIPadding", content)
    pad.PaddingTop = UDim.new(0, PAD)
    pad.PaddingBottom = UDim.new(0, PAD)

    local function toggleMin()
        content.Visible = not content.Visible
        main.Size = content.Visible and UDim2.new(0,W,0,H) or UDim2.new(0,W,0,TITLE_H)
    end
    minBtn.MouseButton1Click:Connect(toggleMin)
    minBtn.Activated:Connect(toggleMin)
    minBtn.ZIndex = 105

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
        btn.Active = true
        btn.ZIndex = 102
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
        btn.Active = true
        btn.ZIndex = 102
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
        header.Active = true
        header.ZIndex = 103
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
                if not element then return end  -- захист від nil
                table.insert(items, element)
                pcall(function() element.Visible = sec.expanded end)
            end
        }
    end

    local function makeDropdown(label, options, getVal, setVal)
        local box = Instance.new("Frame", content)
        box.Size = UDim2.new(1, -16, 0, BTN_H)
        box.LayoutOrder = nextOrder()
        box.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

        local btn = Instance.new("TextButton", box)
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Font = Enum.Font.Gotham
        btn.TextSize = FONT
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Text = label .. ": " .. tostring(getVal() or "—")

        local itemH = IS_SMALL_SCREEN and 32 or 24
        local listFrame = Instance.new("ScrollingFrame", main)
        listFrame.Size = UDim2.new(0, math.min(W - 40, 240), 0, math.min(#options * (itemH + 2) + 6, 200))
        listFrame.BackgroundColor3 = Color3.fromRGB(35, 37, 45)
        listFrame.BorderSizePixel = 0
        listFrame.Visible = false
        listFrame.ZIndex = 50
        listFrame.CanvasSize = UDim2.new(0, 0, 0, #options * (itemH + 2) + 6)
        listFrame.ScrollBarThickness = IS_SMALL_SCREEN and 6 or 4
        Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 6)
        local ll = Instance.new("UIListLayout", listFrame)
        ll.Padding = UDim.new(0, 2)

        for _, opt in ipairs(options) do
            local b = Instance.new("TextButton", listFrame)
            b.Size = UDim2.new(1, -8, 0, itemH)
            b.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
            b.TextColor3 = Color3.new(1, 1, 1)
            b.Font = Enum.Font.Gotham
            b.TextSize = FONT
            b.Text = tostring(opt)
            b.ZIndex = 51
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
            local function selectOpt()
                setVal(opt)
                btn.Text = label .. ": " .. tostring(opt)
                listFrame.Visible = false
            end
            b.MouseButton1Click:Connect(selectOpt)
            b.Activated:Connect(selectOpt)
        end

        local function toggleList()
            local p = box.AbsolutePosition - main.AbsolutePosition
            listFrame.Position = UDim2.new(0, p.X, 0, p.Y + BTN_H + 4)
            listFrame.Visible = not listFrame.Visible
        end
        btn.MouseButton1Click:Connect(toggleList)
        btn.Activated:Connect(toggleList)

        return box  -- ← КРИТИЧНО: повертаємо елемент для makeSection.add()
    end

    -- Статус
    local statusLbl = Instance.new("TextLabel", content)
    statusLbl.Size = UDim2.new(1, -16, 0, 72)
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
            local fsmState = (_G.BSSMacroFSM and _G.BSSMacroFSM.state) or "?"
            local eta = bagETA()
            local etaStr = eta == math.huge and "∞" or (math.floor(eta) .. "s")
            local risk = assessRisk()
            statusLbl.Text = string.format(
                "🤖 %s | Поле: %s | Risk: %d\nМішок: %d%% (ETA %s) | Honey/h: %s\nЧас: %s | Storm: %s | Bees: %d",
                fsmState, fieldName, risk,
                math.floor(fill * 100), etaStr,
                tostring(honeyPerHour()),
                sessionTime(),
                state.stormActive and "✓" or "—",
                beeComposition.count
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
    -- FAB не drag — тільки tap. Інакше touch input не доходить до Click
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

------------------------------------------------------------
-- STATE MACHINE (розумний AI)
------------------------------------------------------------
local FSM = {
    state    = "INIT",
    lastChange = tick(),
    lastBoss   = 0,
    lastDispensers = 0,
    lastClaims = 0,
    deathStreak = 0,
}
_G.BSSMacroFSM = FSM  -- щоб GUI міг показувати поточний стан

local function setState(s, reason)
    if FSM.state ~= s then
        print(string.format("[FSM] %s → %s (%s)", FSM.state, s, reason or ""))
        FSM.state = s
        FSM.lastChange = tick()
    end
end

-- Smart decision з planner'ом і cost-benefit
local function decideNextState()
    local bagFill = readBagFill() or 0

    -- ПРІОРИТЕТ 1: Hard safety
    if state.inDanger then return "FLEEING" end
    if needsHpRecovery() then return "HP_RECOVERY" end

    -- ПРІОРИТЕТ 2: Hive
    if not hive then return "CLAIMING_HIVE" end

    -- ПРІОРИТЕТ 3: Мішок повний
    if bagFill >= CFG.BagFullThreshold or state.returnNow then return "CONVERTING" end

    -- ПРІОРИТЕТ 4: MEGA COMBO (storm + low bag + buffs available)
    if state.stormActive and bagFill < 0.3 then return "MEGA_COMBO" end

    -- ПРІОРИТЕТ 5: Goal queue
    local goal = topGoal()
    if goal then
        if goal.type == "fight_boss" then return "BOSS" end
        if goal.type == "collect" then return "FARMING" end
    end

    -- ПРІОРИТЕТ 6: Storm активний — звичайний фарм
    if state.stormActive then return "FARMING" end

    -- ПРІОРИТЕТ 7: Cost-benefit рішення між основними діями
    --   Кожна дія: (expected_reward, time_cost, risk)
    local candidates = {}

    -- Farm: швидко, низький ризик, середня нагорода
    local farmEV = evaluateAction("FARMING", 50, 60, assessRisk())
    table.insert(candidates, { name = "FARMING", ev = farmEV })

    -- Claims: середня нагорода, рідко, без ризику
    if tick() - FSM.lastClaims > 600 then
        table.insert(candidates, { name = "CLAIMING_EXTRAS",
            ev = evaluateAction("CLAIMING_EXTRAS", 80, 90, 5) })
    end

    -- Boss: висока нагорода, дорого по часу, ризиковано
    if state.bossMode and tick() - FSM.lastBoss > 900 then
        table.insert(candidates, { name = "BOSS",
            ev = evaluateAction("BOSS", 200, 120, 40) })
    end

    -- Dispensers: середньо
    if CFG.DoDispensers and #dispensers > 0 and tick() - FSM.lastDispensers > 900 then
        table.insert(candidates, { name = "DISPENSERS",
            ev = evaluateAction("DISPENSERS", 60, 60, 5) })
    end

    -- Mob hunt: ситуативно
    if state.mobMode and #findMobs() > 0 then
        table.insert(candidates, { name = "MOB_HUNT",
            ev = evaluateAction("MOB_HUNT", 70, 40, 20) })
    end

    -- Сортуємо за EV
    table.sort(candidates, function(a, b) return a.ev > b.ev end)
    return candidates[1] and candidates[1].name or "FARMING"
end

-- HANDLERS станів
local handlers = {}

handlers.CLAIMING_HIVE = function()
    hive = ensureHiveClaimed()
    if not hive then task.wait(10) end
end

handlers.FARMING = function()
    if CFG.TrackStats then readGameStats() end
    detectStorms()
    detectEvents()
    solveMemoryMatch()

    local fn, fm = chooseBestField(fields)
    if not fm then
        -- Нема куди йти — patient idle
        patientIdle()
        return
    end

    useBuffs()

    print("[FSM] Farming: " .. fn .. (currentEvent and (" [event: "..currentEvent.."]") or ""))
    local before = readBagFill() or 0
    local t0 = tick()

    farmField(fm, fn)

    -- Adaptive learning: записуємо outcome
    local gained = (readBagFill() or 0) - before
    local timeSpent = tick() - t0
    recordOutcome("FARMING", gained * 100, timeSpent)
end

handlers.CONVERTING = function()
    if hive then convertAtHive() end
    state.returnNow = false
end

handlers.FLEEING = function()
    smartFlee()
    state.inDanger = false
end

handlers.HP_RECOVERY = function()
    recoverHP()
end

handlers.MEGA_COMBO = function()
    if not attemptMegaCombo() then
        -- Якщо combo failed (без storm) — fallback на farm
        handlers.FARMING()
    end
end

handlers.DISPENSERS = function()
    visitDispensers(dispensers)
    FSM.lastDispensers = tick()
    if hive then convertAtHive() end
end

handlers.BOSS = function()
    fightBoss()
    FSM.lastBoss = tick()
    if hive then convertAtHive() end
end

handlers.MOB_HUNT = function()
    huntMobs()
    if hive then convertAtHive() end
end

handlers.CLAIMING_EXTRAS = function()
    -- Всі periodic задачі за раз
    processPlanters()
    processCrafting()
    processQuests()
    processSprouts()
    claimWealthClock()
    processBeequips()
    feedBees()
    claimStickerStack()
    claimDailyBonus()
    claimGoo()
    claimHoneysuckle()
    claimBuoy()
    goMountainTop()
    collectCuckooDrops()
    huntVicious()
    redeemCodes()
    -- Brain updates
    readBeeComposition()
    parseCurrentQuest()
    FSM.lastClaims = tick()
end

-- Brain background: оновлення кожні 30с
task.spawn(function()
    while task.wait(30) do
        if state.running then
            pcall(readBeeComposition)
            pcall(parseCurrentQuest)
            pcall(detectEvents)
            pcall(planAhead)
            pruneGoals()
        end
    end
end)

-- Goal seeder: автоматично додає цілі на основі контексту
task.spawn(function()
    while task.wait(60) do
        if state.running then
            if currentEvent == "tunnel_day" then
                addGoal("event_tunnel", "fight_boss", 80, 600, { boss = "Tunnel Bear" })
            end
            if currentEvent == "honey_day" then
                addGoal("honey_day_farm", "collect", 75, 1200)
            end
            if currentQuest.objective then
                addGoal("quest_active", "collect", 70, 600)
            end
        end
    end
end)

-- DEATH-DETECTION + auto rejoin якщо помираємо багато
LP.CharacterAdded:Connect(function()
    FSM.deathStreak = FSM.deathStreak + 1
    if FSM.deathStreak >= 4 then
        warn("[FSM] 4 смерті підряд — server hop")
        webhook("💀 4 deaths in a row — server hop", 0xFF6666)
        FSM.deathStreak = 0
        task.spawn(serverHop)
    end
    task.delay(120, function() FSM.deathStreak = math.max(0, FSM.deathStreak - 1) end)
end)

-- ГОЛОВНИЙ FSM LOOP
setState("FARMING", "init")

while state.running do
    local ok, err = pcall(function()
        local nextS = decideNextState()
        setState(nextS, "decide")
        local h = handlers[nextS]
        if h then h() end
    end)
    if not ok then
        warn("[FSM] Err: " .. tostring(err))
        webhook("❌ FSM Error: " .. tostring(err):sub(1, 200), 0xFF0000)
        task.wait(3)
    end
    task.wait(0.3)
end

webhook("⏹️ Macro stopped. Honey: " .. stats.honeyMade .. " | Time: " .. sessionTime(), 0xFF6666)

print("[Macro] Завершено.")
