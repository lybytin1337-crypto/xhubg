local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

local STATE = {
    innocent=true, sheriff=true, murderer=true,
    showDist=true, showBadge=true, showHighlight=true,
    showName=true, showHP=false, maxDist=200,
    throughWalls=true, onlyAlive=true,
}
local SA = { Enabled=false, FOV=30, OnlyMurderer=true, ShowCircle=true, CircleAlpha=80, CircleColor=Color3.fromRGB(255,255,255) }
local AG = { Enabled=false }
local SPEED = { Enabled=false, Value=16 }
local MENU_COLORS = { Color3.fromRGB(192,57,43), Color3.fromRGB(41,128,185), Color3.fromRGB(39,174,96), Color3.fromRGB(211,84,0), Color3.fromRGB(142,68,173), Color3.fromRGB(22,160,133), Color3.fromRGB(136,136,136) }
local FOV_COLORS  = { Color3.fromRGB(255,255,255), Color3.fromRGB(255,221,68), Color3.fromRGB(68,255,170), Color3.fromRGB(68,170,255), Color3.fromRGB(255,68,170), Color3.fromRGB(255,136,68), Color3.fromRGB(204,68,255) }
local COLORS = { innocent=Color3.fromRGB(55,220,90), sheriff=Color3.fromRGB(60,150,255), murderer=Color3.fromRGB(255,55,55) }
local ICONS  = { innocent="👤", sheriff="⭐", murderer="🔪" }

local function getRole(player)
    if not player.Character then return nil end
    local bp=player:FindFirstChild("Backpack"); local char=player.Character
    local hasKnife=(bp and bp:FindFirstChild("Knife")) or char:FindFirstChild("Knife")
    local hasGun=(bp and bp:FindFirstChild("Gun")) or char:FindFirstChild("Gun")
    if hasKnife then return "murderer" end
    if hasGun   then return "sheriff"  end
    return "innocent"
end

local function applyHighlight(char,role)
    if char:FindFirstChild("_ESP_"..role) then return end
    local col=COLORS[role]
    local h=Instance.new("Highlight"); h.Name="_ESP_"..role; h.FillColor=col; h.OutlineColor=col
    h.FillTransparency=0.5; h.OutlineTransparency=0; h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
    h.Adornee=char; h.Parent=char
end

-- Обновляем цвет всех уже существующих подсветок
local function refreshHighlightColors()
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character; if not char then continue end
        local role = getRole(player); if not role then continue end
        local hl = char:FindFirstChild("_ESP_"..role)
        if hl then
            hl.FillColor    = COLORS[role]
            hl.OutlineColor = COLORS[role]
        end
    end
end

-- Бейдж: создаём один раз, обновляем каждый кадр
local function applyBillboard(char, player, role)
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root or root:FindFirstChild("_ESP_BB") then return end
    local col = COLORS[role]

    local bb = Instance.new("BillboardGui")
    bb.Name = "_ESP_BB"; bb.Adornee = root; bb.AlwaysOnTop = true
    bb.StudsOffset = Vector3.new(0, 3.2, 0)
    bb.Size = UDim2.new(0, 130, 0, 36)
    bb.ResetOnSpawn = false; bb.Parent = root

    local bg = Instance.new("Frame", bb)
    bg.Name = "BG"; bg.Size = UDim2.new(1,0,1,0)
    bg.BackgroundColor3 = Color3.fromRGB(8,8,14)
    bg.BackgroundTransparency = 0.3; bg.BorderSizePixel = 0
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0,5)

    local stripe = Instance.new("Frame", bg)
    stripe.Size = UDim2.new(0,3,1,0)
    stripe.BackgroundColor3 = col; stripe.BorderSizePixel = 0
    Instance.new("UICorner", stripe).CornerRadius = UDim.new(0,5)

    local nameL = Instance.new("TextLabel", bg)
    nameL.Name = "NameL"
    nameL.Size = UDim2.new(1,-10,0.55,0); nameL.Position = UDim2.new(0,8,0,0)
    nameL.BackgroundTransparency = 1
    nameL.TextColor3 = Color3.new(1,1,1); nameL.TextSize = 11
    nameL.Font = Enum.Font.GothamBold
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.TextTruncate = Enum.TextTruncate.AtEnd
    nameL.Text = player.DisplayName

    local infoL = Instance.new("TextLabel", bg)
    infoL.Name = "InfoL"
    infoL.Size = UDim2.new(1,-10,0.45,0); infoL.Position = UDim2.new(0,8,0.55,0)
    infoL.BackgroundTransparency = 1
    infoL.TextColor3 = Color3.fromRGB(180,180,180); infoL.TextSize = 10
    infoL.Font = Enum.Font.Gotham
    infoL.TextXAlignment = Enum.TextXAlignment.Left
    infoL.RichText = true; infoL.Text = ""

    -- Точка — отображается когда далеко
    local dot = Instance.new("Frame", bb)
    dot.Name = "Dot"
    dot.Size = UDim2.new(0,8,0,8); dot.AnchorPoint = Vector2.new(0.5,0.5)
    dot.Position = UDim2.new(0.5,0,0.5,0)
    dot.BackgroundColor3 = col; dot.BorderSizePixel = 0
    dot.Visible = false
    Instance.new("UICorner", dot).CornerRadius = UDim.new(0.5,0)
end

local function distColor(d)
    if d < 30  then return "#ff5f5f" end
    if d < 100 then return "#ffcc44" end
    return "#55ee88"
end

local espTimer = 0
RunService.Heartbeat:Connect(function(dt)
    espTimer += dt; if espTimer < 0.08 then return end; espTimer = 0
    local camPos = Camera.CFrame.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character; if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart"); if not root then continue end
        local role = getRole(player); if not role then continue end
        local dist = (root.Position - camPos).Magnitude

        local alive = true
        if STATE.onlyAlive then
            local hum = char:FindFirstChildOfClass("Humanoid")
            alive = hum and hum.Health > 0
        end
        local show = STATE[role] and (dist <= STATE.maxDist) and alive

        for _, r in ipairs({"innocent","sheriff","murderer"}) do
            if r ~= role then
                local old = char:FindFirstChild("_ESP_"..r); if old then old:Destroy() end
            end
        end

        local hl = char:FindFirstChild("_ESP_"..role)
        if show and STATE.showHighlight and not hl then applyHighlight(char, role)
        elseif (not show or not STATE.showHighlight) and hl then hl:Destroy() end

        local bb = root:FindFirstChild("_ESP_BB")
        if show and STATE.showBadge and not bb then
            applyBillboard(char, player, role)
            bb = root:FindFirstChild("_ESP_BB")
        elseif (not show or not STATE.showBadge) and bb then
            bb:Destroy(); bb = nil
        end

        if show and bb then
            local bg2  = bb:FindFirstChild("BG")
            local dot  = bb:FindFirstChild("Dot")
            local nameL = bg2 and bg2:FindFirstChild("NameL")
            local infoL = bg2 and bg2:FindFirstChild("InfoL")

            -- Масштаб: dist 0→50 = полный, 50→120 = уменьшаем, 120+ = только точка
            local FULL_DIST = 50   -- до этого дистанции — полный бейдж
            local DOT_DIST  = 120  -- после — только точка

            if dist <= FULL_DIST then
                -- Полный бейдж, максимальный размер
                bb.Size = UDim2.new(0, 130, 0, 36)
                bb.StudsOffset = Vector3.new(0, 3.2, 0)
                if bg2 then bg2.Visible = true end
                if dot  then dot.Visible  = false end
                if nameL then
                    nameL.Visible = STATE.showName
                    nameL.TextSize = 11
                end
                if infoL then
                    infoL.Visible = STATE.showDist
                    if STATE.showDist then
                        infoL.Text = string.format('<font color="%s">%.0f studs</font>', distColor(dist), dist)
                    end
                end

            elseif dist <= DOT_DIST then
                -- Уменьшаем пропорционально
                local t = (dist - FULL_DIST) / (DOT_DIST - FULL_DIST) -- 0→1
                local scale = 1 - t * 0.55  -- от 1.0 до 0.45
                local w = math.floor(130 * scale)
                local h = math.floor(36  * scale)
                local ts1 = math.max(7, math.floor(11 * scale))
                local ts2 = math.max(7, math.floor(10 * scale))

                bb.Size = UDim2.new(0, w, 0, h)
                bb.StudsOffset = Vector3.new(0, 3.2 * scale, 0)
                if bg2 then bg2.Visible = true end
                if dot  then dot.Visible  = false end
                if nameL then
                    nameL.Visible = STATE.showName
                    nameL.TextSize = ts1
                end
                if infoL then
                    -- На средней дистанции только число, без "studs"
                    infoL.Visible = STATE.showDist
                    if STATE.showDist then
                        infoL.Text = string.format('<font color="%s">%.0f</font>', distColor(dist), dist)
                        infoL.TextSize = ts2
                    end
                end

            else
                -- Только цветная точка
                bb.Size = UDim2.new(0, 10, 0, 10)
                bb.StudsOffset = Vector3.new(0, 3.2, 0)
                if bg2 then bg2.Visible = false end
                if dot then
                    dot.Visible = true
                    -- Размер точки тоже уменьшаем с расстоянием
                    local dotScale = math.max(0.4, 1 - (dist - DOT_DIST) / 300)
                    local dotSize  = math.floor(8 * dotScale)
                    dot.Size = UDim2.new(0, dotSize, 0, dotSize)
                end
            end
        end
    end
end)

