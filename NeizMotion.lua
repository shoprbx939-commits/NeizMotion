--[[ NeizMotion - glassmorphism floating overlay + cinematic motion blur ]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- Config
----------------------------------------------------------------

local ICON_ASSET_ID = "rbxassetid://132896400537590"

local DEFAULT_PILL_POSITION   = UDim2.new(0.5, 0, 0.36, 0)
local DEFAULT_WINDOW_POSITION = UDim2.new(0.5, 0, 0.28, 0)

local DEFAULT_SETTINGS = {
    blurEnabled      = true,
    blurStrength     = 18,
    blurIntensity    = 1,
    blurSensitivity  = 0.6,
    blurFadeIn       = 0.15,
    blurFadeOut      = 0.35,

    guiTransparency   = 0.03,
    glassStrength     = 0.7,
    guiScale          = 1,
    animationsEnabled = true,
    animationSpeed    = 1,
    widgetVisible     = true,
    rememberPosition  = true,
    pillPosition      = DEFAULT_PILL_POSITION,
    windowPosition    = DEFAULT_WINDOW_POSITION,

    shopSkipAnimation = false,
    shopInterval      = 5,
    shopCrate1        = false,
    shopCrate2        = false,
    shopCrate3        = false,
}

local Settings = {}
for k, v in pairs(DEFAULT_SETTINGS) do
    Settings[k] = v
end

local Palette = {
    bg      = Color3.fromRGB(11, 11, 15),
    card    = Color3.fromRGB(22, 22, 28),
    field   = Color3.fromRGB(9, 9, 12),
    accent  = Color3.fromRGB(126, 138, 255),
    text    = Color3.fromRGB(246, 246, 250),
    subtext = Color3.fromRGB(150, 150, 166),
    faint   = Color3.fromRGB(108, 108, 124),
    white   = Color3.fromRGB(255, 255, 255),
}

local PADDING    = 16
local GAP        = 10
local SIDEBAR_W  = 58
local TOPBAR_H   = 50
local NAV_BTN_H  = 46

local WIDGET_SIZE = UDim2.new(0, 130, 0, 42)

----------------------------------------------------------------
-- State + helpers
----------------------------------------------------------------

local State = { isOpen = false, activeTab = nil }
local controlRefreshers = {}

local function new(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    return inst
end

local function tween(instance, props, duration, style, direction)
    duration = duration or 0.2
    if not Settings.animationsEnabled then
        for prop, val in pairs(props) do
            instance[prop] = val
        end
        return
    end
    local speed = math.clamp(Settings.animationSpeed or 1, 0.25, 3)
    local info = TweenInfo.new(duration / speed, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
    local tw = TweenService:Create(instance, info, props)
    tw:Play()
    return tw
end

local function corner(parent, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius or 14), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
    return new("UIStroke", {
        Color = color or Palette.white,
        Thickness = thickness or 1,
        Transparency = transparency or 0.55,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function glow(parent, size, imageTransparency, color)
    return new("ImageLabel", {
        Parent = parent,
        BackgroundTransparency = 1,
        Image = "rbxassetid://5028857084",
        ImageColor3 = color or Palette.accent,
        ImageTransparency = imageTransparency or 0.86,
        Size = UDim2.new(size or 1.6, 0, size or 1.6, 0),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        ZIndex = 1,
    })
end

----------------------------------------------------------------
-- ScreenGui + responsive helpers
----------------------------------------------------------------

local screenGui = new("ScreenGui", {
    Name = "NeizMotionGui",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
    Parent = playerGui,
})

local function getScreenSize()
    local size = screenGui.AbsoluteSize
    if size.X <= 1 or size.Y <= 1 then
        local cam = workspace.CurrentCamera
        size = (cam and cam.ViewportSize) or Vector2.new(800, 600)
    end
    return size
end

local function clampToScreen(pos, size)
    local screenSize = getScreenSize()
    local halfW = size.X / 2
    local margin = 8
    local absX = pos.X.Scale * screenSize.X + pos.X.Offset
    local absY = pos.Y.Scale * screenSize.Y + pos.Y.Offset
    local maxX = math.max(halfW + margin, screenSize.X - halfW - margin)
    local maxY = math.max(margin, screenSize.Y - size.Y - margin)
    absX = math.clamp(absX, halfW + margin, maxX)
    absY = math.clamp(absY, margin, maxY)
    return UDim2.new(0, absX, 0, absY)
end

local function computeBaseWindowSize()
    local vp = getScreenSize()
    local w = math.clamp(vp.X - 32, 250, 320)
    local h = math.clamp(vp.Y - 140, 310, 392)
    return Vector2.new(w, h)
end

local function computeEffectiveWindowSize()
    local base = computeBaseWindowSize()
    return Vector2.new(base.X * Settings.guiScale, base.Y * Settings.guiScale)
end

----------------------------------------------------------------
-- Floating pill
----------------------------------------------------------------

local floatingWidget = new("CanvasGroup", {
    Name = "FloatingWidget",
    Parent = screenGui,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = Settings.pillPosition,
    Size = WIDGET_SIZE,
    BackgroundColor3 = Palette.bg,
    BackgroundTransparency = Settings.guiTransparency,
    ClipsDescendants = true,
    Active = true,
    ZIndex = 10,
})
corner(floatingWidget, 21)
stroke(floatingWidget, Palette.white, 1, 0.5)
glow(floatingWidget, 1.5, 0.88)

local widgetIcon = new("ImageLabel", {
    Name = "Icon",
    Parent = floatingWidget,
    BackgroundTransparency = 1,
    Image = ICON_ASSET_ID,
    ImageColor3 = Color3.fromRGB(255, 255, 255),
    ScaleType = Enum.ScaleType.Fit,
    Size = UDim2.new(0, 24, 0, 24),
    Position = UDim2.new(0, 11, 0.5, 0),
    AnchorPoint = Vector2.new(0, 0.5),
    ZIndex = 3,
})

local widgetLabel = new("TextLabel", {
    Name = "Label",
    Parent = floatingWidget,
    BackgroundTransparency = 1,
    Text = "NeizMotion",
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextColor3 = Palette.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 43, 0, 0),
    Size = UDim2.new(1, -53, 1, 0),
    ZIndex = 3,
})

local widgetButton = new("TextButton", {
    Name = "ClickArea",
    Parent = floatingWidget,
    BackgroundTransparency = 1,
    Text = "",
    Size = UDim2.new(1, 0, 1, 0),
    ZIndex = 5,
})

----------------------------------------------------------------
-- Backdrop
----------------------------------------------------------------

local backdrop = new("TextButton", {
    Name = "Backdrop",
    Parent = screenGui,
    BackgroundTransparency = 1,
    Text = "",
    Size = UDim2.new(1, 0, 1, 0),
    Visible = false,
    ZIndex = 15,
})

----------------------------------------------------------------
-- Main window
----------------------------------------------------------------

local mainWindow = new("CanvasGroup", {
    Name = "MainWindow",
    Parent = screenGui,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = Settings.pillPosition,
    Size = WIDGET_SIZE,
    BackgroundColor3 = Palette.bg,
    BackgroundTransparency = Settings.guiTransparency,
    ClipsDescendants = true,
    Visible = false,
    Active = true,
    ZIndex = 20,
})
corner(mainWindow, 22)
stroke(mainWindow, Palette.white, 1, 0.5)
glow(mainWindow, 1.3, 0.92)

local windowScale = new("UIScale", { Parent = mainWindow, Scale = 1 })

local topBar = new("Frame", {
    Name = "TopBar",
    Parent = mainWindow,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, TOPBAR_H),
    ZIndex = 21,
})

local topBarIcon = new("ImageLabel", {
    Parent = topBar,
    BackgroundTransparency = 1,
    Image = ICON_ASSET_ID,
    ImageColor3 = Color3.fromRGB(255, 255, 255),
    ScaleType = Enum.ScaleType.Fit,
    Size = UDim2.new(0, 22, 0, 22),
    Position = UDim2.new(0, PADDING, 0.5, 0),
    AnchorPoint = Vector2.new(0, 0.5),
    ZIndex = 21,
})

local topBarTitle = new("TextLabel", {
    Parent = topBar,
    BackgroundTransparency = 1,
    Text = "NeizMotion",
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextColor3 = Palette.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, PADDING + 32, 0, 0),
    Size = UDim2.new(1, -100, 1, 0),
    ZIndex = 21,
})

local closeButton = new("TextButton", {
    Parent = topBar,
    BackgroundColor3 = Palette.card,
    BackgroundTransparency = 0.1,
    Text = "×",
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextColor3 = Palette.subtext,
    Size = UDim2.new(0, 26, 0, 26),
    Position = UDim2.new(1, -PADDING, 0, 12),
    AnchorPoint = Vector2.new(1, 0),
    ZIndex = 21,
})
corner(closeButton, 13)

local divider = new("Frame", {
    Parent = mainWindow,
    BackgroundColor3 = Palette.white,
    BackgroundTransparency = 0.94,
    Size = UDim2.new(1, -PADDING * 2, 0, 1),
    Position = UDim2.new(0, PADDING, 0, TOPBAR_H),
    ZIndex = 21,
})

----------------------------------------------------------------
-- Sidebar navigation
----------------------------------------------------------------

local sidebar = new("Frame", {
    Name = "Sidebar",
    Parent = mainWindow,
    BackgroundTransparency = 1,
    Size = UDim2.new(0, SIDEBAR_W, 1, -(TOPBAR_H + PADDING + PADDING)),
    Position = UDim2.new(0, PADDING, 0, TOPBAR_H + PADDING),
    ZIndex = 21,
})

local sidebarHighlight = new("Frame", {
    Parent = sidebar,
    BackgroundColor3 = Palette.accent,
    BackgroundTransparency = 0.85,
    Size = UDim2.new(1, 0, 0, NAV_BTN_H),
    Position = UDim2.new(0, 0, 0, 0),
    ZIndex = 21,
})
corner(sidebarHighlight, 13)
stroke(sidebarHighlight, Palette.accent, 1, 0.55)

local function createNavButton(badgeText, label, yPos)
    local btn = new("TextButton", {
        Parent = sidebar,
        BackgroundTransparency = 1,
        Text = "",
        Size = UDim2.new(1, 0, 0, NAV_BTN_H),
        Position = UDim2.new(0, 0, 0, yPos),
        ZIndex = 22,
    })
    local badge = new("Frame", {
        Parent = btn,
        BackgroundColor3 = Palette.card,
        BackgroundTransparency = 0,
        Size = UDim2.new(0, 22, 0, 22),
        Position = UDim2.new(0.5, 0, 0, 6),
        AnchorPoint = Vector2.new(0.5, 0),
        ZIndex = 22,
    })
    corner(badge, 11)
    local badgeLabel = new("TextLabel", {
        Parent = badge,
        BackgroundTransparency = 1,
        Text = badgeText,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Palette.text,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 22,
    })
    local caption = new("TextLabel", {
        Parent = btn,
        BackgroundTransparency = 1,
        Text = label,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextColor3 = Palette.subtext,
        Size = UDim2.new(1, 0, 0, 13),
        Position = UDim2.new(0, 0, 0, 31),
        ZIndex = 22,
    })
    return btn, badge, badgeLabel, caption
end

local motionNavBtn, motionBadge, _, motionCaption = createNavButton("MB", "Blur", 0)
local settingsNavBtn, settingsBadge, _, settingsCaption = createNavButton("ST", "Setup", NAV_BTN_H + 6)
local shopNavBtn, shopBadge, _, shopCaption = createNavButton("SH", "Shop", (NAV_BTN_H + 6) * 2)

----------------------------------------------------------------
-- Content area
----------------------------------------------------------------

local contentContainer = new("Frame", {
    Name = "Content",
    Parent = mainWindow,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -(PADDING + SIDEBAR_W + GAP + PADDING), 1, -(TOPBAR_H + PADDING + PADDING)),
    Position = UDim2.new(0, PADDING + SIDEBAR_W + GAP, 0, TOPBAR_H + PADDING),
    ClipsDescendants = true,
    ZIndex = 21,
})

local function createPage(name, startVisible)
    local page = new("CanvasGroup", {
        Name = name,
        Parent = contentContainer,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        GroupTransparency = startVisible and 0 or 1,
        Visible = startVisible or false,
        ZIndex = 21,
    })

    local scroll = new("ScrollingFrame", {
        Name = "Scroll",
        Parent = page,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Palette.accent,
        ScrollBarImageTransparency = 0.5,
        ZIndex = 21,
    })
    new("UIPadding", { Parent = scroll, PaddingRight = UDim.new(0, 6) })
    new("UIListLayout", {
        Parent = scroll,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    return page, scroll
end

local motionBlurPage, motionBlurScroll = createPage("MotionBlurPage", true)
local settingsPage, settingsScroll = createPage("SettingsPage", false)
local shopPage, shopScroll = createPage("ShopPage", false)

----------------------------------------------------------------
-- Controls: card / slider / toggle / action button
----------------------------------------------------------------

local function createCard(parent, order, height)
    local card = new("Frame", {
        Parent = parent,
        LayoutOrder = order,
        BackgroundColor3 = Palette.card,
        BackgroundTransparency = 0.25,
        Size = UDim2.new(1, 0, 0, height),
        ZIndex = 21,
    })
    corner(card, 12)
    stroke(card, Palette.white, 1, 0.93)
    new("UIPadding", {
        Parent = card,
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
    })
    return card
end

local function createSlider(parent, order, text, key, min, max, decimals, onChange)
    local card = createCard(parent, order, 54)

    new("TextLabel", {
        Parent = card, BackgroundTransparency = 1, Text = text,
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Palette.subtext,
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.6, 0, 0, 16),
    })

    local valueLabel = new("TextLabel", {
        Parent = card, BackgroundTransparency = 1, Text = tostring(Settings[key]),
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Palette.accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        Size = UDim2.new(0.4, 0, 0, 16), Position = UDim2.new(0.6, 0, 0, 0),
    })

    local track = new("Frame", {
        Parent = card, BackgroundColor3 = Palette.field, BackgroundTransparency = 0,
        Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 27),
    })
    corner(track, 3)

    local fill = new("Frame", { Parent = track, BackgroundColor3 = Palette.accent, Size = UDim2.new(0, 0, 1, 0) })
    corner(fill, 3)

    local knob = new("Frame", {
        Parent = track, BackgroundColor3 = Palette.white,
        Size = UDim2.new(0, 14, 0, 14), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0), ZIndex = 23,
    })
    corner(knob, 7)
    stroke(knob, Palette.accent, 2, 0)

    -- oversized invisible hit region so touch input is comfortable
    -- even though the visible track/knob stay compact
    local hitArea = new("TextButton", {
        Parent = card, Text = "", BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 15),
        ZIndex = 24,
    })

    local function setFromAlpha(alpha, fire)
        alpha = math.clamp(alpha, 0, 1)
        local value = min + (max - min) * alpha
        if decimals and decimals > 0 then
            local mult = 10 ^ decimals
            value = math.floor(value * mult + 0.5) / mult
        else
            value = math.floor(value + 0.5)
        end
        Settings[key] = value
        valueLabel.Text = tostring(value)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        if fire and onChange then onChange(value) end
    end

    local function refresh()
        local alpha = (Settings[key] - min) / (max - min)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = tostring(Settings[key])
    end
    refresh()
    table.insert(controlRefreshers, refresh)

    local dragging = false
    local activeInput = nil
    local function updateFromInput(input)
        local relX = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
        setFromAlpha(relX, true)
    end

    hitArea.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            activeInput = input
            updateFromInput(input)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == activeInput and
           (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if dragging and input == activeInput then
            dragging = false
            activeInput = nil
        end
    end)

    return card
