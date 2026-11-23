--!nocheck

local Players = game:GetService("Players")
local RunSvc = game:GetService("RunService")

local ESP = {}

local DEFAULTS = {
    Enabled            = false,
    ShowBox            = true,
    ShowName           = true,
    ShowHealth         = true,
    ShowDistance       = true,
    ShowLine           = false,
    ShowHeadDot        = false,
    ShowSkeleton       = false,

    TextColor          = Color3.fromRGB(240, 240, 240),
    OutlineColor       = Color3.fromRGB(0, 0, 0),
    BoxColor           = Color3.fromRGB(255, 255, 255),
    LineColor          = Color3.fromRGB(255, 255, 255),
    HeadDotColor       = Color3.fromRGB(255, 80, 80),
    SkeletonColor      = Color3.fromRGB(255, 255, 255),

    BoxThickness       = 1,
    LineThickness      = 1,
    SkeletonThickness  = 1,
    HeadDotSize        = 4,

    BoxFilled          = false,
    BoxFillColor       = Color3.fromRGB(0, 0, 0),
    BoxFillAlpha       = 0.35,

    LineOrigin         = "Bottom",
    LinkBoxLineColor   = false,

    Font               = Enum.Font.GothamMedium,
    TextOutline        = true,
    TextLineSpacing    = 2,
    NameSize           = 13,
    HealthSize         = 11,
    DistSize           = 11,
    CustomSize         = 13,

    CustomText         = "",
    CustomTextPos      = "Below",

    ShowHealthBar      = true,
    HealthBarWidth     = 3,
    HealthBarSide      = "Left",
    HealthBarBg        = Color3.fromRGB(20, 20, 20),
    HealthGood         = Color3.fromRGB(80, 220, 120),
    HealthMid          = Color3.fromRGB(240, 200, 80),
    HealthLow          = Color3.fromRGB(240, 80, 80),
    HealthSmooth       = true,

    Smoothing          = true,
    SmoothFactor       = 0.4,
    MaxDistance        = 0,
    TeamCheck          = true,
    ExcludeLocal       = true,
    ExcludeDead        = true,
    ExcludeNPC         = true,
    DisplayOrder       = 2147480000,
    MinBoxHeight       = 6,
}

local state = {}
for k, v in pairs(DEFAULTS) do state[k] = v end

local playerData = {}
local container
local renderConn
local initialized = false

local function getContainer()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and type(h) == "Instance" then return h end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    local ok2, pg = pcall(function() return Players.LocalPlayer:WaitForChild("PlayerGui", 10) end)
    if ok2 and pg then return pg end
    return nil
end

local function hpColor(ratio)
    if ratio > 0.6 then return state.HealthGood end
    if ratio > 0.3 then return state.HealthMid end
    return state.HealthLow
end

local function worldToScreen(cam, pos)
    local vp = cam:WorldToViewportPoint(pos)
    if vp.Z <= 0.1 then return nil end
    return Vector2.new(vp.X, vp.Y)
end

local function getCharacterBox(character)
    local cam = workspace.CurrentCamera
    if not cam then return nil end

    local head = character:FindFirstChild("Head")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not (head and hrp) then return nil end

    local pHead = worldToScreen(cam, head.Position + Vector3.new(0, head.Size.Y * 0.5, 0))
    local pFoot = worldToScreen(cam, hrp.Position - Vector3.new(0, hrp.Size.Y * 0.5 + 1.3, 0))
    if not (pHead and pFoot) then return nil end

    local topY, botY = pHead.Y, pFoot.Y
    if botY <= topY + 1 then return nil end

    local pCenter = worldToScreen(cam, (head.Position + hrp.Position) * 0.5)
    if not pCenter then return nil end
    local cx = pCenter.X

    local maxHalf = 0
    local function tryPart(part)
        if not part or not part:IsA("BasePart") then return end
        local p = worldToScreen(cam, part.Position)
        if not p then return end
        local d = math.abs(p.X - cx)
        if d > maxHalf then maxHalf = d end
    end

    tryPart(character:FindFirstChild("LeftUpperArm"))
    tryPart(character:FindFirstChild("RightUpperArm"))
    tryPart(character:FindFirstChild("Left Arm"))
    tryPart(character:FindFirstChild("Right Arm"))
    tryPart(character:FindFirstChild("LeftLowerLeg"))
    tryPart(character:FindFirstChild("RightLowerLeg"))
    tryPart(character:FindFirstChild("Left Leg"))
    tryPart(character:FindFirstChild("Right Leg"))

    local h = botY - topY
    local halfW = maxHalf > 0 and (maxHalf * 1.15) or (h * 0.22)
    halfW = math.clamp(halfW, h * 0.14, h * 0.55)

    return cx - halfW, topY, cx + halfW, botY