Players.PlayerRemoving:Connect(function(p)
    if p.Character then
        for _,name in ipairs({"_ESP_innocent","_ESP_sheriff","_ESP_murderer"}) do
            local h=p.Character:FindFirstChild(name); if h then h:Destroy() end
        end
        local root=p.Character:FindFirstChild("HumanoidRootPart")
        if root then local bb=root:FindFirstChild("_ESP_BB"); if bb then bb:Destroy() end end
    end
end)

local function saInFOV(tp)
    if SA.FOV>=360 then return true end
    local cf=Camera.CFrame
    return math.acos(math.clamp(cf.LookVector:Dot((tp-cf.Position).Unit),-1,1))*(180/math.pi) <= SA.FOV/2
end
local function saFindTarget()
    local myChar=LocalPlayer.Character; if not myChar then return nil end
    local myRoot=myChar:FindFirstChild("HumanoidRootPart"); if not myRoot then return nil end
    local best,bestDist=nil,math.huge
    for _,p in ipairs(Players:GetPlayers()) do
        if p==LocalPlayer then continue end
        local char=p.Character; if not char then continue end
        local root=char:FindFirstChild("HumanoidRootPart"); if not root then continue end
        local bp=p:FindFirstChild("Backpack")
        if SA.OnlyMurderer and not ((bp and bp:FindFirstChild("Knife")) or char:FindFirstChild("Knife")) then continue end
        local dist=(root.Position-myRoot.Position).Magnitude
        if dist<bestDist and saInFOV(root.Position) then bestDist=dist; best=p end
    end
    return best
end

local saOrigCF,saActive=nil,false
UserInputService.InputBegan:Connect(function(inp,gp)
    if gp or inp.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    if not SA.Enabled or getRole(LocalPlayer)~="sheriff" then return end
    local target=saFindTarget(); if not target then return end
    local head=target.Character and target.Character:FindFirstChild("Head"); if not head then return end
    saOrigCF=Camera.CFrame; saActive=true
    Camera.CFrame=CFrame.lookAt(Camera.CFrame.Position,head.Position)
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    if saActive and saOrigCF then
        task.defer(function() Camera.CFrame=saOrigCF; saActive=false; saOrigCF=nil end)
    end
end)

local fovGui=Instance.new("ScreenGui"); fovGui.Name="FOVCircle"; fovGui.ResetOnSpawn=false
fovGui.DisplayOrder=998; fovGui.IgnoreGuiInset=true
pcall(function() fovGui.Parent=game:GetService("CoreGui") end)
if not fovGui.Parent then fovGui.Parent=LocalPlayer:WaitForChild("PlayerGui") end
local fovRing=Instance.new("Frame",fovGui); fovRing.AnchorPoint=Vector2.new(0.5,0.5)
fovRing.BackgroundTransparency=1; fovRing.BorderSizePixel=0; fovRing.Visible=false
Instance.new("UICorner",fovRing).CornerRadius=UDim.new(0.5,0)
local fovOutline=Instance.new("UIStroke",fovRing); fovOutline.Color=SA.CircleColor; fovOutline.Thickness=1.5
RunService.Heartbeat:Connect(function()
    -- Круг показывается ВСЕГДА когда SA.ShowCircle = true (не только при SA.Enabled)
    if not SA.ShowCircle then fovRing.Visible=false; return end
    fovRing.Visible=true
    local vp=Camera.ViewportSize
    local r=math.clamp(SA.FOV*(vp.Y/Camera.FieldOfView),1,math.max(vp.X,vp.Y)*2)
    fovRing.Position=UDim2.new(0,vp.X/2,0,vp.Y/2); fovRing.Size=UDim2.new(0,r*2,0,r*2)
    -- Зелёный если цель найдена и SA включён, иначе выбранный цвет
    fovOutline.Color = (SA.Enabled and saFindTarget()) and Color3.fromRGB(80,255,80) or SA.CircleColor
    fovOutline.Transparency=1-(SA.CircleAlpha/100)
end)

local agRunning=false
local function findDroppedGun()
    for _,obj in ipairs(workspace:GetDescendants()) do
        if (obj.Name=="Gun" or obj.Name=="gun") and (obj:IsA("Tool") or obj:IsA("Model")) and not obj:IsDescendantOf(LocalPlayer) then
            local eq=false
            for _,p in ipairs(Players:GetPlayers()) do
                if p.Character and obj:IsDescendantOf(p.Character) then eq=true;break end
                if p:FindFirstChild("Backpack") and obj:IsDescendantOf(p.Backpack) then eq=true;break end
            end
            if not eq then
                local root=obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
                if root then return obj,root.Position end
            end
        end
    end
    return nil,nil
end
local function doAutoGunPickup()
    if agRunning then return end; agRunning=true
    local myChar=LocalPlayer.Character; if not myChar then agRunning=false;return end
    local myRoot=myChar:FindFirstChild("HumanoidRootPart"); if not myRoot then agRunning=false;return end
    local origCF=myRoot.CFrame; local gun,gunPos=nil,nil; local waited=0
    repeat task.wait(0.1); waited+=0.1; gun,gunPos=findDroppedGun() until gun or waited>=5
    if not gun then agRunning=false;return end
    myRoot.CFrame=CFrame.new(gunPos+Vector3.new(0,3,0)); task.wait(0.35)
    myRoot.CFrame=origCF; agRunning=false
end
local function watchDeaths()
    for _,p in ipairs(Players:GetPlayers()) do
        if p==LocalPlayer then continue end
        local function hookChar(char)
            local hum=char:WaitForChild("Humanoid",5); if not hum then return end
            hum.Died:Connect(function() if AG.Enabled then task.wait(0.2);doAutoGunPickup() end end)
        end
        if p.Character then hookChar(p.Character) end
        p.CharacterAdded:Connect(hookChar)
    end
end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function(char)
        local hum=char:WaitForChild("Humanoid",5); if not hum then return end
        hum.Died:Connect(function() if AG.Enabled then task.wait(0.2);doAutoGunPickup() end end)
    end)
end)
watchDeaths()

local speedConn=nil
local function applySpeed()
    if speedConn then speedConn:Disconnect();speedConn=nil end
    if not SPEED.Enabled then return end
    speedConn=RunService.Heartbeat:Connect(function()
        local char=LocalPlayer.Character; if not char then return end
        local hum=char:FindFirstChildOfClass("Humanoid"); if hum then hum.WalkSpeed=SPEED.Value end
    end)
