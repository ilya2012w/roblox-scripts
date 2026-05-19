--[[
    BSSA Macro (Bee Swarm Simulator Ascended)
    ────────────────────────────────────────
    Заточено під реальну структуру BSSA:
    • Hives: Workspace.Hives.Hive_1..5 (Claimed BoolValue)
    • Fields: Workspace.Fields.* (FlowerPart children)
    • Remotes: ReplicatedStorage.Remotes (ClaimHive, MakeHoney, UseItem...)
    • Buffs: окремі remotes (Glue, Enzymes, Oil, Drink, Star Jelly...)

    Запуск:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/ilya2012w/roblox-scripts/main/bssa_macro.lua"))()
--]]

------------------------------------------------------------
-- СЕРВІСИ
------------------------------------------------------------
local Players       = game:GetService("Players")
local Workspace     = game:GetService("Workspace")
local RS            = game:GetService("ReplicatedStorage")
local UIS           = game:GetService("UserInputService")
local VirtualUser   = game:GetService("VirtualUser")
local TweenService  = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local PathfindingService = game:GetService("PathfindingService")

local LP = Players.LocalPlayer

------------------------------------------------------------
-- DEBUG TOAST
------------------------------------------------------------
local function toast(text, color, duration)
    local pg = LP:WaitForChild("PlayerGui")
    local sg = Instance.new("ScreenGui")
    sg.Name = "BSSAToast"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 99999
    sg.IgnoreGuiInset = true
    sg.Parent = pg

    local lbl = Instance.new("TextLabel", sg)
    lbl.Size = UDim2.new(0, 360, 0, 50)
    lbl.Position = UDim2.new(0.5, -180, 0, 100)
    lbl.BackgroundColor3 = color or Color3.fromRGB(60, 180, 100)
    lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 14
    lbl.TextWrapped = true
    lbl.Text = text
    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)

    task.delay(duration or 3, function() sg:Destroy() end)
end

toast("🐝 BSSA Macro: запуск...", Color3.fromRGB(60, 180, 100), 2)

------------------------------------------------------------
-- ХАРАКТЕР
------------------------------------------------------------
local function getChar()
    local c = LP.Character or LP.CharacterAdded:Wait()
    return c, c:WaitForChild("HumanoidRootPart"), c:WaitForChild("Humanoid")
end
local char, hrp, hum = getChar()
LP.CharacterAdded:Connect(function() task.wait(0.5); char, hrp, hum = getChar() end)

-- Anti-AFK
LP.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

------------------------------------------------------------
-- ПОШУК REMOTES
------------------------------------------------------------
local Remotes = RS:WaitForChild("Remotes", 5) or RS

local function getRemote(name)
    local r = Remotes:FindFirstChild(name)
    if r then return r end
    -- fallback: пошук по всьому RS
    return RS:FindFirstChild(name, true)
end

local R = {
    ClaimHive    = getRemote("ClaimHive"),
    MakeHoney    = getRemote("MakeHoney"),
    UseItem      = getRemote("UseItem"),
    ClaimPlanter = getRemote("ClaimPlanter"),
    TalkToNPC    = getRemote("TalkToNPC"),
    ShootCannon  = getRemote("ShootCannon"),
    RedeemCode   = getRemote("RedeemCode"),
    Glue         = getRemote("Glue"),
    Enzymes      = getRemote("Enzymes"),
    Oil          = getRemote("Oil"),
    Drink        = getRemote("Drink"),
    StarJelly    = getRemote("Star Jelly"),
    BlueEx       = getRemote("BlueEx"),
    RedEx        = getRemote("RedEx"),
    BluePotion   = getRemote("BluePotion"),
    RedPotion    = getRemote("RedPotion"),
    WhitePotion  = getRemote("WhitePotion"),
    MixedPotion  = getRemote("MixedPotion"),
}

print("[BSSA] Remotes loaded:")
for name, r in pairs(R) do
    print("  " .. name .. " = " .. (r and "✓" or "✗"))
end

