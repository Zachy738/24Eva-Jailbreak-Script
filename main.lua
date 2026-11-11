

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ============ CONFIG & STATE ============
local CFG = {
    FlySpeed = 55, WalkSpeed = 55, JumpPower = 100,
    ArrestRange = 200, ArrestCooldown = 0.4, LoopCeiling = 50,
    ESPRefresh = 0.5, AimFOV = 150, AimSmooth = 0.15,
    AimPart = "Head", AimTeamCheck = true, AimWallCheck = true,
    AimKey = Enum.KeyCode.E, AimSilent = false, AimAuto = false, -- AimAuto: aim without holding key
    TakeoverFlySpeed = 80, AutoRobDelay = 1.0, ArrestAuraRate = 0.5,
    ItemESPRange = 200, AutoCollectRate = 0.2, carSpeedMult = 300000,
}

local S = {
    flying = false, flyVel = nil, flyGyro = nil,
    speedOn = false, jumpOn = false, noclipOn = false, infJumpOn = false,
    arrestOn = false, lastArrest = 0, espOn = false, itemESPOn = false,
    fullbright = false, noFog = false, antiAfk = false, antiAfkConn = nil,
    carSpeedOn = false, carSpeedConn = nil, espObjects = {}, itemESPObjects = {},
    aimEnabled = false, aimHeld = false, fovCircle = nil, takeoverActive = false,
    autoRobOn = false, autoRobConn = nil, arrestAuraOn = false, arrestAuraConn = nil,
    infAmmoOn = false, infAmmoConn = nil, bitBaggerOn = false, bitBaggerConn = nil,
}

local ArrestRemote = nil
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if remotes then ArrestRemote = remotes:FindFirstChild("ArrestPlayer") or remotes:FindFirstChild("Arrest") end
if not ArrestRemote then ArrestRemote = ReplicatedStorage:FindFirstChild("ArrestPlayer") or ReplicatedStorage:FindFirstChild("Arrest") end
local LegacyArrestRemote = Workspace:FindFirstChild("Remote") and Workspace.Remote:FindFirstChild("arrest")

-- ============ HELPERS ============
local function getChar()
    local c = LP.Character; if not c then return nil end
    local hrp = c:FindFirstChild("HumanoidRootPart"); local hum = c:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return nil end
    return c, hrp, hum
end
local function isCop() return LP.Team and LP.Team.Name == "Police" end

-- ============ CORE LOGIC ============
local function stopFly()
    S.flying = false
    if S.flyVel then S.flyVel:Destroy(); S.flyVel = nil end
    if S.flyGyro then S.flyGyro:Destroy(); S.flyGyro = nil end
end
local function startFly(speedOverride)
    local _, hrp = getChar(); if not hrp or S.flying then return end
    S.flying = true
    S.flyGyro = Instance.new("BodyGyro"); S.flyGyro.P = 9e4
    S.flyGyro.MaxTorque = Vector3.new(9e9,9e9,9e9); S.flyGyro.CFrame = hrp.CFrame; S.flyGyro.Parent = hrp
    S.flyVel = Instance.new("BodyVelocity"); S.flyVel.Velocity = Vector3.zero
    S.flyVel.MaxForce = Vector3.new(9e9,9e9,9e9); S.flyVel.Parent = hrp
    if speedOverride then CFG.FlySpeed = speedOverride end
end
RunService.RenderStepped:Connect(function()
    if not S.flying or not S.flyVel or not S.flyGyro then return end
    local _, hrp = getChar(); if not hrp then stopFly(); return end
    local cam = Workspace.CurrentCamera; local move = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += cam.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= cam.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += cam.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= cam.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
    S.flyVel.Velocity = move.Magnitude > 0 and move.Unit * CFG.FlySpeed or Vector3.zero
    S.flyGyro.CFrame = cam.CFrame
end)
local function applySpeed()
    local _, _, hum = getChar(); if hum then hum.WalkSpeed = S.speedOn and CFG.WalkSpeed or 16 end
end
local function applyJump()
    local _, _, hum = getChar(); if hum then hum.JumpPower = S.jumpOn and CFG.JumpPower or 50 end
end
local function setNoclip(on)
    S.noclipOn = on
    if S.noclipConn then S.noclipConn:Disconnect(); S.noclipConn = nil end
    if not on then return end
    S.noclipConn = RunService.Stepped:Connect(function()
        local char = LP.Character; if not char then return end
        for _, p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end end
    end)