end

local function newLabel(parent, name, size)
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.BorderSizePixel = 0
    l.TextColor3 = state.TextColor
    l.TextSize = size
    l.Font = state.Font
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.TextStrokeTransparency = state.TextOutline and 0.4 or 1
    l.TextStrokeColor3 = state.OutlineColor
    l.RichText = true
    l.Visible = false
    l.ZIndex = 2147480000
    l.Parent = parent
    return l
end

local function ensure(player)
    if playerData[player] then return playerData[player] end
    container = container or getContainer()
    if not container then return nil end

    local gui = Instance.new("ScreenGui")
    gui.Name = "\0ESP_" .. player.Name
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = state.DisplayOrder
    gui.Enabled = false
    gui.Parent = container

    local box = Instance.new("Frame")
    box.Name = "Box"
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.Visible = false
    box.ZIndex = 2147480000
    box.Parent = gui

    local stroke = Instance.new("UIStroke")
    stroke.Color = state.BoxColor
    stroke.Thickness = state.BoxThickness
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.LineJoinMode = Enum.LineJoinMode.Miter
    stroke.Parent = box

    local barBg = Instance.new("Frame")
    barBg.Name = "BarBg"
    barBg.BackgroundColor3 = state.HealthBarBg
    barBg.BorderSizePixel = 0
    barBg.Visible = false
    barBg.ZIndex = 2147480000
    barBg.Parent = gui

    local barFill = Instance.new("Frame")
    barFill.Name = "BarFill"
    barFill.BackgroundColor3 = state.HealthGood
    barFill.BorderSizePixel = 0
    barFill.AnchorPoint = Vector2.new(0, 1)
    barFill.Position = UDim2.fromScale(0, 1)
    barFill.Size = UDim2.fromScale(1, 1)
    barFill.ZIndex = 2147480001
    barFill.Parent = barBg

    local line = Instance.new("Frame")
    line.Name = "Line"
    line.AnchorPoint = Vector2.new(0, 0.5)
    line.BackgroundColor3 = state.LineColor
    line.BorderSizePixel = 0
    line.Visible = false
    line.ZIndex = 2147480002
    line.Parent = gui

    local dot = Instance.new("Frame")
    dot.Name = "HeadDot"
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.BackgroundColor3 = state.HeadDotColor
    dot.BorderSizePixel = 0
    dot.Visible = false
    dot.ZIndex = 2147480002
    dot.Parent = gui
    local dotStroke = Instance.new("UIStroke")
    dotStroke.Color = Color3.fromRGB(0, 0, 0)
    dotStroke.Thickness = 1
    dotStroke.Parent = dot

    local skelGui = Instance.new("Frame")
    skelGui.Name = "Skeleton"
    skelGui.BackgroundTransparency = 1
    skelGui.Visible = false
    skelGui.Size = UDim2.fromScale(1, 1)
    skelGui.ZIndex = 2147480000
    skelGui.Parent = gui

    playerData[player] = {
        Gui        = gui,
        Box        = box,
        Stroke     = stroke,
        BarBg      = barBg,
        BarFill    = barFill,
        Line       = line,
        Dot        = dot,
        Skel       = skelGui,
        SkelLines  = {},
        NameLbl    = newLabel(gui, "Name", state.NameSize),
        HealthLbl  = newLabel(gui, "Health", state.HealthSize),
        DistLbl    = newLabel(gui, "Dist", state.DistSize),
        CustomLbl  = newLabel(gui, "Custom", state.CustomSize),
        Smooth     = {a = 0, b = 0, c = 0, d = 0, ready = false},
        LastHp     = 0,
    }
    return playerData[player]
end

local function cleanup(player)
    local d = playerData[player]
    if d and d.Gui then
        pcall(function() d.Gui:Destroy() end)
    end
    playerData[player] = nil
end

local function fmtText(tpl, player, hum, dist)
    local s = tpl
    s = s:gsub("{name}", player.Name)
    s = s:gsub("{display}", player.DisplayName)
    s = s:gsub("{health}", tostring(math.floor(hum.Health)))
    s = s:gsub("{maxhealth}", tostring(math.floor(hum.MaxHealth)))
    s = s:gsub("{dist}", tostring(math.floor(dist)))
    s = s:gsub("{hp%%}", string.format("%d%%", math.floor(hum.Health / math.max(hum.MaxHealth, 1) * 100)))
    s = s:gsub("{team}", player.Team and player.Team.Name or "None")
    return s