local function fire(remote, ...)
    if not remote then return false end
    local ok = pcall(function()
        if remote:IsA("RemoteEvent") then remote:FireServer(...)
        elseif remote:IsA("RemoteFunction") then remote:InvokeServer(...)
        end
    end)
    return ok
end

------------------------------------------------------------
-- НАЛАШТУВАННЯ
------------------------------------------------------------
local CFG = {
    PreferredField = nil,                -- nil = автовибір
    BagFullThreshold = 0.93,
    WalkSpeed = 60,
    UsePathfinding = true,
    WalkTimeout = 6,
    UnstuckTime = 2,
    UseBuffs = true,
    DoPlanters = true,
    DoQuests = true,
    DoCodes = false,
    FleeFromKillers = true,
}

------------------------------------------------------------
-- ДЕТЕКТ ХАЙВУ
------------------------------------------------------------
local function findMyHive()
    local hives = Workspace:FindFirstChild("Hives")
    if not hives then return nil end

    -- BSSA: кожен Hive_N має `Claimed [BoolValue]`. Власник зберігається
    -- ймовірно в Slots/PlayerName або через атрибут.
    -- Спочатку шукаємо по атрибуту Owner/OwnerName
    for _, h in ipairs(hives:GetChildren()) do
        local ownerAttr = h:GetAttribute("Owner") or h:GetAttribute("OwnerName")
        if ownerAttr == LP.Name or ownerAttr == LP.UserId then
            return h
        end
        -- Перевіряємо ObjectValue/StringValue в Hive_N
        local ov = h:FindFirstChild("Owner") or h:FindFirstChild("OwnerName")
        if ov then
            if (typeof(ov.Value) == "Instance" and ov.Value == LP)
            or (typeof(ov.Value) == "string" and ov.Value == LP.Name) then
                return h
            end
        end
        -- Перевірка Slots — там можуть бути бджоли з owner-полем
        local slots = h:FindFirstChild("Slots")
        if slots then
            for _, slot in ipairs(slots:GetChildren()) do
                local so = slot:FindFirstChild("Owner") or slot:GetAttribute("Owner")
                if so == LP or so == LP.Name then return h end
            end
        end
    end
    return nil
end

local function findEmptyHive()
    local hives = Workspace:FindFirstChild("Hives")
    if not hives then return nil end
    for _, h in ipairs(hives:GetChildren()) do
        local claimed = h:FindFirstChild("Claimed")
        if claimed and claimed:IsA("BoolValue") and claimed.Value == false then
            return h
        end
    end
    return nil
end

local function getHivePosition(h)
    -- Беремо позицію Platform — там стоїть гравець
    local platform = h and h:FindFirstChild("Platform")
    if platform then
        if platform:IsA("Model") then
            local ok, pivot = pcall(function() return platform:GetPivot() end)
            if ok then return pivot.Position end
        elseif platform:IsA("BasePart") then
            return platform.Position
        end
    end
    -- Fallback на сам hive model
    local model = h and h:FindFirstChild("hive")
    if model then
        local ok, pivot = pcall(function() return model:GetPivot() end)
        if ok then return pivot.Position end
    end
    return nil
end

------------------------------------------------------------
-- РУХ
------------------------------------------------------------
local function setSpeed(v)
    pcall(function() if hum then hum.WalkSpeed = v end end)
end

local function walkToPoint(pos)
    if not hum or not hrp then return false end
    local t0 = tick()
    local lastPos = hrp.Position
    local stuckSince = tick()
    local jumpAttempts = 0
    hum:MoveTo(pos)
    while tick() - t0 < CFG.WalkTimeout do
        local cur = hrp.Position
        if (cur - pos).Magnitude <= 5 then return true end
        if (cur - lastPos).Magnitude < 0.5 then
            if tick() - stuckSince > CFG.UnstuckTime then
                jumpAttempts = jumpAttempts + 1
                if jumpAttempts <= 2 then
                    hum.Jump = true
                    task.wait(0.3)
                    hum:MoveTo(pos)
                else
                    local dir = (pos - cur).Magnitude > 0 and (pos - cur).Unit or Vector3.new(0,0,1)
                    hrp.CFrame = CFrame.new(cur + Vector3.new(0, 5, 0) + dir * 3)
                    task.wait(0.2)
                    hum:MoveTo(pos)
                    if jumpAttempts > 5 then return false end
                end
                stuckSince = tick()
            end
        else
            stuckSince = tick()
            jumpAttempts = 0
        end
        lastPos = cur
        task.wait(0.1)
    end
    return false