end
local function resetSpeed()
    if speedConn then speedConn:Disconnect();speedConn=nil end
    local char=LocalPlayer.Character
    if char then local hum=char:FindFirstChildOfClass("Humanoid"); if hum then hum.WalkSpeed=16 end end
end

local HS=game:GetService("HttpService")
local function getAllCfgs()
    local ok,data=pcall(function() return HS:JSONDecode(readfile("mm2_cfgs.json")) end)
    if ok and type(data)=="table" then return data end; return {}
end
local function saveAllCfgs(t)
    pcall(function() writefile("mm2_cfgs.json",HS:JSONEncode(t)) end)
end
local function getFullState()
    return {
        STATE={innocent=STATE.innocent,sheriff=STATE.sheriff,murderer=STATE.murderer,
               showDist=STATE.showDist,showBadge=STATE.showBadge,showHighlight=STATE.showHighlight,
               showName=STATE.showName,showHP=STATE.showHP,maxDist=STATE.maxDist,
               throughWalls=STATE.throughWalls,onlyAlive=STATE.onlyAlive},
        SA={Enabled=SA.Enabled,FOV=SA.FOV,OnlyMurderer=SA.OnlyMurderer,ShowCircle=SA.ShowCircle,CircleAlpha=SA.CircleAlpha},
        AG={Enabled=AG.Enabled},
        SPEED={Enabled=SPEED.Enabled,Value=SPEED.Value},
    }
end

local ScreenGui=Instance.new("ScreenGui"); ScreenGui.Name="MM2Menu"; ScreenGui.ResetOnSpawn=false
ScreenGui.DisplayOrder=999; ScreenGui.IgnoreGuiInset=true
pcall(function() ScreenGui.Parent=game:GetService("CoreGui") end)
if not ScreenGui.Parent then ScreenGui.Parent=LocalPlayer:WaitForChild("PlayerGui") end

local accentColor=MENU_COLORS[1]
local accentColor2=Color3.fromRGB(231,76,60)
local uiAccentRefs = {}

local function setAccent(c)
    accentColor=c
    local r=math.min(1,c.R+0.15); local g=math.min(1,c.G+0.08); local b=math.min(1,c.B+0.08)
    accentColor2=Color3.new(r,g,b)
    for _,o in ipairs(uiAccentRefs) do
        pcall(function()
            if     o.t=="fill"   then o.r.BackgroundColor3=accentColor
            elseif o.t=="knob"   then o.r.BackgroundColor3=accentColor2
            elseif o.t=="chkbg"  then if o.getVal() then o.box.BackgroundColor3=accentColor end
            elseif o.t=="chkst"  then if o.getVal() then o.stroke.Color=accentColor2 end
            elseif o.t=="sidebg" then if o.getActive() then o.r.BackgroundColor3=Color3.fromRGB(42,24,24) end
            elseif o.t=="sidetx" then if o.getActive() then o.r.TextColor3=accentColor2 end
            elseif o.t=="ulbar"  then if o.getActive() then o.r.BackgroundColor3=accentColor end
            elseif o.t=="tabul"  then if o.getActive() then o.r.BackgroundColor3=accentColor end
            end
        end)
    end
end
setAccent(MENU_COLORS[1])

local SIZES={S=420,M=620,L=800,XL=980}
local isMobile=(UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
local currentSize=isMobile and "S" or "M"
local WIN_W=SIZES[currentSize]
local WIN_H=390
local win=Instance.new("Frame",ScreenGui); win.Name="Window"
win.Size=UDim2.new(0,WIN_W,0,WIN_H); win.Position=UDim2.new(0,20,0,isMobile and 200 or 80)
win.BackgroundColor3=Color3.fromRGB(30,30,30); win.BorderSizePixel=0
Instance.new("UICorner",win).CornerRadius=UDim.new(0,6)
local winStroke=Instance.new("UIStroke",win); winStroke.Color=Color3.fromRGB(42,42,42); winStroke.Thickness=1

local sidebar=Instance.new("Frame",win); sidebar.Size=UDim2.new(0,44,1,0)
sidebar.BackgroundColor3=Color3.fromRGB(24,24,24); sidebar.BorderSizePixel=0; sidebar.ZIndex=15
Instance.new("UICorner",sidebar).CornerRadius=UDim.new(0,6)
local sbFill=Instance.new("Frame",sidebar); sbFill.Size=UDim2.new(0.5,0,1,0); sbFill.Position=UDim2.new(0.5,0,0,0)
sbFill.BackgroundColor3=Color3.fromRGB(24,24,24); sbFill.BorderSizePixel=0
local sbRight=Instance.new("Frame",sidebar); sbRight.Size=UDim2.new(0,1,1,0); sbRight.Position=UDim2.new(1,-1,0,0)
sbRight.BackgroundColor3=Color3.fromRGB(42,42,42); sbRight.BorderSizePixel=0

local mainArea=Instance.new("Frame",win); mainArea.Position=UDim2.new(0,45,0,0)
mainArea.Size=UDim2.new(1,-45,1,0); mainArea.BackgroundTransparency=1; mainArea.BorderSizePixel=0

local sideIcons={}
local function makeSideIcon(text,posY)
    local btn=Instance.new("TextButton",sidebar)
    btn.Size=UDim2.new(0,32,0,32); btn.Position=UDim2.new(0.5,-16,0,posY)
    btn.BackgroundTransparency=1; btn.BorderSizePixel=0
    btn.Text=text; btn.TextSize=16; btn.Font=Enum.Font.GothamBold
    btn.TextColor3=Color3.fromRGB(85,85,85); btn.ZIndex=20
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,5)
    return btn
end
local aimIcon=makeSideIcon("🎯",10); local espIcon=makeSideIcon("👁",52)
local miscIcon=makeSideIcon("⚙",94)
local sepLine=Instance.new("Frame",sidebar); sepLine.Size=UDim2.new(0,24,0,1); sepLine.Position=UDim2.new(0.5,-12,0,136)
sepLine.BackgroundColor3=Color3.fromRGB(42,42,42); sepLine.BorderSizePixel=0
local cfgIcon=makeSideIcon("💾",144)

local function setIconActive(icon,active)
    icon.TextColor3=active and accentColor2 or Color3.fromRGB(85,85,85)
    icon.BackgroundTransparency=active and 0 or 1
    icon.BackgroundColor3=Color3.fromRGB(42,24,24)
end

local topbars={}; local pages={}
local currentTab="aim"; local currentSubs={aim="silent",esp="roles",misc="misc",cfg="cfg"}

local function showPage(tab,sub)
    for _,p in pairs(pages) do p.Visible=false end
    local key=tab.."_"..sub; if pages[key] then pages[key].Visible=true end
end

local function switchTab(tab)
    currentTab=tab
    for t,bar in pairs(topbars) do bar.Visible=(t==tab) end
    showPage(tab,currentSubs[tab] or "")
    setIconActive(aimIcon,tab=="aim"); setIconActive(espIcon,tab=="esp")
    setIconActive(miscIcon,tab=="misc"); setIconActive(cfgIcon,tab=="cfg")
end

local function switchSub(tab,sub)
    currentSubs[tab]=sub; showPage(tab,sub)
    local bar=topbars[tab]; if not bar then return end
    for _,ch in ipairs(bar:GetChildren()) do
        if ch:IsA("TextButton") then
            local active=ch:GetAttribute("sub")==sub
            ch.TextColor3=active and Color3.fromRGB(238,238,238) or Color3.fromRGB(85,85,85)
            local ul=ch:FindFirstChild("UL"); if ul then ul.Visible=active; ul.BackgroundColor3=accentColor end
        end
    end
end

