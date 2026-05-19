--[[
    BSSA Scout — обстеження внутрішньої структури гри
    Bee Swarm Simulator Ascended

    Завантаж у грі через executor:
    loadstring(game:HttpGet("https://raw.githubusercontent.com/ilya2012w/roblox-scripts/main/bssa_scout.lua"))()

    Дивись output (F9 або консоль executor'а). Скинь мені результат.
--]]

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RS        = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

-- GUI для виводу
local pg = LP:WaitForChild("PlayerGui")
local sg = Instance.new("ScreenGui")
sg.Name = "BSSAScout"
sg.ResetOnSpawn = false
sg.DisplayOrder = 99999
sg.Parent = pg

local frame = Instance.new("Frame", sg)
frame.Size = UDim2.new(0.5, 0, 0.7, 0)
frame.Position = UDim2.new(0.25, 0, 0.15, 0)
frame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(255, 200, 60)
stroke.Thickness = 2

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1, 0, 0, 36)
title.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
title.Text = "🔍 BSSA Scout — структура гри"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(25, 25, 25)
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)

local closeBtn = Instance.new("TextButton", title)
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -36, 0, 2)
closeBtn.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Text = "✕"
closeBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)
closeBtn.Activated:Connect(function() sg:Destroy() end)

local copyBtn = Instance.new("TextButton", title)
copyBtn.Size = UDim2.new(0, 100, 0, 32)
copyBtn.Position = UDim2.new(1, -140, 0, 2)
copyBtn.BackgroundColor3 = Color3.fromRGB(80, 120, 200)
copyBtn.TextColor3 = Color3.new(1, 1, 1)
copyBtn.Text = "📋 Copy"
copyBtn.Font = Enum.Font.GothamBold
copyBtn.TextSize = 13
Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 6)

local scroll = Instance.new("ScrollingFrame", frame)
scroll.Size = UDim2.new(1, -20, 1, -50)
scroll.Position = UDim2.new(0, 10, 0, 42)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)

local text = Instance.new("TextLabel", scroll)
text.Size = UDim2.new(1, 0, 0, 0)
text.AutomaticSize = Enum.AutomaticSize.Y
text.BackgroundTransparency = 1
text.Font = Enum.Font.Code
text.TextSize = 12
text.TextColor3 = Color3.fromRGB(220, 220, 220)
text.TextXAlignment = Enum.TextXAlignment.Left
text.TextYAlignment = Enum.TextYAlignment.Top
text.TextWrapped = true
text.Text = ""

local output = {}
local function log(s)
    table.insert(output, s)
    text.Text = table.concat(output, "\n")
    print("[BSSA Scout] " .. s)
end

copyBtn.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard(text.Text)
        copyBtn.Text = "✓ Copied"
        task.delay(2, function() if copyBtn.Parent then copyBtn.Text = "📋 Copy" end end)
    end
end)

------------------------------------------------------------
-- РОЗВІДКА
------------------------------------------------------------
log("═══ BSSA SCOUT v1 ═══")
log("Game: " .. (game.Name or "?"))
log("PlaceId: " .. tostring(game.PlaceId))
log("Player: " .. LP.Name)
log("")

-- 1) Workspace top-level children
log("═══ WORKSPACE TOP-LEVEL ═══")
for _, child in ipairs(Workspace:GetChildren()) do
    log(string.format("  %s [%s]", child.Name, child.ClassName))
end
log("")

-- 2) ReplicatedStorage top-level
log("═══ REPLICATEDSTORAGE TOP-LEVEL ═══")
for _, child in ipairs(RS:GetChildren()) do
    log(string.format("  %s [%s]", child.Name, child.ClassName))
end
log("")

-- 3) Шукаємо все що схоже на FIELDS
log("═══ FIELDS (хто схоже на поле) ═══")
local fieldKeywords = { "field", "flower", "zone", "patch", "area" }
local found = 0
for _, obj in ipairs(Workspace:GetDescendants()) do
    local n = obj.Name:lower()
    for _, kw in ipairs(fieldKeywords) do
        if n:find(kw) and (obj:IsA("Model") or obj:IsA("Folder") or obj:IsA("BasePart")) then
            log(string.format("  [%s] %s (parent: %s)",
                obj.ClassName, obj.Name, obj.Parent and obj.Parent.Name or "?"))
            found = found + 1
            if found > 40 then log("  ...(truncated)"); break end
            break
        end
    end
    if found > 40 then break end