end

local function createToggle(parent, order, text, key, desc, onChange)
    local height = desc and 54 or 40
    local card = createCard(parent, order, height)

    new("TextLabel", {
        Parent = card, BackgroundTransparency = 1, Text = text,
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Palette.text,
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.68, 0, 0, 16),
    })

    if desc then
        new("TextLabel", {
            Parent = card, BackgroundTransparency = 1, Text = desc,
            Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Palette.faint,
            TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
            Size = UDim2.new(0.68, 0, 0, 28), Position = UDim2.new(0, 0, 0, 18),
        })
    end

    local track = new("TextButton", {
        Parent = card, Text = "", BackgroundColor3 = Palette.field, BackgroundTransparency = 0,
        Size = UDim2.new(0, 46, 0, 26), AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
    })
    corner(track, 13)

    local knob = new("Frame", {
        Parent = track, BackgroundColor3 = Palette.white,
        Size = UDim2.new(0, 20, 0, 20), AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
    })
    corner(knob, 10)

    local function refresh()
        local on = Settings[key]
        tween(track, { BackgroundColor3 = on and Palette.accent or Palette.field }, 0.12)
        tween(knob, { Position = on and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, 0.12)
    end
    refresh()
    table.insert(controlRefreshers, refresh)

    track.MouseButton1Click:Connect(function()
        Settings[key] = not Settings[key]
        refresh()
        if onChange then onChange(Settings[key]) end
    end)

    return card
end

local function createActionButton(parent, order, text, callback)
    local btn = new("TextButton", {
        Parent = parent, LayoutOrder = order,
        BackgroundColor3 = Palette.card, BackgroundTransparency = 0.15,
        Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Palette.accent,
        Size = UDim2.new(1, 0, 0, 38),
    })
    corner(btn, 12)
    stroke(btn, Palette.accent, 1, 0.65)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

----------------------------------------------------------------
-- Tab content
----------------------------------------------------------------

createToggle(motionBlurScroll, 1, "Motion Blur", "blurEnabled", "Blurs the view while the camera moves")
createSlider(motionBlurScroll, 2, "Strength", "blurStrength", 0, 40, 0)
createSlider(motionBlurScroll, 3, "Intensity", "blurIntensity", 0, 3, 1)
createSlider(motionBlurScroll, 4, "Sensitivity", "blurSensitivity", 0, 2, 2)
createSlider(motionBlurScroll, 5, "Fade In", "blurFadeIn", 0.05, 1, 2)
createSlider(motionBlurScroll, 6, "Fade Out", "blurFadeOut", 0.05, 1.5, 2)

local function applyAppearance()
    tween(floatingWidget, { BackgroundTransparency = Settings.guiTransparency }, 0.2)
    tween(mainWindow, { BackgroundTransparency = Settings.guiTransparency }, 0.2)
    tween(windowScale, { Scale = Settings.guiScale }, 0.2)

    if State.isOpen then
        local base = computeBaseWindowSize()
        tween(mainWindow, { Size = UDim2.new(0, base.X, 0, base.Y) }, 0.22)
    end

    floatingWidget.Visible = Settings.widgetVisible and not State.isOpen
end

createSlider(settingsScroll, 1, "Transparency", "guiTransparency", 0, 0.35, 2, applyAppearance)
createSlider(settingsScroll, 2, "Glass Strength", "glassStrength", 0, 1, 2, applyAppearance)
createSlider(settingsScroll, 3, "Interface Size", "guiScale", 0.85, 1.2, 2, applyAppearance)
createToggle(settingsScroll, 4, "Animations", "animationsEnabled")
createSlider(settingsScroll, 5, "Animation Speed", "animationSpeed", 0.5, 2, 2)
createToggle(settingsScroll, 6, "Floating Widget", "widgetVisible", nil, function(on)
    floatingWidget.Visible = on and not State.isOpen
end)
createToggle(settingsScroll, 7, "Remember Position", "rememberPosition",
    "Keeps the pill and window where you leave them", function(on)
        if not on then
            Settings.pillPosition = DEFAULT_PILL_POSITION
            Settings.windowPosition = DEFAULT_WINDOW_POSITION
            floatingWidget.Position = Settings.pillPosition
            if State.isOpen then
                mainWindow.Position = Settings.windowPosition
            end
        end
    end)
createActionButton(settingsScroll, 8, "Reset to Default", function()
    for k, v in pairs(DEFAULT_SETTINGS) do
        Settings[k] = v
    end
    floatingWidget.Position = Settings.pillPosition
    if State.isOpen then
        mainWindow.Position = Settings.windowPosition
    end
    applyAppearance()
    for _, fn in ipairs(controlRefreshers) do
        fn()
    end
end)

----------------------------------------------------------------
-- Shop tab (auto crate opener, ported from the reference script)
----------------------------------------------------------------

local CRATES = {
    { name = "Premium Explosion", objectName = "PremiumExplosionCrate", settingKey = "shopCrate1" },
    { name = "Normal Sword",      objectName = "NormalSwordCrate",      settingKey = "shopCrate2" },
    { name = "Premium Sword",     objectName = "PremiumSwordCrate",     settingKey = "shopCrate3" },
}

for i, data in ipairs(CRATES) do
    createToggle(shopScroll, i, data.name, data.settingKey)
end
createToggle(shopScroll, 4, "Skip Animation", "shopSkipAnimation", "Hides the unbox popup while auto-opening")
createSlider(shopScroll, 5, "Interval", "shopInterval", 0.5, 30, 1)

local shopStatusCard = createCard(shopScroll, 6, 34)
local shopStatus = new("TextLabel", {
    Parent = shopStatusCard, BackgroundTransparency = 1, Text = "Ready",
    Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Palette.subtext,
    TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 1, 0),
})