local function addTopbar(tab,subs)
    local bar=Instance.new("Frame",mainArea); bar.Size=UDim2.new(1,0,0,36)
    bar.BackgroundColor3=Color3.fromRGB(30,30,30); bar.BorderSizePixel=0; bar.ZIndex=10; bar.Visible=(tab==currentTab)
    local bord=Instance.new("Frame",bar); bord.Size=UDim2.new(1,0,0,1); bord.Position=UDim2.new(0,0,1,-1)
    bord.BackgroundColor3=Color3.fromRGB(42,42,42); bord.BorderSizePixel=0
    topbars[tab]=bar; local x=0
    for _,sub in ipairs(subs) do
        local btn=Instance.new("TextButton",bar); btn.Size=UDim2.new(0,90,1,0); btn.Position=UDim2.new(0,x,0,0)
        btn.BackgroundTransparency=1; btn.BorderSizePixel=0; btn.Text=sub[1]; btn.TextSize=12; btn.Font=Enum.Font.GothamBold
        local isActive=(currentSubs[tab]==sub[2])
        btn.TextColor3=isActive and Color3.fromRGB(238,238,238) or Color3.fromRGB(85,85,85)
        btn:SetAttribute("sub",sub[2])
        local ul=Instance.new("Frame",btn); ul.Name="UL"; ul.Size=UDim2.new(1,0,0,2); ul.Position=UDim2.new(0,0,1,-2)
        ul.BackgroundColor3=accentColor; ul.BorderSizePixel=0; ul.Visible=isActive
        btn.Activated:Connect(function() switchSub(tab,sub[2]) end)
        x+=90
    end
end

local function makeCols(parent)
    local frame=Instance.new("Frame",parent); frame.Position=UDim2.new(0,0,0,36)
    frame.Size=UDim2.new(1,0,1,-36); frame.BackgroundTransparency=1; frame.BorderSizePixel=0; frame.ZIndex=10
    local left=Instance.new("ScrollingFrame",frame); left.Size=UDim2.new(0.5,-1,1,0)
    left.BackgroundTransparency=1; left.BorderSizePixel=0; left.ScrollBarThickness=3
    left.ScrollBarImageColor3=Color3.fromRGB(60,60,60); left.CanvasSize=UDim2.new(0,0,0,0); left.AutomaticCanvasSize=Enum.AutomaticSize.Y
    local lpad=Instance.new("UIPadding",left); lpad.PaddingLeft=UDim.new(0,12); lpad.PaddingRight=UDim.new(0,12)
    lpad.PaddingTop=UDim.new(0,10); lpad.PaddingBottom=UDim.new(0,10)
    local llay=Instance.new("UIListLayout",left); llay.Padding=UDim.new(0,0)
    local div=Instance.new("Frame",frame); div.Size=UDim2.new(0,1,1,0); div.Position=UDim2.new(0.5,-0.5,0,0)
    div.BackgroundColor3=Color3.fromRGB(42,42,42); div.BorderSizePixel=0
    local right=Instance.new("ScrollingFrame",frame); right.Size=UDim2.new(0.5,-1,1,0); right.Position=UDim2.new(0.5,1,0,0)
    right.BackgroundTransparency=1; right.BorderSizePixel=0; right.ScrollBarThickness=3
    right.ScrollBarImageColor3=Color3.fromRGB(60,60,60); right.CanvasSize=UDim2.new(0,0,0,0); right.AutomaticCanvasSize=Enum.AutomaticSize.Y
    local rpad=Instance.new("UIPadding",right); rpad.PaddingLeft=UDim.new(0,12); rpad.PaddingRight=UDim.new(0,12)
    rpad.PaddingTop=UDim.new(0,10); rpad.PaddingBottom=UDim.new(0,10)
    Instance.new("UIListLayout",right).Padding=UDim.new(0,0)
    return frame,left,right
end

local function addPage(tab,sub)
    local frame,left,right=makeCols(mainArea)
    frame.Visible=(tab==currentTab and currentSubs[tab]==sub)
    pages[tab.."_"..sub]=frame; return left,right
end

local function makeColTitle(parent,text,order)
    local lbl=Instance.new("TextLabel",parent); lbl.Size=UDim2.new(1,0,0,28)
    lbl.BackgroundTransparency=1; lbl.Text=string.upper(text); lbl.TextSize=10; lbl.Font=Enum.Font.GothamBold
    lbl.TextColor3=Color3.fromRGB(100,100,100); lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.LayoutOrder=order or 0
    local bord=Instance.new("Frame",lbl); bord.Size=UDim2.new(1,0,0,1); bord.Position=UDim2.new(0,0,1,-1)
    bord.BackgroundColor3=Color3.fromRGB(42,42,42); bord.BorderSizePixel=0
end

local function makeRow(parent,order)
    local row=Instance.new("Frame",parent); row.Size=UDim2.new(1,0,0,30)
    row.BackgroundTransparency=1; row.BorderSizePixel=0; row.LayoutOrder=order
    local bord=Instance.new("Frame",row); bord.Size=UDim2.new(1,0,0,1); bord.Position=UDim2.new(0,0,1,-1)
    bord.BackgroundColor3=Color3.fromRGB(38,38,38); bord.BorderSizePixel=0
    return row
end

local function makeLabel(parent,text)
    local lbl=Instance.new("TextLabel",parent); lbl.Size=UDim2.new(1,-36,1,0)
    lbl.BackgroundTransparency=1; lbl.Text=text; lbl.TextSize=12; lbl.Font=Enum.Font.Gotham
    lbl.TextColor3=Color3.fromRGB(170,170,170); lbl.TextXAlignment=Enum.TextXAlignment.Left
    return lbl
end

local allChecks={}; local allSliders={}

local function makeCheckbox(parent,initVal,onChange)
    local box=Instance.new("TextButton",parent)
    box.Size=UDim2.new(0,16,0,16); box.Position=UDim2.new(1,-16,0.5,-8)
    box.BackgroundColor3=Color3.fromRGB(37,37,37); box.BorderSizePixel=0; box.Text=""
    Instance.new("UICorner",box).CornerRadius=UDim.new(0,3)
    local stroke=Instance.new("UIStroke",box); stroke.Color=Color3.fromRGB(68,68,68); stroke.Thickness=1
    local check=Instance.new("TextLabel",box); check.Size=UDim2.new(1,0,1,0)
    check.BackgroundTransparency=1; check.Text="✓"; check.TextSize=10; check.Font=Enum.Font.GothamBold
    check.TextColor3=Color3.new(1,1,1); check.Visible=initVal
    local val=initVal
    local function apply(v)
        val=v; check.Visible=v
        if v then box.BackgroundColor3=accentColor; stroke.Color=accentColor2
        else box.BackgroundColor3=Color3.fromRGB(37,37,37); stroke.Color=Color3.fromRGB(68,68,68) end
        onChange(v)
    end
    table.insert(uiAccentRefs, {t="chkbg",  r=box,    box=box, stroke=stroke, getVal=function() return val end})
    table.insert(uiAccentRefs, {t="chkst",  r=stroke, box=box, stroke=stroke, getVal=function() return val end})
    apply(initVal)
    box.Activated:Connect(function() apply(not val) end)
    return box, apply
end