end

local function drawSkeleton(d, character)
    local cam = workspace.CurrentCamera
    if not cam then return end

    local r15 = {
        {"Head", "UpperTorso"},
        {"UpperTorso", "LowerTorso"},
        {"UpperTorso", "LeftUpperArm"},
        {"LeftUpperArm", "LeftLowerArm"},
        {"LeftLowerArm", "LeftHand"},
        {"UpperTorso", "RightUpperArm"},
        {"RightUpperArm", "RightLowerArm"},
        {"RightLowerArm", "RightHand"},
        {"LowerTorso", "LeftUpperLeg"},
        {"LeftUpperLeg", "LeftLowerLeg"},
        {"LeftLowerLeg", "LeftFoot"},
        {"LowerTorso", "RightUpperLeg"},
        {"RightUpperLeg", "RightLowerLeg"},
        {"RightLowerLeg", "RightFoot"},
    }
    local r6 = {
        {"Head", "Torso"},
        {"Torso", "Left Arm"},
        {"Torso", "Right Arm"},
        {"Torso", "Left Leg"},
        {"Torso", "Right Leg"},
    }
    local set = character:FindFirstChild("UpperTorso") and r15 or r6
    local idx = 0
    for _, pair in ipairs(set) do
        local a = character:FindFirstChild(pair[1])
        local b = character:FindFirstChild(pair[2])
        if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
            local va = worldToScreen(cam, a.Position)
            local vb = worldToScreen(cam, b.Position)
            if va and vb then
                idx = idx + 1
                local seg = d.SkelLines[idx]
                if not seg then
                    seg = Instance.new("Frame")
                    seg.AnchorPoint = Vector2.new(0, 0.5)
                    seg.BorderSizePixel = 0
                    seg.ZIndex = 2147480000
                    seg.Parent = d.Skel
                    d.SkelLines[idx] = seg
                end
                local dx, dy = vb.X - va.X, vb.Y - va.Y
                local len = math.sqrt(dx * dx + dy * dy)
                seg.Visible = true
                seg.BackgroundColor3 = state.SkeletonColor
                seg.Position = UDim2.fromOffset(va.X, va.Y)
                seg.Size = UDim2.fromOffset(len, state.SkeletonThickness)
                seg.Rotation = math.deg(math.atan2(dy, dx))
            end
        end
    end
    for i = idx + 1, #d.SkelLines do
        d.SkelLines[i].Visible = false
    end
end