local function setShopStatus(text, color)
    shopStatus.Text = text
    shopStatus.TextColor3 = color or Palette.subtext
end

local shopRemote, shopCrateFolder

task.spawn(function()
    local okRemote, remoteResult = pcall(function()
        return ReplicatedStorage:WaitForChild("Remote", 10):WaitForChild("RemoteFunction", 10)
    end)
    local okFolder, folderResult = pcall(function()
        return workspace:WaitForChild("Spawn", 10):WaitForChild("Crates", 10)
    end)

    if okRemote then shopRemote = remoteResult end
    if okFolder then shopCrateFolder = folderResult end

    if not (shopRemote and shopCrateFolder) then
        setShopStatus("Shop remotes not found", Color3.fromRGB(255, 110, 110))
    end
end)

local function openCrate(data)
    if not (shopRemote and shopCrateFolder) then
        setShopStatus("Shop not ready", Color3.fromRGB(255, 170, 90))
        return
    end

    local crate = shopCrateFolder:FindFirstChild(data.objectName)
    if not crate then
        setShopStatus(data.name .. ": crate not found", Color3.fromRGB(255, 110, 110))
        return
    end

    local success, result = pcall(function()
        return shopRemote:InvokeServer("PromptPurchaseCrate", crate)
    end)

    if success then
        setShopStatus("Opened: " .. data.name, Color3.fromRGB(120, 230, 150))
    else
        setShopStatus("Failed: " .. data.name, Color3.fromRGB(255, 110, 110))
        warn(result)
    end