local function makeSlider(parent,label,initVal,minV,maxV,suffix,order,onChange)
    local wrap=Instance.new("Frame",parent); wrap.Size=UDim2.new(1,0,0,46)
    wrap.BackgroundTransparency=1; wrap.BorderSizePixel=0; wrap.LayoutOrder=order
    local bord=Instance.new("Frame",wrap); bord.Size=UDim2.new(1,0,0,1); bord.Position=UDim2.new(0,0,1,-1)
    bord.BackgroundColor3=Color3.fromRGB(38,38,38); bord.BorderSizePixel=0
    local top=Instance.new("Frame",wrap); top.Size=UDim2.new(1,0,0,22); top.BackgroundTransparency=1; top.BorderSizePixel=0
    local lbl=Instance.new("TextLabel",top); lbl.Size=UDim2.new(0.7,0,1,0); lbl.BackgroundTransparency=1
    lbl.Text=label; lbl.TextSize=12; lbl.Font=Enum.Font.Gotham; lbl.TextColor3=Color3.fromRGB(170,170,170); lbl.TextXAlignment=Enum.TextXAlignment.Left
    local valLbl=Instance.new("TextLabel",top); valLbl.Size=UDim2.new(0.3,0,1,0); valLbl.Position=UDim2.new(0.7,0,0,0)
    valLbl.BackgroundTransparency=1; valLbl.Text=tostring(initVal)..suffix; valLbl.TextSize=12; valLbl.Font=Enum.Font.Code
    valLbl.TextColor3=Color3.fromRGB(204,204,204); valLbl.TextXAlignment=Enum.TextXAlignment.Right
    local track=Instance.new("Frame",wrap); track.Size=UDim2.new(1,0,0,3); track.Position=UDim2.new(0,0,0,30)
    track.BackgroundColor3=Color3.fromRGB(51,51,51); track.BorderSizePixel=0
    Instance.new("UICorner",track).CornerRadius=UDim.new(0.5,0)
    local fill=Instance.new("Frame",track); fill.Size=UDim2.new((initVal-minV)/(maxV-minV),0,1,0)
    fill.BackgroundColor3=accentColor; fill.BorderSizePixel=0
    Instance.new("UICorner",fill).CornerRadius=UDim.new(0.5,0)
    table.insert(uiAccentRefs, {t="fill", r=fill})
    local knob=Instance.new("Frame",track); knob.Size=UDim2.new(0,11,0,11); knob.AnchorPoint=Vector2.new(0.5,0.5)
    knob.Position=UDim2.new((initVal-minV)/(maxV-minV),0,0.5,0); knob.BackgroundColor3=accentColor2; knob.BorderSizePixel=0
    Instance.new("UICorner",knob).CornerRadius=UDim.new(0.5,0)
    table.insert(uiAccentRefs, {t="knob", r=knob})
    local ks=Instance.new("UIStroke",knob); ks.Color=Color3.new(1,1,1); ks.Thickness=1.5
    local dragging=false
    local function updateSlider(inputX)
        local abs=track.AbsolutePosition; local sz=track.AbsoluteSize
        local t=math.clamp((inputX-abs.X)/sz.X,0,1)
        local v=math.floor(minV+t*(maxV-minV))
        fill.Size=UDim2.new(t,0,1,0); knob.Position=UDim2.new(t,0,0.5,0)
        valLbl.Text=tostring(v)..suffix; onChange(v)
    end
    local dragBtn=Instance.new("TextButton",wrap); dragBtn.Size=UDim2.new(1,0,1,0)
    dragBtn.BackgroundTransparency=1; dragBtn.Text=""; dragBtn.ZIndex=5
    dragBtn.MouseButton1Down:Connect(function(x,_) dragging=true; updateSlider(x) end)
    UserInputService.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch then
            updateSlider(inp.Position.X) end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)
    return wrap,fill,knob,valLbl
end

local function setSliderVal(id,v)
    local s=allSliders[id]; if not s then return end
    local t=math.clamp((v-s.minV)/(s.maxV-s.minV),0,1)
    s.fill.Size=UDim2.new(t,0,1,0); s.knob.Position=UDim2.new(t,0,0.5,0)
    s.valLbl.Text=tostring(v)..s.suffix; s.onChange(v)
end

local function regSlider(id,fill,knob,valLbl,minV,maxV,suffix,onChange)
    allSliders[id]={fill=fill,knob=knob,valLbl=valLbl,minV=minV,maxV=maxV,suffix=suffix,onChange=onChange}
end

local function makeColorPicker(parent,colors,current,order,onChange)
    local wrap=Instance.new("Frame",parent); wrap.Size=UDim2.new(1,0,0,36)
    wrap.BackgroundTransparency=1; wrap.BorderSizePixel=0; wrap.LayoutOrder=order
    local layout=Instance.new("UIListLayout",wrap); layout.FillDirection=Enum.FillDirection.Horizontal
    layout.Padding=UDim.new(0,6); layout.VerticalAlignment=Enum.VerticalAlignment.Center
    local swatches={}
    for i,c in ipairs(colors) do
        local sw=Instance.new("TextButton",wrap); sw.Size=UDim2.new(0,20,0,20)
        sw.BackgroundColor3=c; sw.BorderSizePixel=0; sw.Text=""
        Instance.new("UICorner",sw).CornerRadius=UDim.new(0,3)
        local st=Instance.new("UIStroke",sw)
        st.Color=(c==current) and Color3.new(1,1,1) or Color3.fromRGB(60,60,60)
        st.Thickness=(c==current) and 2 or 1
        swatches[i]={sw=sw,st=st,c=c}
        sw.Activated:Connect(function()
            for _,s in ipairs(swatches) do s.st.Color=Color3.fromRGB(60,60,60); s.st.Thickness=1 end
            st.Color=Color3.new(1,1,1); st.Thickness=2; onChange(c)
        end)
    end
    return wrap
end

addTopbar("aim",{{"Silent Aim","silent"},{"FOV","fov"}})
addTopbar("esp",{{"Роли","roles"},{"Инфо","info"}})
addTopbar("misc",{{"Misc","misc"}})
addTopbar("cfg",{{"Config","cfg"}})

do
    local left,right=addPage("aim","silent")
    makeColTitle(left,"Aim Settings",0)
    local r1=makeRow(left,1); makeLabel(r1,"Silent Aim")
    local _,setChk=makeCheckbox(r1,SA.Enabled,function(v) SA.Enabled=v end); allChecks.sa_enabled=setChk
    local r2=makeRow(left,2); makeLabel(r2,"Only Murderer")
    local _,setOM=makeCheckbox(r2,SA.OnlyMurderer,function(v) SA.OnlyMurderer=v end); allChecks.sa_only_murderer=setOM
    local _,f1,k1,vl1=makeSlider(left,"FOV",SA.FOV,1,360,"°",3,function(v) SA.FOV=v end)
    regSlider("sa_fov",f1,k1,vl1,1,360,"°",function(v) SA.FOV=v end)
    local resetRow=makeRow(left,4)
    local rb=Instance.new("TextButton",resetRow); rb.Size=UDim2.new(1,0,0,22); rb.Position=UDim2.new(0,0,0.5,-11)
    rb.BackgroundColor3=Color3.fromRGB(42,42,42); rb.BorderSizePixel=0; rb.Text="Reset FOV"
    rb.TextSize=12; rb.Font=Enum.Font.Gotham; rb.TextColor3=Color3.fromRGB(204,204,204)
    Instance.new("UICorner",rb).CornerRadius=UDim.new(0,3)
    rb.Activated:Connect(function() SA.FOV=30; setSliderVal("sa_fov",30); setSliderVal("sa_fov2",30) end)
    local r3=makeRow(left,5); makeLabel(r3,"FOV Circle")
    local _,setFC=makeCheckbox(r3,SA.ShowCircle,function(v) SA.ShowCircle=v end); allChecks.sa_show_circle=setFC
    makeColTitle(right,"Target Priority",0)
    local rH=makeRow(right,1); makeLabel(rH,"Голова"); makeCheckbox(rH,true,function() end)
    local rT=makeRow(right,2); makeLabel(rT,"Торс"); makeCheckbox(rT,false,function() end)
    local rN=makeRow(right,3); makeLabel(rN,"Ближайший"); makeCheckbox(rN,true,function() end)
    local rF=makeRow(right,4); makeLabel(rF,"В FOV"); makeCheckbox(rF,true,function() end)
end