end
local function setInfJump(on)
    S.infJumpOn = on
    if S.infJumpConn then S.infJumpConn:Disconnect(); S.infJumpConn = nil end
    if not on then return end
    S.infJumpConn = UserInputService.JumpRequest:Connect(function()
        local _, _, hum = getChar(); if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end
local function setFullbright(on)
    S.fullbright = on
    if on then Lighting.Brightness = 3; Lighting.ClockTime = 12; Lighting.GlobalShadows = false
    else Lighting.Brightness = 2; Lighting.GlobalShadows = true end
end
local function setNoFog(on)
    S.noFog = on
    if on then Lighting.FogEnd = 1e6; Lighting.FogStart = 1e6
    else Lighting.FogEnd = 1000; Lighting.FogStart = 0 end
end
local function setAntiAfk(on)
    S.antiAfk = on
    if S.antiAfkConn then S.antiAfkConn:Disconnect(); S.antiAfkConn = nil end
    if not on then return end
    S.antiAfkConn = LP.Idled:Connect(function() game:GetService("VirtualUser"):CaptureController(); game:GetService("VirtualUser"):ClickButton2(Vector2.new()) end)
end

-- ============ AIMBOT ============
local function isVisible(part)
    if not CFG.AimWallCheck then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LP.Character, Camera}
    local origin = Camera.CFrame.Position
    local result = Workspace:Raycast(origin, part.Position - origin, params)
    return not result or result.Instance:IsDescendantOf(part.Parent)
end

local function getClosestTarget()
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local best, bestDist = nil, CFG.AimFOV
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LP then continue end
        local c = plr.Character
        if not c then continue end
        local hum = c:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        if CFG.AimTeamCheck and plr.Team and LP.Team and plr.Team == LP.Team then continue end
        local part = c:FindFirstChild(CFG.AimPart) or c:FindFirstChild("HumanoidRootPart")
        if not part then continue end
        local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen then continue end
        local screenDist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
        if screenDist >= bestDist then continue end
        if not isVisible(part) then continue end
        best = plr; bestDist = screenDist
    end
    return best
end

local function aimAtTarget(target)
    if not target or not target.Character then return end
    local part = target.Character:FindFirstChild(CFG.AimPart) or target.Character:FindFirstChild("HumanoidRootPart")
    if not part then return end
    local targetCFrame = CFrame.lookAt(Camera.CFrame.Position, part.Position)
    if CFG.AimSilent then
        Camera.CFrame = targetCFrame
    else
        local alpha = 1 - math.pow(1 - CFG.AimSmooth, RunService.RenderStepped:Wait() * 60)
        Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, alpha)
    end
end

local function ensureFovCircle()
    if S.fovCircle then return end
    if not Drawing then return end
    S.fovCircle = Drawing.new("Circle")
    S.fovCircle.Thickness = 1
    S.fovCircle.Color = Color3.fromRGB(255, 80, 80)
    S.fovCircle.Filled = false
    S.fovCircle.Transparency = 0.7
    S.fovCircle.Visible = false
end

RunService.RenderStepped:Connect(function()
    if not S.aimEnabled then
        if S.fovCircle then S.fovCircle.Visible = false end
        return
    end
    ensureFovCircle()
    if S.fovCircle then
        S.fovCircle.Visible = true
        S.fovCircle.Radius = CFG.AimFOV
        local mousePos = UserInputService:GetMouseLocation()
        local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        S.fovCircle.Position = (UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter) and center or mousePos
    end
    -- Aimbot engages if: key is held, OR auto-aim is on
    if not S.aimHeld and not CFG.AimAuto then return end
    local target = getClosestTarget()
    S.aimTarget = target
    if target then aimAtTarget(target) end
end)