end

local function hideShopUnbox()
    if not Settings.shopSkipAnimation then return end
    local unbox = playerGui:FindFirstChild("UnboxGUI", true)
    if unbox then
        if unbox:IsA("ScreenGui") then
            unbox.Enabled = false
        elseif unbox:IsA("GuiObject") then
            unbox.Visible = false
        end
    end
end

playerGui.DescendantAdded:Connect(function(obj)
    if Settings.shopSkipAnimation and obj.Name == "UnboxGUI" then
        task.defer(hideShopUnbox)
    end
end)

task.spawn(function()
    while screenGui.Parent do
        local anyEnabled = false
        for _, data in ipairs(CRATES) do
            if Settings[data.settingKey] then
                anyEnabled = true
                openCrate(data)
                if Settings.shopSkipAnimation then
                    task.defer(hideShopUnbox)
                end
            end
        end
        if anyEnabled then
            setShopStatus(string.format("Auto running - %.1fs", Settings.shopInterval), Palette.subtext)
        end
        task.wait(Settings.shopInterval)
    end
end)

----------------------------------------------------------------
-- Tabs / open / close / drag
----------------------------------------------------------------

local TABS = {
    { key = "MotionBlur", page = motionBlurPage, caption = motionCaption, nav = motionNavBtn },
    { key = "Settings",   page = settingsPage,   caption = settingsCaption, nav = settingsNavBtn },
    { key = "Shop",       page = shopPage,       caption = shopCaption,     nav = shopNavBtn },
}