end
log("")

-- 4) Шукаємо HIVES
log("═══ HIVES ═══")
local hiveKeywords = { "hive", "honeycomb", "bee" }
found = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    local n = obj.Name:lower()
    for _, kw in ipairs(hiveKeywords) do
        if n:find(kw) then
            log(string.format("  [%s] %s", obj.ClassName, obj.Name))
            -- Подивимось ще rear-1 level вглиб
            for _, c in ipairs(obj:GetChildren()) do
                log(string.format("    └ %s [%s]", c.Name, c.ClassName))
                if #c:GetChildren() < 10 then
                    for _, cc in ipairs(c:GetChildren()) do
                        log(string.format("       └ %s [%s]", cc.Name, cc.ClassName))
                    end
                end
            end
            found = found + 1
            break
        end
    end
    if found > 5 then break end
end
log("")

-- 5) RemoteEvents/RemoteFunctions у ReplicatedStorage
log("═══ REMOTES ═══")
found = 0
for _, obj in ipairs(RS:GetDescendants()) do
    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
        log(string.format("  [%s] %s", obj.ClassName, obj.Name))
        found = found + 1
        if found > 30 then log("  ...(truncated)"); break end
    end
end
log("")

-- 6) ProximityPrompts в Workspace
log("═══ PROXIMITY PROMPTS ═══")
found = 0
for _, obj in ipairs(Workspace:GetDescendants()) do
    if obj:IsA("ProximityPrompt") then
        log(string.format("  [%s] action='%s' object='%s' parent=%s",
            obj.Parent.Name or "?",
            obj.ActionText or "",
            obj.ObjectText or "",
            obj.Parent and obj.Parent.Name or "?"))
        found = found + 1
        if found > 20 then log("  ...(truncated)"); break end
    end
end
log("")

-- 7) PlayerGui — топ-level (для кнопок claim/etc)
log("═══ PLAYERGUI TOP-LEVEL ═══")
for _, child in ipairs(pg:GetChildren()) do
    log(string.format("  %s [%s]", child.Name, child.ClassName))
end
log("")

-- 8) Активні tokens / collectibles
log("═══ COLLECTIBLES / TOKENS ═══")
local tokenKeywords = { "token", "collectible" }
found = 0
for _, obj in ipairs(Workspace:GetChildren()) do
    local n = obj.Name:lower()
    for _, kw in ipairs(tokenKeywords) do
        if n:find(kw) then
            log(string.format("  [%s] %s (%d children)",
                obj.ClassName, obj.Name, #obj:GetChildren()))
            -- Sample 3 children
            for i = 1, math.min(3, #obj:GetChildren()) do
                local c = obj:GetChildren()[i]
                log(string.format("    sample: %s [%s]", c.Name, c.ClassName))
            end
            found = found + 1
            break
        end
    end
end
log("")

-- 9) Backpack гравця
log("═══ BACKPACK ═══")
local bp = LP:FindFirstChild("Backpack")
if bp then
    for _, item in ipairs(bp:GetChildren()) do
        log(string.format("  %s [%s]", item.Name, item.ClassName))
    end
end
log("")

-- 10) Character
log("═══ CHARACTER ═══")
local char = LP.Character
if char then
    log("  Name: " .. char.Name)
    log("  Position: " .. tostring(char.PrimaryPart and char.PrimaryPart.Position or "?"))
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then log("  Health: " .. hum.Health .. "/" .. hum.MaxHealth) end
end

log("")
log("═══ DONE ═══")
log("Скопіюй (📋 Copy) і скинь Claude'у")

-- Логи в консоль для тих хто має executor console
for _, l in ipairs(output) do
    print("[BSSA] " .. l)
end