-- ============ PRO UI ============
local function createProUI()
    local C = {
        Bg = Color3.fromRGB(24, 24, 28),
        Panel = Color3.fromRGB(32, 32, 38),
        Sidebar = Color3.fromRGB(16, 16, 20),
        Accent = Color3.fromRGB(120, 100, 255),
        AccentGlow = Color3.fromRGB(160, 140, 255),
        Text = Color3.fromRGB(245, 245, 250),
        Sub = Color3.fromRGB(140, 140, 155),
        ToggleOff = Color3.fromRGB(50, 50, 60),
        ToggleOn = Color3.fromRGB(0, 210, 110),
    }

    local function tween(o, p, t, tm) TweenService:Create(o, TweenInfo.new(tm or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {[p] = t}):Play() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "JBProUI"
    gui.ResetOnSpawn = false
    pcall(function() gui.Parent = CoreGui end)
    if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 640, 0, 440)
    main.Position = UDim2.new(0.5, -320, 0.5, -220)
    main.BackgroundColor3 = C.Bg
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", main); stroke.Color = Color3.fromRGB(60, 60, 75); stroke.Thickness = 1
    
    local shadow = Instance.new("ImageLabel", main)
    shadow.Size = UDim2.new(1, 30, 1, 30); shadow.Position = UDim2.new(0, -15, 0, -15)
    shadow.BackgroundTransparency = 1; shadow.Image = "rbxassetid://5028857472"
    shadow.ImageColor3 = Color3.new(0,0,0); shadow.ImageTransparency = 0.5
    shadow.ScaleType = Enum.ScaleType.Slice; shadow.SliceCenter = Rect.new(24,24,276,276)
    shadow.ZIndex = 0

    -- Dragging
    local dragging, dragStart, startPos
    main.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = main.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Header
    local header = Instance.new("Frame", main)
    header.Size = UDim2.new(1, 0, 0, 55); header.BackgroundTransparency = 1; header.ZIndex = 2
    local title = Instance.new("TextLabel", header)
    title.Size = UDim2.new(1, -60, 1, 0); title.Position = UDim2.new(0, 20, 0, 0)
    title.BackgroundTransparency = 1; title.Text = "Jailbreak — Takeover"
    title.TextColor3 = C.Text; title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold; title.TextSize = 16

    local closeBtn = Instance.new("TextButton", header)
    closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.Position = UDim2.new(1, -40, 0.5, -15)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80); closeBtn.BackgroundTransparency = 0.85
    closeBtn.Text = "×"; closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
    closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 20; closeBtn.BorderSizePixel = 0
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
    closeBtn.MouseEnter:Connect(function() tween(closeBtn, "BackgroundTransparency", 0.6) end)
    closeBtn.MouseLeave:Connect(function() tween(closeBtn, "BackgroundTransparency", 0.85) end)
    closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

    -- Sidebar
    local sidebar = Instance.new("Frame", main)
    sidebar.Size = UDim2.new(0, 160, 1, -70); sidebar.Position = UDim2.new(0, 15, 0, 55)
    sidebar.BackgroundColor3 = C.Sidebar; sidebar.BorderSizePixel = 0
    Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 10)
    local sideLayout = Instance.new("UIListLayout", sidebar)
    sideLayout.Padding = UDim.new(0, 4); sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
    Instance.new("UIPadding", sidebar).PaddingTop = UDim.new(0, 10)

    -- Content Area
    local contentArea = Instance.new("ScrollingFrame", main)
    contentArea.Size = UDim2.new(1, -195, 1, -75); contentArea.Position = UDim2.new(0, 185, 0, 65)
    contentArea.BackgroundTransparency = 1; contentArea.ScrollBarThickness = 3
    contentArea.ScrollBarImageColor3 = C.Accent; contentArea.BorderSizePixel = 0
    contentArea.CanvasSize = UDim2.new(0, 0, 0, 0)
    local contentLayout = Instance.new("UIListLayout", contentArea)
    contentLayout.Padding = UDim.new(0, 10); contentLayout.SortOrder = Enum.SortOrder.LayoutOrder

    -- Components
    local function addToggle(parent, text, default, callback)
        local container = Instance.new("Frame", parent)
        container.Size = UDim2.new(1, -10, 0, 44); container.BackgroundColor3 = C.Panel
        container.BorderSizePixel = 0; Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

        local label = Instance.new("TextLabel", container)
        label.Size = UDim2.new(1, -70, 1, 0); label.Position = UDim2.new(0, 15, 0, 0)
        label.BackgroundTransparency = 1; label.Text = text
        label.TextColor3 = C.Text; label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Gotham; label.TextSize = 13

        local switchBg = Instance.new("Frame", container)
        switchBg.Size = UDim2.new(0, 38, 0, 22); switchBg.Position = UDim2.new(1, -53, 0.5, -11)
        switchBg.BackgroundColor3 = default and C.ToggleOn or C.ToggleOff
        switchBg.BorderSizePixel = 0; Instance.new("UICorner", switchBg).CornerRadius = UDim.new(0, 11)

        local knob = Instance.new("Frame", switchBg)
        knob.Size = UDim2.new(0, 18, 0, 18); knob.Position = default and UDim2.new(0, 18, 0, 2) or UDim2.new(0, 2, 0, 2)
        knob.BackgroundColor3 = Color3.new(1, 1, 1); knob.BorderSizePixel = 0
        Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 9)

        local state = default
        local btn = Instance.new("TextButton", container)
        btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1; btn.Text = ""
        
        btn.MouseButton1Click:Connect(function()
            state = not state
            tween(switchBg, "BackgroundColor3", state and C.ToggleOn or C.ToggleOff)
            tween(knob, "Position", state and UDim2.new(0, 18, 0, 2) or UDim2.new(0, 2, 0, 2))
            if callback then pcall(callback, state) end
        end)
        btn.MouseEnter:Connect(function() tween(container, "BackgroundColor3", Color3.fromRGB(40, 40, 48)) end)
        btn.MouseLeave:Connect(function() tween(container, "BackgroundColor3", C.Panel) end)
    end

    local function addButton(parent, text, callback)
        local btn = Instance.new("TextButton", parent)
        btn.Size = UDim2.new(1, -10, 0, 40); btn.BackgroundColor3 = C.Accent
        btn.BackgroundTransparency = 0.85; btn.Text = text
        btn.TextColor3 = C.AccentGlow; btn.Font = Enum.Font.GothamBold
        btn.TextSize = 13; btn.BorderSizePixel = 0
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        btn.MouseEnter:Connect(function() tween(btn, "BackgroundTransparency", 0.5) end)
        btn.MouseLeave:Connect(function() tween(btn, "BackgroundTransparency", 0.85) end)
        btn.MouseButton1Click:Connect(function() if callback then pcall(callback) end end)
    end

    local function addSlider(parent, text, default, min, max, callback)
        local container = Instance.new("Frame", parent)
        container.Size = UDim2.new(1, -10, 0, 60); container.BackgroundColor3 = C.Panel
        container.BorderSizePixel = 0; Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

        local label = Instance.new("TextLabel", container)
        label.Size = UDim2.new(1, -20, 0, 25); label.Position = UDim2.new(0, 15, 0, 5)
        label.BackgroundTransparency = 1; label.Text = text .. ": " .. default
        label.TextColor3 = C.Text; label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Gotham; label.TextSize = 12

        local barBg = Instance.new("Frame", container)
        barBg.Size = UDim2.new(1, -30, 0, 6); barBg.Position = UDim2.new(0, 15, 0, 40)
        barBg.BackgroundColor3 = C.ToggleOff; barBg.BorderSizePixel = 0
        Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame", barBg)
        fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
        fill.BackgroundColor3 = C.Accent; fill.BorderSizePixel = 0
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("Frame", barBg)
        knob.Size = UDim2.new(0, 14, 0, 14); knob.Position = UDim2.new((default - min) / (max - min), -7, 0.5, -7)
        knob.BackgroundColor3 = Color3.new(1,1,1); knob.BorderSizePixel = 0
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        local btn = Instance.new("TextButton", barBg)
        btn.Size = UDim2.new(1, 0, 2, 0); btn.Position = UDim2.new(0, 0, -0.5, 0)
        btn.BackgroundTransparency = 1; btn.Text = ""

        local dragging = false
        local function update(input)
            local relX = math.clamp((input.Position.X - barBg.AbsolutePosition.X) / barBg.AbsoluteSize.X, 0, 1)
            local val = math.floor(min + relX * (max - min))
            fill.Size = UDim2.new(relX, 0, 1, 0)
            knob.Position = UDim2.new(relX, -7, 0.5, -7)
            label.Text = text .. ": " .. val
            if callback then pcall(callback, val) end
        end
        btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true; update(input)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then update(input) end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
    end

    -- Tabs
    local tabs = {}; local currentTab = nil
    local tabList = { "Takeover", "Movement", "Combat", "Aimbot", "Auto", "Settings" }
    
    local function switchTab(btnRef, frameRef)
        if currentTab then 
            tween(currentTab.frame, "Position", UDim2.new(0, 20, 0, 0)); currentTab.frame.Visible = false 
            tween(currentTab.btn, "BackgroundTransparency", 1)
            currentTab.btn.TextColor3 = C.Sub 
        end
        currentTab = { btn = btnRef, frame = frameRef }
        frameRef.Visible = true; frameRef.Position = UDim2.new(0, -20, 0, 0)
        tween(frameRef, "Position", UDim2.new(0, 0, 0, 0))
        tween(btnRef, "BackgroundTransparency", 0.8)
        btnRef.TextColor3 = C.Text
    end

    for i, name in ipairs(tabList) do
        local btn = Instance.new("TextButton", sidebar)
        btn.Size = UDim2.new(1, -10, 0, 34); btn.BackgroundTransparency = 1
        btn.BackgroundColor3 = C.Accent
        btn.Text = "  " .. name; btn.TextColor3 = C.Sub
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Font = Enum.Font.Gotham; btn.TextSize = 13
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        
        btn.MouseEnter:Connect(function() if not currentTab or currentTab.btn ~= btn then tween(btn, "BackgroundTransparency", 0.9); tween(btn, "TextColor3", C.Text) end end)
        btn.MouseLeave:Connect(function() if not currentTab or currentTab.btn ~= btn then tween(btn, "BackgroundTransparency", 1); tween(btn, "TextColor3", C.Sub) end end)

        local frame = Instance.new("Frame", contentArea)
        frame.Size = UDim2.new(1, -10, 0, 500); frame.BackgroundTransparency = 1; frame.Visible = false
        local fLayout = Instance.new("UIListLayout", frame)
        fLayout.Padding = UDim.new(0, 8); fLayout.SortOrder = Enum.SortOrder.LayoutOrder

        btn.MouseButton1Click:Connect(function() switchTab(btn, frame) end)
        if i == 1 then switchTab(btn, frame) end
        table.insert(tabs, { name = name, frame = frame })
    end

    -- Populate Tabs
    local TakeoverTab = tabs[1].frame
    addButton(TakeoverTab, "TAKEOVER (Cop Only)", function()
        if not isCop() then return end
        S.takeoverActive = true; if not S.flying then startFly(CFG.TakeoverFlySpeed) end
        S.speedOn = true; applySpeed(); S.jumpOn = true; applyJump()
        setNoclip(true); S.arrestOn = true; S.espOn = true
        setFullbright(true); setNoFog(true)
    end)
    addButton(TakeoverTab, "Stand Down", function()
        S.takeoverActive = false; stopFly()
        S.speedOn = false; applySpeed(); S.jumpOn = false; applyJump()
        setNoclip(false); S.arrestOn = false; S.espOn = false
        setFullbright(false); setNoFog(false)
    end)

    local MoveTab = tabs[2].frame
    addToggle(MoveTab, "Fly (F)", false, function(v) if v then startFly() else stopFly() end end)
    addSlider(MoveTab, "Fly Speed", CFG.FlySpeed, 20, 150, function(v) CFG.FlySpeed = v end)
    addToggle(MoveTab, "Speed Boost (G)", false, function(v) S.speedOn = v; applySpeed() end)
    addSlider(MoveTab, "Walk Speed", CFG.WalkSpeed, 16, 150, function(v) CFG.WalkSpeed = v; if S.speedOn then applySpeed() end end)
    addToggle(MoveTab, "Jump Boost (H)", false, function(v) S.jumpOn = v; applyJump() end)
    addToggle(MoveTab, "Infinite Jump (I)", false, setInfJump)
    addToggle(MoveTab, "Noclip (N)", false, setNoclip)

    local CombatTab = tabs[3].frame
    addToggle(CombatTab, "Auto-Arrest (J)", false, function(v) S.arrestOn = v end)
    addToggle(CombatTab, "Arrest Aura", false, function(v)
        S.arrestAuraOn = v
        if S.arrestAuraConn then task.cancel(S.arrestAuraConn); S.arrestAuraConn = nil end
        if not v then return end
        S.arrestAuraConn = task.spawn(function()
            while S.arrestAuraOn do
                pcall(function()
                    local remote = LegacyArrestRemote or ArrestRemote
                    local _, myHrp = getChar()
                    if remote and myHrp and isCop() then
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr ~= LP and plr.Team and plr.Team.Name ~= "Police" and plr.Character then
                                local h = plr.Character:FindFirstChild("HumanoidRootPart")
                                if h and (h.Position - myHrp.Position).Magnitude <= CFG.ArrestRange then
                                    if remote:IsA("RemoteFunction") then remote:InvokeServer(h) else remote:FireServer(plr) end
                                end
                            end
                        end
                    end
                end)
                task.wait(CFG.ArrestAuraRate)
            end
        end)
    end)
    addButton(CombatTab, "Teleport to Nearest Criminal", function()
        if not isCop() then return end
        local _, myHrp = getChar(); if not myHrp then return end
        local best, bd = nil, math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Team and p.Team.Name ~= "Police" and p.Character then
                local h = p.Character:FindFirstChild("HumanoidRootPart")
                if h then local d = (h.Position - myHrp.Position).Magnitude; if d < bd then bd = d; best = p end end
            end
        end
        if best and best.Character then local h = best.Character:FindFirstChild("HumanoidRootPart"); if h then myHrp.CFrame = h.CFrame * CFrame.new(0,5,0) end end
    end)

    local AimTab = tabs[4].frame
    addToggle(AimTab, "Aimbot Master (Q)", false, function(v) S.aimEnabled = v end)
    addToggle(AimTab, "Auto-Aim (No Key)", false, function(v) CFG.AimAuto = v end)
    addToggle(AimTab, "Silent Aim", false, function(v) CFG.AimSilent = v end)
    addSlider(AimTab, "FOV Radius", CFG.AimFOV, 20, 500, function(v) CFG.AimFOV = v end)
    addSlider(AimTab, "Smoothness", CFG.AimSmooth, 0.02, 0.8, function(v) CFG.AimSmooth = v end) -- Note: rounding needs to be handled if you use ints, but float works here
    addToggle(AimTab, "Team Check", true, function(v) CFG.AimTeamCheck = v end)
    addToggle(AimTab, "Wall Check", true, function(v) CFG.AimWallCheck = v end)

    local AutoTab = tabs[5].frame
    addToggle(AutoTab, "Auto Rob (All Stores)", false, function(v)
        S.autoRobOn = v
        if S.autoRobConn then task.cancel(S.autoRobConn); S.autoRobConn = nil end
        if not v then return end
        S.autoRobConn = task.spawn(function()
            while S.autoRobOn do
                local _, hrp = getChar()
                if hrp then
                    local locs = { Vector3.new(-291,8,-304), Vector3.new(-55,8,-230), Vector3.new(291,8,-225), Vector3.new(0,8,800), Vector3.new(1196,8,-609) }
                    for _, p in ipairs(locs) do if not S.autoRobOn then break end; pcall(function() hrp.CFrame = CFrame.new(p + Vector3.new(0,5,0)) end); task.wait(CFG.AutoRobDelay) end
                end
                task.wait(2)
            end
        end)
    end)
    addToggle(AutoTab, "Infinite Ammo / No Reload", false, function(v)
        S.infAmmoOn = v
        if S.infAmmoConn then S.infAmmoConn:Disconnect(); S.infAmmoConn = nil end
        if not v then return end
        S.infAmmoConn = RunService.Heartbeat:Connect(function()
            local char = LP.Character; if not char then return end
            local tool = char:FindFirstChildOfClass("Tool"); if not tool then return end
            for _, c in ipairs(tool:GetChildren()) do
                if c.Name == "Ammo" or c.Name == "AmmoInClip" or c.Name == "Clip" then
                    if c:IsA("IntValue") or c:IsA("NumberValue") then c.Value = 999 end
                end
                if c.Name == "Reloading" and c:IsA("BoolValue") then c.Value = false end
            end
        end)
    end)
    addToggle(AutoTab, "Supercar Speed", false, function(v)
        S.carSpeedOn = v
        if S.carSpeedConn then S.carSpeedConn:Disconnect(); S.carSpeedConn = nil end
        if not v then return end
        S.carSpeedConn = RunService.RenderStepped:Connect(function()
            pcall(function()
                local vehicles = Workspace:FindFirstChild("Vehicles"); if not vehicles then return end
                for _, car in ipairs(vehicles:GetChildren()) do
                    local seat = car:FindFirstChild("Seat")
                    if seat and seat:FindFirstChild("PlayerName") and seat.PlayerName.Value == LP.Name then
                        local engine = car:FindFirstChild("Engine"); if engine then
                            local bf = engine:FindFirstChild("BodyForce") or engine:FindFirstChild("VectorForce")
                            if not bf then bf = Instance.new("BodyForce"); bf.Name = "JBSupercarForce"; bf.Parent = engine end
                            if bf then bf.Force = car.PrimaryPart.CFrame.LookVector * CFG.carSpeedMult end
                        end
                        break
                    end
                end
            end)
        end)
    end)
    addToggle(AutoTab, "Bit Bagger / Auto Collect", false, function(v)
        S.bitBaggerOn = v
        if S.bitBaggerConn then task.cancel(S.bitBaggerConn); S.bitBaggerConn = nil end
        if not v then return end
        S.bitBaggerConn = task.spawn(function()
            while S.bitBaggerOn do
                pcall(function()
                    local _, hrp = getChar(); if hrp then
                        local best, bestDist = nil, 50
                        for _, obj in ipairs(Workspace:GetDescendants()) do
                            if obj:IsA("BasePart") then
                                local n = obj.Name:lower()
                                if n:find("bit") or n:find("bag") or n:find("cash") or n:find("pickup") then
                                    local d = (obj.Position - hrp.Position).Magnitude
                                    if d < bestDist then bestDist = d; best = obj end
                                end
                            end
                        end
                        if best then hrp.CFrame = best.CFrame * CFrame.new(0, 3, 0) end
                    end
                end)
                task.wait(CFG.AutoCollectRate)
            end
        end)
    end)
    addButton(AutoTab, "Auto Escape Jail", function()
        pcall(function()
            local _, hrp = getChar()
            if hrp then hrp.CFrame = CFrame.new(-100, 50, -400); task.wait(0.3); game:GetService("VirtualUser"):CaptureController(); game:GetService("VirtualUser"):ClickButton1(Vector2.new()) end
        end)
    end)

    local SetTab = tabs[6].frame
    addToggle(SetTab, "Anti-AFK", false, setAntiAfk)
    addToggle(SetTab, "Fullbright", false, setFullbright)
    addToggle(SetTab, "Item ESP", false, function(v) S.itemESPOn = v; if not v then for _, d in pairs(S.itemESPObjects) do if d.Remove then d:Remove() end end end; S.itemESPObjects = {} end)
    addButton(SetTab, "Rejoin Server", function() game:GetService("TeleportService"):Teleport(game.PlaceId, LP) end)
    addButton(SetTab, "Unload UI", function() gui:Destroy() end)

    task.spawn(function()
        while gui.Parent do
            task.wait(1)
            if currentTab and currentTab.frame then
                local absSize = currentTab.frame.AbsoluteSize.Y
                contentArea.CanvasSize = UDim2.new(0, 0, 0, absSize + 20)
            end
        end
    end)