local function findTab(key)
    for i, t in ipairs(TABS) do
        if t.key == key then return i, t end
    end
end

local function switchTab(name)
    if State.activeTab == name then return end
    local targetIndex, target = findTab(name)
    if not target then return end

    local currentIndex = State.activeTab and findTab(State.activeTab)
    local sign = (currentIndex and targetIndex < currentIndex) and -1 or 1
    local hidePage = currentIndex and TABS[currentIndex].page

    State.activeTab = name

    tween(sidebarHighlight, { Position = UDim2.new(0, 0, 0, (targetIndex - 1) * (NAV_BTN_H + 6)) }, 0.2)
    for i, t in ipairs(TABS) do
        tween(t.caption, { TextColor3 = i == targetIndex and Palette.text or Palette.subtext }, 0.15)
    end

    target.page.Visible = true
    target.page.Position = UDim2.new(sign * -0.06, 0, 0, 0)
    target.page.GroupTransparency = 1
    tween(target.page, { Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0 }, 0.2)

    if hidePage then
        tween(hidePage, { Position = UDim2.new(sign * 0.06, 0, 0, 0), GroupTransparency = 1 }, 0.16)
        task.delay(0.16, function()
            if hidePage.GroupTransparency > 0.9 then
                hidePage.Visible = false
            end
        end)
    end