do
    local left,right=addPage("aim","fov")
    makeColTitle(left,"FOV Visual",0)
    local r1=makeRow(left,1); makeLabel(r1,"Показать круг")
    local _,setFC2=makeCheckbox(r1,SA.ShowCircle,function(v) SA.ShowCircle=v end); allChecks.sa_show_circle2=setFC2
    local _,f2,k2,vl2=makeSlider(left,"Размер",SA.FOV,1,360,"°",2,function(v) SA.FOV=v end)
    regSlider("sa_fov2",f2,k2,vl2,1,360,"°",function(v) SA.FOV=v end)
    local _,f3,k3,vl3=makeSlider(left,"Прозрачность",SA.CircleAlpha,0,100,"%",3,function(v) SA.CircleAlpha=v end)
    regSlider("sa_alpha",f3,k3,vl3,0,100,"%",function(v) SA.CircleAlpha=v end)
    makeColTitle(right,"Цвет FOV Круга",0)
    local prevRow=makeRow(right,1)
    local prevCircle=Instance.new("Frame",prevRow); prevCircle.Size=UDim2.new(0,50,0,50); prevCircle.Position=UDim2.new(0.5,-25,0.5,-25)
    prevCircle.BackgroundTransparency=1; prevCircle.BorderSizePixel=0
    Instance.new("UICorner",prevCircle).CornerRadius=UDim.new(0.5,0)
    local prevStroke=Instance.new("UIStroke",prevCircle); prevStroke.Color=SA.CircleColor; prevStroke.Thickness=2
    makeColorPicker(right,FOV_COLORS,SA.CircleColor,2,function(c)
        SA.CircleColor=c; fovOutline.Color=c; prevStroke.Color=c
    end)
end

do
    local left,right=addPage("esp","roles")
    makeColTitle(left,"ESP Roles",0)
    local r1=makeRow(left,1); local l1=makeLabel(r1,"● Innocent"); l1.TextColor3=COLORS.innocent
    local _,setI=makeCheckbox(r1,STATE.innocent,function(v)
        STATE.innocent=v
        for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer and p.Character and getRole(p)=="innocent" then
            if v then applyHighlight(p.Character,"innocent") else local h=p.Character:FindFirstChild("_ESP_innocent"); if h then h:Destroy() end end
        end end
        refreshHighlightColors()
    end); allChecks.esp_innocent=setI
    local r2=makeRow(left,2); local l2=makeLabel(r2,"● Sheriff"); l2.TextColor3=COLORS.sheriff
    local _,setSh=makeCheckbox(r2,STATE.sheriff,function(v)
        STATE.sheriff=v
        for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer and p.Character and getRole(p)=="sheriff" then
            if v then applyHighlight(p.Character,"sheriff") else local h=p.Character:FindFirstChild("_ESP_sheriff"); if h then h:Destroy() end end
        end end
        refreshHighlightColors()
    end); allChecks.esp_sheriff=setSh
    local r3=makeRow(left,3); local l3=makeLabel(r3,"● Murderer"); l3.TextColor3=COLORS.murderer
    local _,setM=makeCheckbox(r3,STATE.murderer,function(v)
        STATE.murderer=v
        for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer and p.Character and getRole(p)=="murderer" then
            if v then applyHighlight(p.Character,"murderer") else local h=p.Character:FindFirstChild("_ESP_murderer"); if h then h:Destroy() end end
        end end
        refreshHighlightColors()
    end); allChecks.esp_murderer=setM
    makeColTitle(right,"ESP Options",0)
    local r4=makeRow(right,1); makeLabel(r4,"Подсветка")
    local _,setHL=makeCheckbox(r4,STATE.showHighlight,function(v) STATE.showHighlight=v end); allChecks.esp_highlight=setHL
    local r5=makeRow(right,2); makeLabel(r5,"Бейджи")
    local _,setBG=makeCheckbox(r5,STATE.showBadge,function(v) STATE.showBadge=v end); allChecks.esp_badge=setBG
    local r6=makeRow(right,3); makeLabel(r6,"Дистанция")
    local _,setD=makeCheckbox(r6,STATE.showDist,function(v) STATE.showDist=v end); allChecks.esp_dist=setD
end

do
    local left,right=addPage("esp","info")
    makeColTitle(left,"Отображение",0)
    local r1=makeRow(left,1); makeLabel(r1,"Имя игрока")
    local _,setName=makeCheckbox(r1,STATE.showName,function(v) STATE.showName=v end); allChecks.esp_name=setName
    local r2=makeRow(left,2); makeLabel(r2,"HP бар")
    local _,setHP=makeCheckbox(r2,STATE.showHP,function(v) STATE.showHP=v end); allChecks.esp_hp=setHP
    local _,fd,kd,vld=makeSlider(left,"Макс. дистанция",STATE.maxDist,10,500,"",3,function(v) STATE.maxDist=v end)
    regSlider("esp_maxdist",fd,kd,vld,10,500,"",function(v) STATE.maxDist=v end)
    makeColTitle(right,"Фильтры",0)
    local r3=makeRow(right,1); makeLabel(r3,"Через стены")
    local _,setTW=makeCheckbox(r3,STATE.throughWalls,function(v) STATE.throughWalls=v end); allChecks.esp_walls=setTW
    local r4=makeRow(right,2); makeLabel(r4,"Только живые")
    local _,setOA=makeCheckbox(r4,STATE.onlyAlive,function(v) STATE.onlyAlive=v end); allChecks.esp_alive=setOA
end

do
    local left,right=addPage("misc","misc")
    makeColTitle(left,"Misc Settings",0)
    local r1=makeRow(left,1); makeLabel(r1,"Auto Gun Pickup")
    local _,setAG=makeCheckbox(r1,AG.Enabled,function(v) AG.Enabled=v end); allChecks.ag_enabled=setAG
    local r2=makeRow(left,2); makeLabel(r2,"Speedhack")
    local _,setSP=makeCheckbox(r2,SPEED.Enabled,function(v) SPEED.Enabled=v; if v then applySpeed() else resetSpeed() end end)
    allChecks.speed_enabled=setSP
    local _,fs,ks,vls=makeSlider(left,"Speed",SPEED.Value,8,100,"",3,function(v)
        SPEED.Value=v
        if SPEED.Enabled then local char=LocalPlayer.Character; if char then local hum=char:FindFirstChildOfClass("Humanoid"); if hum then hum.WalkSpeed=v end end end
    end)
    regSlider("speed_val",fs,ks,vls,8,100,"",function(v) SPEED.Value=v end)
    makeColTitle(right,"Accent Color",0)
    makeColorPicker(right,MENU_COLORS,accentColor,1,function(c) setAccent(c) end)

    -- Размер окна
    local szTitle=Instance.new("TextLabel",right); szTitle.Size=UDim2.new(1,0,0,16)
    szTitle.BackgroundTransparency=1; szTitle.Text="РАЗМЕР ОКНА"; szTitle.TextSize=9
    szTitle.Font=Enum.Font.GothamBold; szTitle.TextColor3=Color3.fromRGB(90,90,90)
    szTitle.TextXAlignment=Enum.TextXAlignment.Left; szTitle.LayoutOrder=2

    local szRow=Instance.new("Frame",right); szRow.Size=UDim2.new(1,0,0,28)
    szRow.BackgroundTransparency=1; szRow.LayoutOrder=3
    local szLayout=Instance.new("UIListLayout",szRow)
    szLayout.FillDirection=Enum.FillDirection.Horizontal; szLayout.Padding=UDim.new(0,4)
    szLayout.VerticalAlignment=Enum.VerticalAlignment.Center

    local SIZES={S=500,M=700,L=860,XL=1020}
    local szBtns={}
    local curSize="M"
    for _,sz in ipairs({"S","M","L","XL"}) do
        local b=Instance.new("TextButton",szRow); b.Size=UDim2.new(0,34,0,24)
        b.Text=sz; b.TextSize=11; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0
        b.BackgroundColor3=sz=="M" and accentColor or Color3.fromRGB(42,42,42)
        b.TextColor3=sz=="M" and Color3.new(1,1,1) or Color3.fromRGB(160,160,160)
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,3)
        szBtns[sz]=b
        local capSz=sz
        b.Activated:Connect(function()
            curSize=capSz
            local w=SIZES[capSz]
            win.Size=UDim2.new(0,w,0,390)
            win.Position=UDim2.new(0.5,-w/2,0.3,0)
            for s,btn in pairs(szBtns) do
                btn.BackgroundColor3=s==capSz and accentColor or Color3.fromRGB(42,42,42)
                btn.TextColor3=s==capSz and Color3.new(1,1,1) or Color3.fromRGB(160,160,160)
            end
        end)
        -- обновляем цвет кнопки при смене акцента
        regAccent("bg",{BackgroundColor3=accentColor,__set=function(c)
            if curSize==capSz then b.BackgroundColor3=c end
        end})
    end

    makeColTitle(right,"Размер окна",2)
    local sizeRow=Instance.new("Frame",right); sizeRow.Size=UDim2.new(1,0,0,28)
    sizeRow.BackgroundTransparency=1; sizeRow.BorderSizePixel=0; sizeRow.LayoutOrder=3
    local szLayout=Instance.new("UIListLayout",sizeRow)
    szLayout.FillDirection=Enum.FillDirection.Horizontal; szLayout.Padding=UDim.new(0,4)
    local sizeBtns={}
    for _,sz in ipairs({"S","M","L","XL"}) do
        local sbtn=Instance.new("TextButton",sizeRow); sbtn.Size=UDim2.new(0,32,1,0)
        sbtn.BackgroundColor3=sz==currentSize and accentColor or Color3.fromRGB(42,42,42)
        sbtn.BorderSizePixel=0; sbtn.Text=sz; sbtn.TextSize=11; sbtn.Font=Enum.Font.GothamBold
        sbtn.TextColor3=sz==currentSize and Color3.new(1,1,1) or Color3.fromRGB(160,160,160)
        Instance.new("UICorner",sbtn).CornerRadius=UDim.new(0,3)
        sizeBtns[sz]=sbtn
        local capSz=sz
        sbtn.Activated:Connect(function()
            currentSize=capSz
            local w=SIZES[capSz]
            win.Size=UDim2.new(0,w,0,WIN_H)
            win.Position=UDim2.new(0.5,-w/2,0.3,0)
            for s,b in pairs(sizeBtns) do
                b.BackgroundColor3=s==capSz and accentColor or Color3.fromRGB(42,42,42)
                b.TextColor3=s==capSz and Color3.new(1,1,1) or Color3.fromRGB(160,160,160)
            end
        end)
    end