local function renderOne(player, d)
    local lp = Players.LocalPlayer
    if state.ExcludeLocal and player == lp then d.Gui.Enabled = false return end
    if state.TeamCheck and player.Team ~= nil and player.Team == lp.Team then
        d.Gui.Enabled = false
        return
    end

    local ch = player.Character
    if not ch then d.Gui.Enabled = false return end

    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hum then d.Gui.Enabled = false return end
    if state.ExcludeDead and hum.Health <= 0 then d.Gui.Enabled = false return end

    if state.ExcludeNPC and Players:GetPlayerFromCharacter(ch) == nil then
        d.Gui.Enabled = false
        return
    end

    local myCh = lp.Character
    local myHrp = myCh and myCh:FindFirstChild("HumanoidRootPart")
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    if not hrp then d.Gui.Enabled = false return end

    local dist = myHrp and (myHrp.Position - hrp.Position).Magnitude or 0
    if state.MaxDistance > 0 and dist > state.MaxDistance then
        d.Gui.Enabled = false
        return
    end

    local x1, y1, x2, y2 = getCharacterBox(ch)
    if not x1 then d.Gui.Enabled = false return end
    if x2 - x1 < 1 or y2 - y1 < state.MinBoxHeight then d.Gui.Enabled = false return end

    if state.Smoothing then
        local s = d.Smooth
        local f = math.clamp(state.SmoothFactor, 0.05, 1)
        if not s.ready then
            s.a, s.b, s.c, s.d = x1, y1, x2, y2
            s.ready = true
        else
            s.a = s.a + (x1 - s.a) * f
            s.b = s.b + (y1 - s.b) * f
            s.c = s.c + (x2 - s.c) * f
            s.d = s.d + (y2 - s.d) * f
        end
        x1, y1, x2, y2 = s.a, s.b, s.c, s.d
    end

    d.Gui.Enabled = true
    local w, h = x2 - x1, y2 - y1

    d.Box.Visible = state.ShowBox
    if state.ShowBox then
        d.Box.Position = UDim2.fromOffset(x1, y1)
        d.Box.Size = UDim2.fromOffset(w, h)
        d.Box.BackgroundTransparency = state.BoxFilled and (1 - state.BoxFillAlpha) or 1
        d.Box.BackgroundColor3 = state.BoxFillColor
        d.Stroke.Color = state.BoxColor
        d.Stroke.Thickness = state.BoxThickness
    end

    d.NameLbl.Visible = state.ShowName
    if state.ShowName then
        d.NameLbl.Text = player.DisplayName ~= player.Name
            and (player.Name .. ' <font color="#888888">' .. player.DisplayName .. '</font>')
            or player.Name
        d.NameLbl.TextColor3 = state.TextColor
        d.NameLbl.TextSize = state.NameSize
        d.NameLbl.Font = state.Font
        d.NameLbl.TextStrokeTransparency = state.TextOutline and 0.4 or 1
        d.NameLbl.Position = UDim2.fromOffset(x1, y1 - state.NameSize - state.TextLineSpacing)
        d.NameLbl.Size = UDim2.fromOffset(math.max(w, 140), state.NameSize + 2)
    end

    d.HealthLbl.Visible = state.ShowHealth
    if state.ShowHealth then
        local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
        d.HealthLbl.Text = string.format("%d / %d", math.floor(hum.Health), math.floor(hum.MaxHealth))
        d.HealthLbl.TextColor3 = hpColor(ratio)
        d.HealthLbl.TextSize = state.HealthSize
        d.HealthLbl.Font = state.Font
        d.HealthLbl.TextStrokeTransparency = state.TextOutline and 0.4 or 1
        d.HealthLbl.Position = UDim2.fromOffset(x1, y1 + h + state.TextLineSpacing)
        d.HealthLbl.Size = UDim2.fromOffset(math.max(w, 90), state.HealthSize + 2)
    end

    d.DistLbl.Visible = state.ShowDistance
    if state.ShowDistance then
        d.DistLbl.Text = tostring(math.floor(dist)) .. "m"
        d.DistLbl.TextColor3 = state.TextColor
        d.DistLbl.TextSize = state.DistSize
        d.DistLbl.Font = state.Font
        d.DistLbl.TextStrokeTransparency = state.TextOutline and 0.4 or 1
        local yOff = y1 + h + state.TextLineSpacing
        if state.ShowHealth then yOff = yOff + state.HealthSize + 2 end
        d.DistLbl.Position = UDim2.fromOffset(x1, yOff)
        d.DistLbl.Size = UDim2.fromOffset(math.max(w, 60), state.DistSize + 2)
    end

    d.CustomLbl.Visible = state.CustomText ~= ""
    if state.CustomText ~= "" then
        d.CustomLbl.Text = fmtText(state.CustomText, player, hum, dist)
        d.CustomLbl.TextColor3 = state.TextColor
        d.CustomLbl.TextSize = state.CustomSize
        d.CustomLbl.Font = state.Font
        d.CustomLbl.TextStrokeTransparency = state.TextOutline and 0.4 or 1
        if state.CustomTextPos == "Above" then
            local yOff = y1 - state.CustomSize - state.TextLineSpacing
            if state.ShowName then yOff = yOff - state.NameSize - 2 end
            d.CustomLbl.Position = UDim2.fromOffset(x1, yOff)
        else
            local yOff = y1 + h + state.TextLineSpacing
            if state.ShowHealth then yOff = yOff + state.HealthSize + 2 end
            if state.ShowDistance then yOff = yOff + state.DistSize + 2 end
            d.CustomLbl.Position = UDim2.fromOffset(x1, yOff)
        end
        d.CustomLbl.Size = UDim2.fromOffset(math.max(w, 180), state.CustomSize + 2)
    end

    d.BarBg.Visible = state.ShowHealthBar
    if state.ShowHealthBar then
        local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
        if state.HealthSmooth then
            d.LastHp = d.LastHp + (ratio - d.LastHp) * 0.25
        else
            d.LastHp = ratio
        end
        local draw = math.clamp(d.LastHp, 0.001, 1)
        d.BarBg.Position = state.HealthBarSide == "Left"
            and UDim2.fromOffset(x1 - state.HealthBarWidth - 2, y1)
            or UDim2.fromOffset(x2 + 2, y1)
        d.BarBg.Size = UDim2.fromOffset(state.HealthBarWidth, h)
        d.BarBg.BackgroundColor3 = state.HealthBarBg
        d.BarFill.BackgroundColor3 = hpColor(ratio)
        d.BarFill.Size = UDim2.fromScale(1, draw)
    end

    d.Line.Visible = state.ShowLine
    if state.ShowLine then
        local cam = workspace.CurrentCamera
        if cam then
            local vp = cam.ViewportSize
            local ox, oy
            if state.LineOrigin == "Top" then
                ox, oy = vp.X / 2, 60
            elseif state.LineOrigin == "Center" then
                ox, oy = vp.X / 2, vp.Y / 2
            else
                ox, oy = vp.X / 2, vp.Y - 60
            end
            local cxLine = x1 + w / 2
            local cyLine = (state.LineOrigin == "Top") and y1 or (y1 + h)
            local dx, dy = cxLine - ox, cyLine - oy
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 1 then
                d.Line.BackgroundColor3 = state.LineColor
                d.Line.Position = UDim2.fromOffset(ox, oy)
                d.Line.Size = UDim2.fromOffset(len, state.LineThickness)
                d.Line.Rotation = math.deg(math.atan2(dy, dx))
            else
                d.Line.Visible = false
            end
        end
    end

    d.Dot.Visible = state.ShowHeadDot
    if state.ShowHeadDot then
        local cam = workspace.CurrentCamera
        local head = ch:FindFirstChild("Head")
        if head and cam then
            local hp = worldToScreen(cam, head.Position)
            if hp then
                d.Dot.Position = UDim2.fromOffset(hp.X, hp.Y)
                d.Dot.Size = UDim2.fromOffset(state.HeadDotSize, state.HeadDotSize)
                d.Dot.BackgroundColor3 = state.HeadDotColor
            else
                d.Dot.Visible = false
            end
        else
            d.Dot.Visible = false
        end
    end

    d.Skel.Visible = state.ShowSkeleton
    if state.ShowSkeleton then
        drawSkeleton(d, ch)
    end