end

for _, t in ipairs(TABS) do
    t.nav.MouseButton1Click:Connect(function() switchTab(t.key) end)
end

local function openMenu()
    if State.isOpen then return end
    State.isOpen = true

    local base = computeBaseWindowSize()
    local effective = computeEffectiveWindowSize()
    local destination = Settings.rememberPosition and Settings.windowPosition or DEFAULT_WINDOW_POSITION
    destination = clampToScreen(destination, effective)

    windowScale.Scale = Settings.guiScale
    mainWindow.Position = floatingWidget.Position
    mainWindow.Size = WIDGET_SIZE
    mainWindow.GroupTransparency = 0
    mainWindow.Visible = true
    backdrop.Visible = true

    tween(floatingWidget, { GroupTransparency = 1 }, 0.18)
    tween(mainWindow, {
        Size = UDim2.new(0, base.X, 0, base.Y),
        Position = destination,
    }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    task.delay(0.18, function()
        if State.isOpen then
            floatingWidget.Visible = false
        end
    end)
end

local function closeMenu()
    if not State.isOpen then return end
    State.isOpen = false

    if Settings.rememberPosition then
        Settings.windowPosition = mainWindow.Position
    end

    local pillDest = Settings.rememberPosition and Settings.pillPosition or DEFAULT_PILL_POSITION
    pillDest = clampToScreen(pillDest, Vector2.new(WIDGET_SIZE.X.Offset, WIDGET_SIZE.Y.Offset))

    floatingWidget.Position = pillDest
    floatingWidget.Size = WIDGET_SIZE
    floatingWidget.GroupTransparency = 1
    floatingWidget.Visible = Settings.widgetVisible

    tween(mainWindow, { Size = WIDGET_SIZE, Position = pillDest }, 0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    tween(floatingWidget, { GroupTransparency = 0 }, 0.26)

    task.delay(0.28, function()
        if not State.isOpen then
            mainWindow.Visible = false
            backdrop.Visible = false
            local base = computeBaseWindowSize()
            mainWindow.Size = UDim2.new(0, base.X, 0, base.Y)
        end
    end)
end

closeButton.MouseButton1Click:Connect(closeMenu)
backdrop.MouseButton1Click:Connect(closeMenu)

-- smoothed drag: the frame chases a target position every frame via
-- exponential interpolation instead of snapping straight to the cursor
local function makeDraggable(frame, handle, opts)
    opts = opts or {}
    local followSpeed = opts.followSpeed or 18
    local onEnd = opts.onEnd

    local dragging = false
    local activeInput = nil
    local dragStart = Vector2.new()
    local startPos = frame.Position
    local targetPos = frame.Position
    local moved = false
    local renderConn = nil

    local function startFollow()
        if renderConn then renderConn:Disconnect() end
        renderConn = RunService.RenderStepped:Connect(function(dt)
            local alpha = 1 - math.exp(-followSpeed * dt)
            frame.Position = frame.Position:Lerp(targetPos, alpha)
        end)
    end

    local function stopFollow(snap)
        if renderConn then
            renderConn:Disconnect()
            renderConn = nil
        end
        if snap then
            frame.Position = targetPos
        end
    end

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            activeInput = input
            dragStart = Vector2.new(input.Position.X, input.Position.Y)
            startPos = frame.Position
            targetPos = frame.Position
            startFollow()
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == activeInput and
           (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
            if delta.Magnitude > 4 then moved = true end
            targetPos = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if dragging and input == activeInput then
            dragging = false
            activeInput = nil
            local finalMoved = moved
            local finalPos = targetPos
            task.delay(0.12, function()
                stopFollow(true)
            end)
            if onEnd then onEnd(finalMoved, finalPos) end
        end
    end)
end

makeDraggable(floatingWidget, widgetButton, {
    followSpeed = 20,
    onEnd = function(moved, finalPos)
        if not moved then
            openMenu()
            return
        end
        finalPos = clampToScreen(finalPos, Vector2.new(WIDGET_SIZE.X.Offset, WIDGET_SIZE.Y.Offset))
        floatingWidget.Position = finalPos
        if Settings.rememberPosition then
            Settings.pillPosition = finalPos
        end
    end,
})

makeDraggable(mainWindow, topBar, {
    followSpeed = 16,
    onEnd = function(_, finalPos)
        local effective = computeEffectiveWindowSize()
        finalPos = clampToScreen(finalPos, effective)
        mainWindow.Position = finalPos
        if Settings.rememberPosition then
            Settings.windowPosition = finalPos
        end
    end,
})

----------------------------------------------------------------
-- Motion blur runtime (independent of GUI open/closed state)
----------------------------------------------------------------

local blurEffect = Lighting:FindFirstChild("NeizMotionBlur")
if not blurEffect then
    blurEffect = new("BlurEffect", { Name = "NeizMotionBlur", Size = 0, Parent = Lighting })
end

local lastPosition = (workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position) or Vector3.new()
local currentBlur = 0

RunService.RenderStepped:Connect(function(dt)
    local cam = workspace.CurrentCamera
    if not cam then return end

    local pos = cam.CFrame.Position
    local speed = (pos - lastPosition).Magnitude / math.max(dt, 1 / 240)
    lastPosition = pos

    local targetBlur = 0
    if Settings.blurEnabled then
        targetBlur = math.clamp(speed * Settings.blurSensitivity * Settings.blurIntensity, 0, Settings.blurStrength)
    end

    local smoothTime
    if targetBlur > currentBlur then
        smoothTime = math.max(Settings.blurFadeIn, 0.01)
    else
        smoothTime = math.max(Settings.blurFadeOut, 0.01)
    end

    local alpha = 1 - math.exp(-dt / smoothTime)
    currentBlur = currentBlur + (targetBlur - currentBlur) * alpha
    blurEffect.Size = currentBlur
end)

----------------------------------------------------------------
-- Responsive reflow + init
----------------------------------------------------------------

screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    floatingWidget.Position = clampToScreen(floatingWidget.Position, Vector2.new(WIDGET_SIZE.X.Offset, WIDGET_SIZE.Y.Offset))
    if State.isOpen then
        local base = computeBaseWindowSize()
        local effective = computeEffectiveWindowSize()
        mainWindow.Size = UDim2.new(0, base.X, 0, base.Y)
        mainWindow.Position = clampToScreen(mainWindow.Position, effective)
    end
end)

switchTab("MotionBlur")
applyAppearance()