end

do
    local left,right=addPage("cfg","cfg")
    makeColTitle(left,"Конфиги",0)
    local cfgInput=Instance.new("TextBox",left); cfgInput.Size=UDim2.new(1,0,0,26)
    cfgInput.BackgroundColor3=Color3.fromRGB(37,37,37); cfgInput.BorderSizePixel=0; cfgInput.LayoutOrder=1
    cfgInput.Text=""; cfgInput.PlaceholderText="Название конфига..."
    cfgInput.TextSize=12; cfgInput.Font=Enum.Font.Gotham
    cfgInput.TextColor3=Color3.fromRGB(204,204,204); cfgInput.PlaceholderColor3=Color3.fromRGB(68,68,68)
    Instance.new("UICorner",cfgInput).CornerRadius=UDim.new(0,3)
    local inputStroke=Instance.new("UIStroke",cfgInput); inputStroke.Color=Color3.fromRGB(60,60,60); inputStroke.Thickness=1
    cfgInput.Focused:Connect(function() inputStroke.Color=accentColor end)
    cfgInput.FocusLost:Connect(function() inputStroke.Color=Color3.fromRGB(60,60,60) end)

    local msgLbl=Instance.new("TextLabel",left); msgLbl.Size=UDim2.new(1,0,0,20)
    msgLbl.BackgroundTransparency=1; msgLbl.Text=""; msgLbl.TextSize=11; msgLbl.Font=Enum.Font.Gotham
    msgLbl.TextColor3=Color3.fromRGB(51,204,102); msgLbl.TextXAlignment=Enum.TextXAlignment.Left; msgLbl.LayoutOrder=10
    local function showMsg(text,color)
        msgLbl.Text=text; msgLbl.TextColor3=color or Color3.fromRGB(51,204,102)
        task.delay(2,function() if msgLbl then msgLbl.Text="" end end)
    end

    local function makeCfgBtn(text,order,color,onClick)
        local row=makeRow(left,order)
        local btn=Instance.new("TextButton",row); btn.Size=UDim2.new(1,0,0,22); btn.Position=UDim2.new(0,0,0.5,-11)
        btn.BackgroundColor3=Color3.fromRGB(42,42,42); btn.BorderSizePixel=0; btn.Text=text
        btn.TextSize=12; btn.Font=Enum.Font.Gotham; btn.TextColor3=color or Color3.fromRGB(204,204,204)
        Instance.new("UICorner",btn).CornerRadius=UDim.new(0,3)
        btn.Activated:Connect(onClick); return btn
    end

    makeColTitle(right,"Мои Конфиги",0)
    local cfgListFrame=Instance.new("Frame",right); cfgListFrame.Size=UDim2.new(1,0,0,0)
    cfgListFrame.AutomaticSize=Enum.AutomaticSize.Y; cfgListFrame.BackgroundTransparency=1; cfgListFrame.BorderSizePixel=0; cfgListFrame.LayoutOrder=1
    local cfgListLayout=Instance.new("UIListLayout",cfgListFrame); cfgListLayout.Padding=UDim.new(0,4)
    local activeCfgName=nil

    local function applyLoadedState(s)
        if s.STATE then for k,v in pairs(s.STATE) do if STATE[k]~=nil then STATE[k]=v end end end
        if s.SA then for k,v in pairs(s.SA) do if SA[k]~=nil then SA[k]=v end end end
        if s.AG then AG.Enabled=s.AG.Enabled end
        if s.SPEED then SPEED.Enabled=s.SPEED.Enabled; SPEED.Value=s.SPEED.Value; if SPEED.Enabled then applySpeed() else resetSpeed() end end
        for id,fn in pairs(allChecks) do
            if id=="sa_enabled" then fn(SA.Enabled)
            elseif id=="sa_only_murderer" then fn(SA.OnlyMurderer)
            elseif id=="sa_show_circle" or id=="sa_show_circle2" then fn(SA.ShowCircle)
            elseif id=="esp_innocent" then fn(STATE.innocent)
            elseif id=="esp_sheriff" then fn(STATE.sheriff)
            elseif id=="esp_murderer" then fn(STATE.murderer)
            elseif id=="esp_highlight" then fn(STATE.showHighlight)
            elseif id=="esp_badge" then fn(STATE.showBadge)
            elseif id=="esp_dist" then fn(STATE.showDist)
            elseif id=="esp_name" then fn(STATE.showName)
            elseif id=="esp_hp" then fn(STATE.showHP)
            elseif id=="esp_walls" then fn(STATE.throughWalls)
            elseif id=="esp_alive" then fn(STATE.onlyAlive)
            elseif id=="ag_enabled" then fn(AG.Enabled)
            elseif id=="speed_enabled" then fn(SPEED.Enabled)
            end
        end
        setSliderVal("sa_fov",SA.FOV); setSliderVal("sa_fov2",SA.FOV)
        setSliderVal("sa_alpha",SA.CircleAlpha); setSliderVal("esp_maxdist",STATE.maxDist); setSliderVal("speed_val",SPEED.Value)
    end

    local function renderCfgList()
        for _,c in ipairs(cfgListFrame:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
        local cfgs=getAllCfgs(); local keys={}; for k in pairs(cfgs) do table.insert(keys,k) end
        if #keys==0 then
            local empty=Instance.new("TextLabel",cfgListFrame); empty.Size=UDim2.new(1,0,0,24)
            empty.BackgroundTransparency=1; empty.Text="Нет конфигов"; empty.TextSize=11; empty.Font=Enum.Font.Gotham
            empty.TextColor3=Color3.fromRGB(68,68,68); empty.TextXAlignment=Enum.TextXAlignment.Left; return
        end
        for _,name in ipairs(keys) do
            local cfg=cfgs[name]
            local item=Instance.new("Frame",cfgListFrame); item.Size=UDim2.new(1,0,0,48)
            item.BackgroundColor3=Color3.fromRGB(34,34,34); item.BorderSizePixel=0
            Instance.new("UICorner",item).CornerRadius=UDim.new(0,3)
            local itemStroke=Instance.new("UIStroke",item)
            itemStroke.Color=name==activeCfgName and accentColor or Color3.fromRGB(42,42,42); itemStroke.Thickness=1
            local nameLbl=Instance.new("TextLabel",item); nameLbl.Size=UDim2.new(1,-80,0,24); nameLbl.Position=UDim2.new(0,8,0,4)
            nameLbl.BackgroundTransparency=1; nameLbl.Text=name; nameLbl.TextSize=12; nameLbl.Font=Enum.Font.GothamBold
            nameLbl.TextColor3=name==activeCfgName and accentColor2 or Color3.fromRGB(170,170,170); nameLbl.TextXAlignment=Enum.TextXAlignment.Left
            local dateLbl=Instance.new("TextLabel",item); dateLbl.Size=UDim2.new(1,-80,0,16); dateLbl.Position=UDim2.new(0,8,0,28)
            dateLbl.BackgroundTransparency=1; dateLbl.Text=cfg.savedAt or ""; dateLbl.TextSize=10; dateLbl.Font=Enum.Font.Gotham
            dateLbl.TextColor3=Color3.fromRGB(68,68,68); dateLbl.TextXAlignment=Enum.TextXAlignment.Left
            local loadBtn=Instance.new("TextButton",item); loadBtn.Size=UDim2.new(0,36,0,20); loadBtn.Position=UDim2.new(1,-78,0.5,-10)
            loadBtn.BackgroundColor3=Color3.fromRGB(42,42,42); loadBtn.BorderSizePixel=0; loadBtn.Text="load"
            loadBtn.TextSize=10; loadBtn.Font=Enum.Font.Gotham; loadBtn.TextColor3=accentColor2
            Instance.new("UICorner",loadBtn).CornerRadius=UDim.new(0,2)
            local delBtn=Instance.new("TextButton",item); delBtn.Size=UDim2.new(0,26,0,20); delBtn.Position=UDim2.new(1,-36,0.5,-10)
            delBtn.BackgroundColor3=Color3.fromRGB(42,26,26); delBtn.BorderSizePixel=0; delBtn.Text="✕"
            delBtn.TextSize=10; delBtn.Font=Enum.Font.GothamBold; delBtn.TextColor3=Color3.fromRGB(204,68,68)
            Instance.new("UICorner",delBtn).CornerRadius=UDim.new(0,2)
            loadBtn.Activated:Connect(function()
                local all=getAllCfgs(); local s=all[name]; if not s then return end
                applyLoadedState(s); activeCfgName=name; renderCfgList(); showMsg("✓ Загружено: "..name)
            end)
            delBtn.Activated:Connect(function()
                local all=getAllCfgs(); all[name]=nil; saveAllCfgs(all)
                if activeCfgName==name then activeCfgName=nil end
                renderCfgList(); showMsg("Удалено: "..name,Color3.fromRGB(221,170,34))
            end)
        end
    end

    makeCfgBtn("Сохранить",2,nil,function()
        local name=cfgInput.Text:match("^%s*(.-)%s*$"); if name=="" then name="default" end
        local s=getFullState(); s.savedAt=os.date("%d.%m %H:%M")
        local all=getAllCfgs(); all[name]=s; saveAllCfgs(all)
        activeCfgName=name; renderCfgList(); showMsg("✓ Сохранено: "..name)
    end)
    makeCfgBtn("Сбросить всё",3,Color3.fromRGB(204,68,68),function()
        saveAllCfgs({}); activeCfgName=nil; renderCfgList(); showMsg("Сброшено",Color3.fromRGB(221,170,34))
    end)
    renderCfgList()
end

aimIcon.Activated:Connect(function()  switchTab("aim")  end)
espIcon.Activated:Connect(function()  switchTab("esp")  end)
miscIcon.Activated:Connect(function() switchTab("misc") end)
cfgIcon.Activated:Connect(function()  switchTab("cfg")  end)
switchTab("aim")

local menuVisible=true
local function setMenu(v) menuVisible=v; win.Visible=v end

UserInputService.InputBegan:Connect(function(inp,gp)
    if gp then return end
    if inp.KeyCode==Enum.KeyCode.Insert then setMenu(not menuVisible) end
end)

-- ── Крестик закрытия — поверх всего, в ScreenGui ──────
local closeBtn=Instance.new("TextButton",ScreenGui)
closeBtn.Size=UDim2.new(0,36,0,36)
closeBtn.AnchorPoint=Vector2.new(1,0)
closeBtn.BackgroundColor3=Color3.fromRGB(58,16,16)
closeBtn.BorderSizePixel=0; closeBtn.Text="✕"
closeBtn.TextSize=14; closeBtn.Font=Enum.Font.GothamBold
closeBtn.TextColor3=Color3.fromRGB(255,85,85); closeBtn.ZIndex=2000
Instance.new("UICorner",closeBtn).CornerRadius=UDim.new(0,6)
Instance.new("UIStroke",closeBtn).Color=Color3.fromRGB(120,34,34)

local function syncCloseBtnPos()
    local wx=win.AbsolutePosition.X+win.AbsoluteSize.X
    local wy=win.AbsolutePosition.Y
    closeBtn.Position=UDim2.new(0,wx,0,wy-2)
end
RunService.Heartbeat:Connect(function()
    if menuVisible then syncCloseBtnPos() end
    closeBtn.Visible=menuVisible
end)
closeBtn.Activated:Connect(function() setMenu(false) end)

-- ── Drag меню — тянуть за любое место окна (низкий ZIndex, иконки выше) ──
do
    local dragging,dragStart,startPos=false,nil,nil
    local dragZone=Instance.new("TextButton",win)
    dragZone.Size=UDim2.new(1,0,1,0); dragZone.Position=UDim2.new(0,0,0,0)
    dragZone.BackgroundTransparency=1; dragZone.Text=""; dragZone.ZIndex=2
    dragZone.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
            dragging=true; dragStart=inp.Position; startPos=win.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch then
            local d=inp.Position-dragStart
            win.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
            dragging=false
        end
    end)