end

local function render()
    if not state.Enabled then
        for _, d in pairs(playerData) do
            if d.Gui then d.Gui.Enabled = false end
        end
        return
    end
    for player, d in pairs(playerData) do
        local ok = pcall(renderOne, player, d)
        if not ok and d.Gui then d.Gui.Enabled = false end
    end
end

function ESP:Init(opts)
    if initialized then
        if type(opts) == "table" then ESP:Set(opts) end
        return ESP
    end
    if type(opts) == "table" then
        for k, v in pairs(opts) do
            if k ~= "Name" and state[k] ~= nil then state[k] = v end
        end
    end
    container = getContainer()
    if not container then
        error("ESP.Init: 无法挂载 GUI（gethui / CoreGui / PlayerGui 全部失败）")
    end
    for _, p in ipairs(Players:GetPlayers()) do
        ensure(p)
    end
    Players.PlayerAdded:Connect(function(p) ensure(p) end)
    Players.PlayerRemoving:Connect(cleanup)
    renderConn = RunSvc.RenderStepped:Connect(render)
    initialized = true
    return ESP
end

function ESP:Set(opts)
    if type(opts) ~= "table" then return ESP end
    for k, v in pairs(opts) do
        if k == "Name" then
            ESP.Name = v
        elseif state[k] ~= nil then
            state[k] = v
        end
    end
    if opts.BoxColor ~= nil and state.LinkBoxLineColor then
        state.LineColor = opts.BoxColor
    end
    if opts.DisplayOrder ~= nil then
        for _, d in pairs(playerData) do
            if d.Gui then d.Gui.DisplayOrder = opts.DisplayOrder end
        end
    end
    return ESP
end

function ESP:Get(key)
    if key == "Name" then return ESP.Name end
    return state[key]
end

function ESP:Toggle(v)
    if v == nil then
        state.Enabled = not state.Enabled
    else
        state.Enabled = v and true or false
    end
    return ESP
end

function ESP:Enable() state.Enabled = true return ESP end
function ESP:Disable() state.Enabled = false return ESP end

function ESP:AddPlayer(p) return ensure(p) end

function ESP:Refresh()
    for p in pairs(playerData) do cleanup(p) end
    for _, p in ipairs(Players:GetPlayers()) do ensure(p) end
    return ESP
end

function ESP:Clear()
    for p in pairs(playerData) do cleanup(p) end
    return ESP
end

function ESP:Destroy()
    if renderConn then
        renderConn:Disconnect()
        renderConn = nil
    end
    for p in pairs(playerData) do cleanup(p) end
    initialized = false
    return ESP
end

function ESP:Defaults()
    local t = {}
    for k, v in pairs(DEFAULTS) do t[k] = v end
    return t
end

return ESP