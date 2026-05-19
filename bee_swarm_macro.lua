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
local Players      = game:GetService("Players")
local Workspace    = game:GetService("Workspace")
local RS           = game:GetService("ReplicatedStorage")
local UIS          = game:GetService("UserInputService")
local VirtualUser  = game:GetService("VirtualUser")
local RunService   = game:GetService("RunService")
local GuiService   = game:GetService("GuiService")

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
-- ФОРВАРД-ДЕКЛАРАЦІЯ СТАНУ (потрібно для anti-detect функцій)
------------------------------------------------------------
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

local function tpTo(target)
    local cf
    if typeof(target) == "Instance" then
        local ok, p = pcall(function() return target:GetPivot() end)
        if not ok then return false end
        cf = p
    elseif typeof(target) == "CFrame" then cf = target
    elseif typeof(target) == "Vector3" then cf = CFrame.new(target)
    else return false end
    if not hrp or not hrp.Parent then return false end

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
local function setSpeed(v) pcall(function() hum.WalkSpeed = v end) end

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

local function findTokens(radius)
    radius = radius or CFG.TokenRadius
    local out = {}
    local fold = Workspace:FindFirstChild("Collectibles") or Workspace:FindFirstChild("Tokens")
    local search = fold and fold:GetChildren() or Workspace:GetDescendants()
    for _, obj in ipairs(search) do
        if obj:IsA("BasePart") or obj:IsA("Model") then
            local n = obj.Name:lower()
            if n:find("token") or n:find("ticket") or n:find("royal")
               or n:find("star") or n:find("treat") or n:find("honey")
               or n:find("egg") or n:find("snowflake") or n:find("glitter") then
                if distTo(obj) <= radius then table.insert(out, obj) end
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
local function collectTokens()
    if not CFG.UseTokens then return end
    local toks = findTokens()
    table.sort(toks, function(a, b) return distTo(a) < distTo(b) end)
    for i = 1, math.min(#toks, 25) do
        if not state.running or state.returnNow or state.inDanger then break end
        local t = toks[i]
        if t and t.Parent then tpTo(t); task.wait(0.12) end
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
    statusLbl.Size = UDim2.new(1, -16, 0, 36)
    statusLbl.LayoutOrder = nextOrder()
    statusLbl.BackgroundColor3 = Color3.fromRGB(35, 37, 45)
    statusLbl.TextColor3 = Color3.fromRGB(180, 255, 180)
    statusLbl.Font = Enum.Font.GothamBold
    statusLbl.TextSize = 11
    statusLbl.Text = "Статус: запуск..."
    statusLbl.TextWrapped = true
    Instance.new("UICorner", statusLbl).CornerRadius = UDim.new(0, 6)

    -- Toggles
    makeToggle("Running",        function() return state.running end,    function(v) state.running = v end)
    makeToggle("Auto-farm pause",function() return state.paused end,     function(v) state.paused = v end)
    makeToggle("Mob mode",       function() return state.mobMode end,    function(v) state.mobMode = v end)
    makeToggle("Boss mode",      function() return state.bossMode end,   function(v) state.bossMode = v end)
    makeToggle("Use buffs",      function() return CFG.DoBuffs end,      function(v) CFG.DoBuffs = v end)
    makeToggle("Dispensers",     function() return CFG.DoDispensers end, function(v) CFG.DoDispensers = v end)
    makeToggle("Planters",       function() return CFG.DoPlanters end,   function(v) CFG.DoPlanters = v end)
    makeToggle("Flee killers",   function() return CFG.FleeFromKillers end, function(v) CFG.FleeFromKillers = v end)
    makeToggle("Collect tokens", function() return CFG.UseTokens end,    function(v) CFG.UseTokens = v end)

    -- Поля
    local fieldOpts = { "Auto" }
    for n in pairs(fields) do table.insert(fieldOpts, n) end
    makeDropdown("Field", fieldOpts,
        function() return CFG.PreferredField or "Auto" end,
        function(v) CFG.PreferredField = (v ~= "Auto") and v or nil end)

    -- Боси
    makeDropdown("Boss", BOSS_NAMES,
        function() return CFG.PreferredBoss end,
        function(v) CFG.PreferredBoss = v end)

    -- Дії
    makeButton("→ Hive & Convert", Color3.fromRGB(200, 140, 50), function()
        state.returnNow = true
    end)
    makeButton("Craft now (Blender/Stickers)", Color3.fromRGB(100, 120, 220), function()
        state.craftNow = true
    end)
    makeButton("STOP", Color3.fromRGB(200, 60, 60), function()
        state.running = false
    end)

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
                "Поле: %s  |  Мішок: %d%%\nDanger: %s  |  Pause: %s",
                fieldName, math.floor(fill * 100),
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
while state.running do
    local ok, err = pcall(function()
        useBuffs()

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
        if state.bossMode then fightBoss() end

        processPlanters()
        processCrafting()
    end)
    if not ok then warn("[Macro] Err: " .. tostring(err)); task.wait(2) end
    task.wait(0.4)
end

print("[Macro] Завершено.")