end

local success, err = pcall(createProUI)
if not success then warn("[JB] UI Failed: " .. tostring(err)) end

-- ============ BACKGROUND LOOPS & HOTKEYS ============
task.spawn(function()
    while true do task.wait(0.1)
        if S.arrestOn and isCop() and (ArrestRemote or LegacyArrestRemote) then
            pcall(function()
                local remote = LegacyArrestRemote or ArrestRemote
                local _, myHrp = getChar(); local now = tick()
                if myHrp and now - S.lastArrest >= CFG.ArrestCooldown then
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LP and plr.Team and plr.Team.Name ~= "Police" and plr.Character then
                            local h = plr.Character:FindFirstChild("HumanoidRootPart")
                            if h and (h.Position - myHrp.Position).Magnitude <= CFG.ArrestRange then
                                if remote:IsA("RemoteFunction") then remote:InvokeServer(h) else remote:FireServer(plr) end
                                S.lastArrest = now; break
                            end
                        end
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while true do task.wait(CFG.ESPRefresh)
        if S.espOn then
            pcall(function()
                local cam = Workspace.CurrentCamera; local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LP and plr.Character then
                        local h = plr.Character:FindFirstChild("HumanoidRootPart"); local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                        if h and hum and hum.Health > 0 then
                            local pos, onScreen = cam:WorldToViewportPoint(h.Position)
                            if onScreen then
                                if not S.espObjects[plr] then local d = Drawing.new("Square"); d.Thickness = 1; d.Filled = false; S.espObjects[plr] = d end
                                local d = S.espObjects[plr]; local dist = myHrp and (h.Position - myHrp.Position).Magnitude or 0
                                local size = math.clamp(1200 / math.max(dist, 1), 8, 60)
                                local team = plr.Team and plr.Team.Name or "None"
                                d.Color = team == "Criminals" and Color3.fromRGB(255,60,60) or team == "Police" and Color3.fromRGB(60,120,255) or Color3.fromRGB(200,200,200)
                                d.Size = Vector2.new(size, size * 1.8); d.Position = Vector2.new(pos.X - size/2, pos.Y - size*0.9); d.Visible = true
                            elseif S.espObjects[plr] then S.espObjects[plr].Visible = false end
                        end
                    end
                end
            end)
        else
            pcall(function() for _, d in pairs(S.espObjects) do if d and d.Remove then d:Remove() end end end); S.espObjects = {}
        end
    end
end)

task.spawn(function()
    while true do task.wait(CFG.ESPRefresh)
        if S.itemESPOn then
            pcall(function()
                local cam = Workspace.CurrentCamera; local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"); local i = 0
                for _, obj in ipairs(Workspace:GetDescendants()) do
                    if obj:IsA("BasePart") then
                        local n = obj.Name:lower()
                        if n:find("bag") or n:find("cash") or n:find("pickup") or n:find("artifact") or n:find("briefcase") or n:find("loot") then
                            i += 1; if i > 50 then break end
                            local pos, onScreen = cam:WorldToViewportPoint(obj.Position)
                            if onScreen and myHrp and (obj.Position - myHrp.Position).Magnitude <= CFG.ItemESPRange then
                                if not S.itemESPObjects[i] then S.itemESPObjects[i] = Drawing.new("Square"); S.itemESPObjects[i].Thickness = 1; S.itemESPObjects[i].Filled = false; S.itemESPObjects[i].Color = Color3.fromRGB(255, 200, 50) end
                                local d = S.itemESPObjects[i]; d.Visible = true; d.Size = Vector2.new(12, 12); d.Position = Vector2.new(pos.X - 6, pos.Y - 6)
                            elseif S.itemESPObjects[i] then S.itemESPObjects[i].Visible = false end
                        end
                    end
                end
            end)
        else
            pcall(function() for _, d in pairs(S.itemESPObjects) do if d.Remove then d:Remove() end end end); S.itemESPObjects = {}
        end
    end
end)

task.spawn(function()
    while true do task.wait(0.1)
        if S.aimEnabled and S.aimHeld then
            pcall(function()
                local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2); local best, bestDist = nil, CFG.AimFOV
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LP and plr.Character then
                        local c = plr.Character; local hum = c:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 and not (CFG.AimTeamCheck and plr.Team and LP.Team and plr.Team == LP.Team) then
                            local part = c:FindFirstChild(CFG.AimPart) or c:FindFirstChild("HumanoidRootPart")
                            if part then
                                local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
                                if onScreen then
                                    local d = (Vector2.new(pos.X, pos.Y) - center).Magnitude
                                    if d < bestDist then
                                        if not CFG.AimWallCheck then best = plr; bestDist = d
                                        else
                                            local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = {LP.Character, Camera}
                                            local res = Workspace:Raycast(Camera.CFrame.Position, part.Position - Camera.CFrame.Position, params)
                                            if not res or res.Instance:IsDescendantOf(part.Parent) then best = plr; bestDist = d end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if best then
                    local part = best.Character:FindFirstChild(CFG.AimPart) or best.Character:FindFirstChild("HumanoidRootPart")
                    if part then
                        local targetCF = CFrame.lookAt(Camera.CFrame.Position, part.Position)
                        if CFG.AimSilent then Camera.CFrame = targetCF else Camera.CFrame = Camera.CFrame:Lerp(targetCF, 1 - math.pow(1 - CFG.AimSmooth, 0.1 * 60)) end
                    end
                end
            end)
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    local k = input.KeyCode
    if k == Enum.KeyCode.F then if S.flying then stopFly() else startFly() end
    elseif k == Enum.KeyCode.G then S.speedOn = not S.speedOn; applySpeed()
    elseif k == Enum.KeyCode.H then S.jumpOn = not S.jumpOn; applyJump()
    elseif k == Enum.KeyCode.I then setInfJump(not S.infJumpOn)
    elseif k == Enum.KeyCode.N then setNoclip(not S.noclipOn)
    elseif k == Enum.KeyCode.J then S.arrestOn = not S.arrestOn
    elseif k == Enum.KeyCode.Q then S.aimEnabled = not S.aimEnabled
    elseif k == CFG.AimKey then S.aimHeld = true
    end
end)

UserInputService.InputEnded:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CFG.AimKey then S.aimHeld = false end
end)

LP.CharacterAdded:Connect(function()
    task.wait(1)
    applySpeed(); applyJump()
    if S.flying then stopFly() end
    if S.noclipOn then setNoclip(true) end
end)