end

local function walkPath(targetPos)
    if not hrp or not hum then return false end
    local ok1, path = pcall(function()
        return PathfindingService:CreatePath({
            AgentRadius = 2, AgentHeight = 5,
            AgentCanJump = true, AgentJumpHeight = 7, AgentMaxSlope = 45,
        })
    end)
    if not ok1 or not path then return walkToPoint(targetPos) end
    local ok2 = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)
    if not ok2 or path.Status ~= Enum.PathStatus.Success then
        return walkToPoint(targetPos)
    end
    for _, wp in ipairs(path:GetWaypoints()) do
        if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
        if not walkToPoint(wp.Position) then break end
    end
    return (hrp.Position - targetPos).Magnitude < 10
end

local function goTo(pos, options)
    options = options or {}
    if not pos then return false end
    setSpeed(CFG.WalkSpeed)
    local reached
    for attempt = 1, options.attempts or 3 do
        reached = CFG.UsePathfinding and walkPath(pos) or walkToPoint(pos)
        if reached then return true end
        if hum then hum.Jump = true end
        task.wait(0.5)
    end
    -- Fallback teleport (тільки якщо не зміг walk)
    if options.teleportFallback ~= false then
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
        task.wait(0.3)
        return true
    end
    return false
end

------------------------------------------------------------
-- КЛЕЙМ ХАЙВУ (через RemoteEvent — найчистіший спосіб!)
------------------------------------------------------------
local function claimHive()
    local mine = findMyHive()
    if mine then return mine end

    local empty = findEmptyHive()
    if not empty then
        toast("❌ Усі hive зайняті", Color3.fromRGB(220, 60, 60), 4)
        return nil
    end

    toast("Йду до hive: " .. empty.Name, Color3.fromRGB(80, 120, 200), 2)
    local pos = getHivePosition(empty)
    if pos then goTo(pos, { attempts = 3 }) end
    task.wait(0.5)

    -- Спроба 1: викликаємо ClaimHive remote напряму
    if R.ClaimHive then
        -- Спробуємо різні сигнатури (hiveIndex / hive itself / hiveName)
        local hiveIndex = tonumber(empty.Name:match("(%d+)"))
        local signatures = {
            { hiveIndex },
            { empty },
            { empty.Name },
            {},
        }
        for _, args in ipairs(signatures) do
            fire(R.ClaimHive, table.unpack(args))
            task.wait(0.3)
            mine = findMyHive()
            if mine then break end
        end
    end

    -- Спроба 2: ProximityPrompt "Claim"
    if not mine then
        for _, prompt in ipairs(empty:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") and prompt.Enabled then
                pcall(function() fireproximityprompt(prompt) end)
                pcall(function() prompt:InputHoldBegin(); task.wait(0.6); prompt:InputHoldEnd() end)
                task.wait(0.3)
                mine = findMyHive()
                if mine then break end
            end
        end
    end

    if mine then
        toast("✓ Hive claimed: " .. mine.Name, Color3.fromRGB(60, 180, 100), 3)
    else
        toast("⚠ Не вдалось claim — стоїмо на hive, натисни E/тач prompt вручну", Color3.fromRGB(220, 140, 50), 5)
    end
    return mine or empty
end

------------------------------------------------------------
-- ПОЛЯ
------------------------------------------------------------
local function findFields()
    local out = {}
    local f = Workspace:FindFirstChild("Fields")
    if not f then return out end
    for _, field in ipairs(f:GetChildren()) do
        if field:IsA("Folder") or field:IsA("Model") then
            out[field.Name] = field
        end
    end
    return out
end

local function getFieldCenter(field)
    -- FieldBox це BasePart що окреслює межі поля
    local fb = field:FindFirstChild("FieldBox")
    if fb and fb:IsA("BasePart") then return fb.Position, fb.Size end
    -- Fallback: середнє позицій FlowerPart'ів
    local sum, count = Vector3.new(), 0
    for _, c in ipairs(field:GetChildren()) do
        if c:IsA("BasePart") and c.Name:find("Flower") then
            sum = sum + c.Position
            count = count + 1
        end
    end
    if count > 0 then return sum / count, Vector3.new(50, 10, 50) end
    return nil, nil
end

------------------------------------------------------------
-- POLLEN / BAG
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
-- ФАРМ ПОЛЯ (рух між FlowerPart'ами)
------------------------------------------------------------
local function farmField(field)
    if not field then return end
    local center, size = getFieldCenter(field)
    if not center then return end

    toast("🌻 Фарм: " .. field.Name, Color3.fromRGB(60, 180, 100), 2)
    goTo(center, { attempts = 2 })
    setSpeed(CFG.WalkSpeed)

    local farmEnd = tick() + 180
    while state.running ~= false and tick() < farmEnd do
        -- Рух змійкою по полю — телепорт між випадковими FlowerPart'ами
        local flowers = {}
        for _, c in ipairs(field:GetChildren()) do
            if c:IsA("BasePart") and c.Name:find("Flower") then
                table.insert(flowers, c)
            end
        end
        if #flowers == 0 then break end

        -- Перемішуємо і йдемо по 5-8 з них
        for i = 1, math.min(8, #flowers) do
            local f = flowers[math.random(#flowers)]
            walkToPoint(f.Position + Vector3.new(0, 3, 0))
            task.wait(0.3 + math.random() * 0.3)
            if readBagFill() >= CFG.BagFullThreshold then return end
        end
    end
end

------------------------------------------------------------
-- КОНВЕРТАЦІЯ (через MakeHoney remote)
------------------------------------------------------------
local function convertAtHive(hive)
    if not hive then return end
    local pos = getHivePosition(hive)
    if pos then goTo(pos, { attempts = 3 }) end
    task.wait(0.5)

    -- Викликаємо MakeHoney remote (декілька разів для надійності)
    if R.MakeHoney then
        for _ = 1, 5 do
            fire(R.MakeHoney)
            task.wait(0.3)
        end
    end
    -- Дублюємо клавішею E (на випадок якщо remote змінив сигнатуру)
    for _ = 1, 8 do
        pcall(function()
            local VIM = game:GetService("VirtualInputManager")
            VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.05)
            VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end)
        task.wait(0.2)
    end
    task.wait(1)
end

------------------------------------------------------------
-- БУФФИ через окремі remotes
------------------------------------------------------------
local function useBuffs()
    if not CFG.UseBuffs then return end
    -- Виглядаємо як reasonable гравець — не юзаємо все підряд
    -- Юзаємо тільки якщо нема активного buff'у
    for _, buffR in ipairs({ R.Glue, R.Enzymes, R.Oil, R.Drink, R.StarJelly, R.BlueEx, R.RedEx }) do
        if buffR then
            pcall(function() fire(buffR) end)
            task.wait(0.2)
        end
    end
end

------------------------------------------------------------
-- ПЛАНТЕРИ
------------------------------------------------------------
local function claimPlanters()
    if not CFG.DoPlanters or not R.ClaimPlanter then return end
    local p = Workspace:FindFirstChild("Planters")
    if not p then return end
    for _, planter in ipairs(p:GetChildren()) do
        local owner = planter:FindFirstChild("Owner") or planter:GetAttribute("Owner")
        local isMine = false
        if owner then
            if typeof(owner) == "Instance" and owner.Value == LP then isMine = true
            elseif typeof(owner) == "string" and owner == LP.Name then isMine = true end
        end
        if isMine then
            fire(R.ClaimPlanter, planter)
            fire(R.ClaimPlanter, planter.Name)
            task.wait(0.3)
        end
    end
end

------------------------------------------------------------
-- КВЕСТИ
------------------------------------------------------------
local function processQuests()
    if not CFG.DoQuests or not R.TalkToNPC then return end
    local npcs = Workspace:FindFirstChild("QuestNPCS")
    if not npcs then return end
    for _, npc in ipairs(npcs:GetChildren()) do
        local ok, pivot = pcall(function() return npc:GetPivot().Position end)
        if ok and (hrp.Position - pivot).Magnitude < 2000 then
            goTo(pivot, { attempts = 2 })
            task.wait(0.5)
            fire(R.TalkToNPC, npc)
            fire(R.TalkToNPC, npc.Name)
            task.wait(0.5)
        end
    end
end

------------------------------------------------------------
-- GUI
------------------------------------------------------------
local state = { running = true, paused = false, fsm = "INIT" }
_G.BSSAState = state

local function buildGUI()
    local pg = LP:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("BSSAMacroGUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BSSAMacroGUI"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 9999
    gui.IgnoreGuiInset = true
    gui.Parent = pg

    local IS_MOBILE = UIS.TouchEnabled and not UIS.KeyboardEnabled
    local W = IS_MOBILE and 280 or 260
    local H = IS_MOBILE and 380 or 340
    local BTN_H = IS_MOBILE and 38 or 28
    local FONT = IS_MOBILE and 14 or 13

    local main = Instance.new("Frame", gui)
    main.Size = UDim2.new(0, W, 0, H)
    main.Position = UDim2.new(0, 30, 0, 60)
    main.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(255, 200, 60)
    stroke.Thickness = 1.5

    local title = Instance.new("TextLabel", main)
    title.Size = UDim2.new(1, 0, 0, 38)
    title.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
    title.Text = "🐝 BSSA Macro"
    title.Font = Enum.Font.GothamBold
    title.TextSize = FONT + 2
    title.TextColor3 = Color3.fromRGB(25, 25, 25)
    title.Active = true
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)

    -- Drag (тільки за title, > 5px рух)
    do
        local pressing, dragging, pressPos, startPos
        title.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                pressing = true; dragging = false
                pressPos = input.Position; startPos = main.Position
            end
        end)
        title.InputEnded:Connect(function() pressing = false; dragging = false end)
        UIS.InputChanged:Connect(function(input)
            if not pressing then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - pressPos
                if not dragging and delta.Magnitude > 5 then dragging = true end
                if dragging then
                    main.Position = UDim2.new(
                        startPos.X.Scale, startPos.X.Offset + delta.X,
                        startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                end
            end
        end)
    end

    local content = Instance.new("ScrollingFrame", main)
    content.Position = UDim2.new(0, 0, 0, 38)
    content.Size = UDim2.new(1, 0, 1, -38)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.Active = true
    content.ScrollBarThickness = 5
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local layout = Instance.new("UIListLayout", content)
    layout.Padding = UDim.new(0, 5)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    local pad = Instance.new("UIPadding", content)
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)

    local statusLbl = Instance.new("TextLabel", content)
    statusLbl.Size = UDim2.new(1, -12, 0, 50)
    statusLbl.BackgroundColor3 = Color3.fromRGB(35, 37, 45)
    statusLbl.TextColor3 = Color3.fromRGB(180, 255, 180)
    statusLbl.Font = Enum.Font.GothamBold
    statusLbl.TextSize = FONT - 2
    statusLbl.TextWrapped = true
    statusLbl.Text = "Запуск..."
    Instance.new("UICorner", statusLbl).CornerRadius = UDim.new(0, 6)

    local function makeBtn(text, color, fn)
        local b = Instance.new("TextButton", content)
        b.Size = UDim2.new(1, -12, 0, BTN_H)
        b.BackgroundColor3 = color
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = FONT
        b.Text = text
        b.Active = true
        b.ZIndex = 5
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(fn)
        b.Activated:Connect(fn)
        return b
    end

    local function makeToggle(label, get, set)
        local b = Instance.new("TextButton", content)
        b.Size = UDim2.new(1, -12, 0, BTN_H)
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.Gotham
        b.TextSize = FONT
        b.AutoButtonColor = false
        b.Active = true
        b.ZIndex = 5
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        local function refresh()
            local v = get()
            b.Text = (v and "✓ " or "✗ ") .. label
            b.BackgroundColor3 = v and Color3.fromRGB(60, 140, 80) or Color3.fromRGB(55, 55, 65)
        end
        local function handler() set(not get()); refresh() end
        b.MouseButton1Click:Connect(handler)
        b.Activated:Connect(handler)
        refresh()
        return b
    end

    makeToggle("Running", function() return state.running end, function(v) state.running = v end)
    makeToggle("Pause", function() return state.paused end, function(v) state.paused = v end)
    makeToggle("Use buffs", function() return CFG.UseBuffs end, function(v) CFG.UseBuffs = v end)
    makeToggle("Planters", function() return CFG.DoPlanters end, function(v) CFG.DoPlanters = v end)
    makeToggle("Quests", function() return CFG.DoQuests end, function(v) CFG.DoQuests = v end)

    makeBtn("→ Hive & Convert", Color3.fromRGB(200, 140, 50), function()
        state.forceConvert = true
    end)
    makeBtn("Claim hive now", Color3.fromRGB(100, 160, 200), function()
        task.spawn(claimHive)
    end)
    makeBtn("STOP", Color3.fromRGB(200, 60, 60), function()
        state.running = false
    end)

    -- Live update
    task.spawn(function()
        while gui.Parent do
            local fill = readBagFill() or 0
            statusLbl.Text = string.format(
                "🤖 %s\nМішок: %d%% | Pause: %s",
                state.fsm or "?",
                math.floor(fill * 100),
                tostring(state.paused))
            task.wait(1)
        end
    end)
end

pcall(buildGUI)

------------------------------------------------------------
-- ГОЛОВНИЙ ЦИКЛ
------------------------------------------------------------
local lastBuff = 0
local lastQuest = 0
local lastPlanter = 0

local function setFsm(s) state.fsm = s end

setFsm("INIT")
toast("✓ Запущено. Шукаю hive...", Color3.fromRGB(60, 180, 100), 2)

local myHive = claimHive()

while state.running do
    if state.paused then task.wait(1) ; setFsm("PAUSED"); continue end
    if not myHive then myHive = claimHive() ; if not myHive then task.wait(5); continue end end

    local ok, err = pcall(function()
        local bagFill = readBagFill() or 0

        -- Конвертація?
        if bagFill >= CFG.BagFullThreshold or state.forceConvert then
            setFsm("CONVERTING")
            convertAtHive(myHive)
            state.forceConvert = false
            return
        end

        -- Buffs раз на 4 хв
        if tick() - lastBuff > 240 then
            setFsm("BUFFS")
            useBuffs()
            lastBuff = tick()
        end

        -- Quests раз на 5 хв
        if tick() - lastQuest > 300 then
            setFsm("QUESTS")
            processQuests()
            lastQuest = tick()
        end

        -- Planters раз на 10 хв
        if tick() - lastPlanter > 600 then
            setFsm("PLANTERS")
            claimPlanters()
            lastPlanter = tick()
        end

        -- Фарм
        setFsm("FARMING")
        local fields = findFields()
        local fn = CFG.PreferredField
        local fm = fn and fields[fn]
        if not fm then
            -- Просто перше доступне
            for n, f in pairs(fields) do fn = n; fm = f; break end
        end
        if fm then farmField(fm) end
    end)
    if not ok then warn("[BSSA] " .. tostring(err)) ; task.wait(2) end

    task.wait(0.3)
end

toast("⏹ BSSA Macro зупинено", Color3.fromRGB(220, 80, 80), 3)
print("[BSSA] Завершено")