end

-- ── Мобильная кнопка ☰ — перетаскиваемая ──────────────
local mob=Instance.new("TextButton",ScreenGui)
mob.Size=UDim2.new(0,52,0,52); mob.Position=UDim2.new(1,-66,1,-80)
mob.BackgroundColor3=Color3.fromRGB(20,20,35); mob.BorderSizePixel=0
mob.TextColor3=Color3.fromRGB(200,200,255)
mob.Text="☰"; mob.TextSize=24; mob.Font=Enum.Font.GothamBold; mob.ZIndex=1000
Instance.new("UICorner",mob).CornerRadius=UDim.new(0,14)
Instance.new("UIStroke",mob).Color=Color3.fromRGB(60,60,100)

local mobDrag,mobDragStart,mobStartPos=false,nil,nil
local mobMoved=false

mob.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
        mobDrag=true; mobMoved=false
        mobDragStart=inp.Position; mobStartPos=mob.AbsolutePosition
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if not mobDrag then return end
    if inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch then
        local d=inp.Position-mobDragStart
        if d.Magnitude>6 then
            mobMoved=true
            mob.Position=UDim2.new(0,mobStartPos.X+d.X,0,mobStartPos.Y+d.Y)
        end
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
        if not mobMoved then setMenu(not menuVisible) end
        mobDrag=false; mobDragStart=nil; mobMoved=false
    end
end)
RunService.Heartbeat:Connect(function() mob.Visible=not menuVisible end)
print("[MM2] ready | Insert / ☰")
