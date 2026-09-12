--[[
    ================================================================
    NeizMotion — premium glassmorphism floating overlay + cinematic
    motion blur for Roblox.  (v2 — визуальный и UX-апдейт)

    Изменения этой версии:
      - плотнее и контрастнее фон таблетки/окна (glass, но читаемо)
      - боковая навигация вместо верхних вкладок
      - премиальные карточки для контролов, состояния On/Off
      - фикс отображения иконки (только через ICON_ASSET_ID в коде)
      - плавное (сглаженное) перетаскивание таблетки и окна
      - "Remember Position" — отдельно для таблетки и окна
      - адаптивный размер/позиция под разные экраны, в т.ч. мобильные

    Структура файла:
      1. Сервисы
      2. Конфиг / настройки по умолчанию
      3. Состояние (State) и вспомогательные функции
      4. ScreenGui: floating widget + главное окно (topbar, sidebar, content)
      5. Контролы: card / slider / toggle / button
      6. Наполнение вкладок Motion Blur / Settings
      7. Открытие / закрытие / переключение вкладок / drag
      8. Рантайм motion blur (работает независимо от GUI)
      9. Адаптивность и инициализация
    ================================================================
]]

----------------------------------------------------------------
-- 1. СЕРВИСЫ
----------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- 2. КОНФИГ / НАСТРОЙКИ ПО УМОЛЧАНИЮ
----------------------------------------------------------------

-- ИКОНКА ЗАДАЁТСЯ ТОЛЬКО ЗДЕСЬ (в интерфейсе смена иконки не предусмотрена)
local ICON_ASSET_ID = "rbxassetid://132896400537590"

local DEFAULT_PILL_POSITION   = UDim2.new(0.5, 0, 0.36, 0)
local DEFAULT_WINDOW_POSITION = UDim2.new(0.5, 0, 0.28, 0)

local DEFAULT_SETTINGS = {
    -- Motion Blur
    blurEnabled      = true,
    blurStrength     = 18,     -- максимальный размер блюра (0-40)
    blurIntensity    = 1,      -- множитель силы (0-3)
    blurSensitivity  = 0.6,    -- чувствительность к скорости камеры (0-2)
    blurFadeIn       = 0.15,   -- плавность появления (сек)
    blurFadeOut      = 0.35,   -- плавность исчезания (сек)

    -- Внешний вид / поведение GUI
    guiTransparency   = 0.08,  -- прозрачность фона карточек (0-0.5)
    glassStrength     = 0.7,   -- сила стекло-эффекта (0-1)
    guiScale          = 1,     -- масштаб интерфейса (0.85-1.2)
    animationsEnabled = true,
    animationSpeed    = 1,     -- множитель скорости анимаций (0.5-2)
    widgetVisible     = true,
    rememberPosition  = true,
    pillPosition      = DEFAULT_PILL_POSITION,
    windowPosition    = DEFAULT_WINDOW_POSITION,
}

local Settings = {}
for k, v in pairs(DEFAULT_SETTINGS) do
    Settings[k] = v
end

local Palette = {
    bg      = Color3.fromRGB(15, 15, 20),   -- более плотный тёмный фон
    bgLight = Color3.fromRGB(30, 30, 38),
    card    = Color3.fromRGB(26, 26, 33),
    accent  = Color3.fromRGB(126, 138, 255),
    text    = Color3.fromRGB(244, 244, 248),
    subtext = Color3.fromRGB(168, 168, 182),
    white   = Color3.fromRGB(255, 255, 255),
}

local WIDGET_SIZE = UDim2.new(0, 132, 0, 44)
local SIDEBAR_W   = 72

----------------------------------------------------------------
-- 3. СОСТОЯНИЕ И ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
----------------------------------------------------------------

local State = {
    isOpen = false,
    activeTab = nil, -- задаётся первым вызовом switchTab() при инициализации
}

local controlRefreshers = {} -- функции синхронизации UI со Settings (для reset)

local function new(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    return inst
end

local function tween(instance, props, duration, style, direction)
    duration = duration or 0.25
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
    return new("UICorner", { CornerRadius = UDim.new(0, radius or 16), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
    return new("UIStroke", {
        Color = color or Palette.white,
        Thickness = thickness or 1,
        Transparency = transparency or 0.6,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function gradient(parent, rotation, transp1, transp2)
    return new("UIGradient", {
        Rotation = rotation or 100,
        Color = ColorSequence.new(Palette.white, Color3.fromRGB(200, 200, 212)),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, transp1 or 0.85),
            NumberSequenceKeypoint.new(1, transp2 or 0.96),
        }),
        Parent = parent,
    })
end

----------------------------------------------------------------
-- 4. SCREENGUI / FLOATING WIDGET / MAIN WINDOW
----------------------------------------------------------------

local screenGui = new("ScreenGui", {
    Name = "NeizMotionGui",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
    Parent = player:WaitForChild("PlayerGui"),
})

local function getScreenSize()
    local size = screenGui.AbsoluteSize
    if size.X <= 1 or size.Y <= 1 then
        local cam = workspace.CurrentCamera
        size = (cam and cam.ViewportSize) or Vector2.new(800, 600)
    end
    return size
end

-- держит рамку в пределах экрана (AnchorPoint предполагается (0.5, 0))
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

-- "чистый" (немасштабированный) размер окна, подогнанный только под
-- доступное место на экране; реальный визуальный размер = base * guiScale
local function computeBaseWindowSize()
    local vp = getScreenSize()
    local w = math.clamp(vp.X - 32, 260, 340)
    local h = math.clamp(vp.Y - 140, 320, 404)
    return Vector2.new(w, h)
end

-- визуальный (эффективный) размер окна с учётом UIScale — используется
-- для позиционирования / clamp по границам экрана
local function computeEffectiveWindowSize()
    local base = computeBaseWindowSize()
    return Vector2.new(base.X * Settings.guiScale, base.Y * Settings.guiScale)
end

-- ===== Floating Widget (pill) =====
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
corner(floatingWidget, 22)
stroke(floatingWidget, Palette.white, 1, 0.55)
gradient(floatingWidget, 100)

local widgetGlow = new("ImageLabel", {
    Name = "Glow",
    Parent = floatingWidget,
    BackgroundTransparency = 1,
    Image = "rbxassetid://5028857084",
    ImageColor3 = Palette.accent,
    ImageTransparency = 0.82,
    Size = UDim2.new(1.8, 0, 1.8, 0),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    ZIndex = 1,
})

local widgetIcon = new("ImageLabel", {
    Name = "Icon",
    Parent = floatingWidget,
    BackgroundTransparency = 1,
    Image = ICON_ASSET_ID,
    ScaleType = Enum.ScaleType.Fit,
    Size = UDim2.new(0, 24, 0, 24),
    Position = UDim2.new(0, 12, 0.5, 0),
    AnchorPoint = Vector2.new(0, 0.5),
    ZIndex = 2,
})
corner(widgetIcon, 6)

local widgetLabel = new("TextLabel", {
    Name = "Label",
    Parent = floatingWidget,
    BackgroundTransparency = 1,
    Text = "NeizMotion",
    Font = Enum.Font.GothamMedium,
    TextSize = 15,
    TextColor3 = Palette.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 46, 0, 0),
    Size = UDim2.new(1, -56, 1, 0),
    ZIndex = 2,
})

local widgetButton = new("TextButton", {
    Name = "ClickArea",
    Parent = floatingWidget,
    BackgroundTransparency = 1,
    Text = "",
    Size = UDim2.new(1, 0, 1, 0),
    ZIndex = 5,
})

-- ===== Backdrop (клик вне окна закрывает) =====
local backdrop = new("TextButton", {
    Name = "Backdrop",
    Parent = screenGui,
    BackgroundTransparency = 1,
    Text = "",
    Size = UDim2.new(1, 0, 1, 0),
    Visible = false,
    ZIndex = 15,
})

-- ===== Main Window =====
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
corner(mainWindow, 26)
stroke(mainWindow, Palette.white, 1, 0.55)
gradient(mainWindow, 100)

local windowScale = new("UIScale", { Parent = mainWindow, Scale = 1 })

-- Top bar
local topBar = new("Frame", {
    Name = "TopBar",
    Parent = mainWindow,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 54),
    ZIndex = 21,
})

local topBarIcon = new("ImageLabel", {
    Parent = topBar,
    BackgroundTransparency = 1,
    Image = ICON_ASSET_ID,
    ScaleType = Enum.ScaleType.Fit,
    Size = UDim2.new(0, 24, 0, 24),
    Position = UDim2.new(0, 16, 0.5, 0),
    AnchorPoint = Vector2.new(0, 0.5),
    ZIndex = 21,
})
corner(topBarIcon, 6)

local topBarTitle = new("TextLabel", {
    Parent = topBar,
    BackgroundTransparency = 1,
    Text = "NeizMotion",
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = Palette.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.new(0, 50, 0, 0),
    Size = UDim2.new(1, -100, 1, 0),
    ZIndex = 21,
})

local closeButton = new("TextButton", {
    Parent = topBar,
    BackgroundColor3 = Palette.bgLight,
    BackgroundTransparency = 0.15,
    Text = "×",
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextColor3 = Palette.subtext,
    Size = UDim2.new(0, 28, 0, 28),
    Position = UDim2.new(1, -16, 0, 13),
    AnchorPoint = Vector2.new(1, 0),
    ZIndex = 21,
})
corner(closeButton, 14)

local divider = new("Frame", {
    Parent = mainWindow,
    BackgroundColor3 = Palette.white,
    BackgroundTransparency = 0.92,
    Size = UDim2.new(1, -32, 0, 1),
    Position = UDim2.new(0, 16, 0, 54),
    ZIndex = 21,
})

-- ===== Sidebar navigation =====
local sidebar = new("Frame", {
    Name = "Sidebar",
    Parent = mainWindow,
    BackgroundTransparency = 1,
    Size = UDim2.new(0, SIDEBAR_W, 1, -70),
    Position = UDim2.new(0, 12, 0, 62),
    ZIndex = 21,
})

local sidebarHighlight = new("Frame", {
    Parent = sidebar,
    BackgroundColor3 = Palette.accent,
    BackgroundTransparency = 0.78,
    Size = UDim2.new(1, 0, 0, 56),
    Position = UDim2.new(0, 0, 0, 0),
    ZIndex = 21,
})
corner(sidebarHighlight, 16)
stroke(sidebarHighlight, Palette.accent, 1, 0.4)

local function createNavButton(badgeText, label, yPos)
    local btn = new("TextButton", {
        Parent = sidebar,
        BackgroundTransparency = 1,
        Text = "",
        Size = UDim2.new(1, 0, 0, 56),
        Position = UDim2.new(0, 0, 0, yPos),
        ZIndex = 22,
    })
    local badge = new("Frame", {
        Parent = btn,
        BackgroundColor3 = Palette.bgLight,
        BackgroundTransparency = 0.1,
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(0.5, 0, 0, 6),
        AnchorPoint = Vector2.new(0.5, 0),
        ZIndex = 22,
    })
    corner(badge, 14)
    local badgeLabel = new("TextLabel", {
        Parent = badge,
        BackgroundTransparency = 1,
        Text = badgeText,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
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
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.new(0, 0, 0, 38),
        ZIndex = 22,
    })
    return btn, badge, badgeLabel, caption
end

local motionNavBtn, motionBadge, _, motionCaption = createNavButton("MB", "Blur", 0)
local settingsNavBtn, settingsBadge, _, settingsCaption = createNavButton("ST", "Settings", 64)

-- ===== Content area =====
local contentContainer = new("Frame", {
    Name = "Content",
    Parent = mainWindow,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -(SIDEBAR_W + 12 + 12 + 16), 1, -70),
    Position = UDim2.new(0, SIDEBAR_W + 12 + 12, 0, 62),
    ClipsDescendants = true,
    ZIndex = 21,
})

local motionBlurPage = new("CanvasGroup", {
    Name = "MotionBlurPage",
    Parent = contentContainer,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    ZIndex = 21,
})
local motionBlurLayout = new("UIListLayout", {
    Parent = motionBlurPage,
    Padding = UDim.new(0, 10),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local settingsPage = new("CanvasGroup", {
    Name = "SettingsPage",
    Parent = contentContainer,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    Position = UDim2.new(0.08, 0, 0, 0),
    GroupTransparency = 1,
    Visible = false,
    ZIndex = 21,
})
local settingsLayout = new("UIListLayout", {
    Parent = settingsPage,
    Padding = UDim.new(0, 10),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

----------------------------------------------------------------
-- 5. КОНТРОЛЫ: CARD / SLIDER / TOGGLE / BUTTON
----------------------------------------------------------------

local function createCard(parent, order, height)
    local card = new("Frame", {
        Parent = parent,
        LayoutOrder = order,
        BackgroundColor3 = Palette.card,
        BackgroundTransparency = 0.15,
        Size = UDim2.new(1, 0, 0, height),
        ZIndex = 21,
    })
    corner(card, 14)
    stroke(card, Palette.white, 1, 0.9)
    new("UIPadding", {
        Parent = card,
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
    })
    return card
end

local function createSlider(parent, order, text, key, min, max, decimals, onChange)
    local card = createCard(parent, order, 60)

    new("TextLabel", {
        Parent = card, BackgroundTransparency = 1, Text = text,
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Palette.subtext,
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.6, 0, 0, 16),
    })

    local valueLabel = new("TextLabel", {
        Parent = card, BackgroundTransparency = 1, Text = tostring(Settings[key]),
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Palette.accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        Size = UDim2.new(0.4, 0, 0, 16), Position = UDim2.new(0.6, 0, 0, 0),
    })

    local track = new("Frame", {
        Parent = card, BackgroundColor3 = Palette.bg, BackgroundTransparency = 0.05,
        Size = UDim2.new(1, 0, 0, 8), Position = UDim2.new(0, 0, 0, 27),
    })
    corner(track, 4)

    local fill = new("Frame", { Parent = track, BackgroundColor3 = Palette.accent, Size = UDim2.new(0, 0, 1, 0) })
    corner(fill, 4)

    local knob = new("Frame", {
        Parent = track, BackgroundColor3 = Palette.white,
        Size = UDim2.new(0, 16, 0, 16), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0), ZIndex = 23,
    })
    corner(knob, 8)
    stroke(knob, Palette.accent, 2, 0.05)

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
    local function updateFromInput(input)
        local relX = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
        setFromAlpha(relX, true)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromInput(input)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return card
end

local function createToggle(parent, order, text, key, onChange)
    local card = createCard(parent, order, 44)

    new("TextLabel", {
        Parent = card, BackgroundTransparency = 1, Text = text,
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Palette.subtext,
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.5, 0, 1, 0),
    })

    local statusLabel = new("TextLabel", {
        Parent = card, BackgroundTransparency = 1,
        Text = Settings[key] and "On" or "Off",
        Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = Settings[key] and Palette.accent or Palette.subtext,
        TextXAlignment = Enum.TextXAlignment.Right,
        Size = UDim2.new(0.24, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0),
    })

    local track = new("TextButton", {
        Parent = card, Text = "", BackgroundColor3 = Palette.bg, BackgroundTransparency = 0.05,
        Size = UDim2.new(0, 44, 0, 24), AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
    })
    corner(track, 12)

    local knob = new("Frame", {
        Parent = track, BackgroundColor3 = Palette.white,
        Size = UDim2.new(0, 18, 0, 18), AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
    })
    corner(knob, 9)

    local function refresh()
        local on = Settings[key]
        tween(track, { BackgroundColor3 = on and Palette.accent or Palette.bg }, 0.15)
        tween(knob, { Position = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, 0.15)
        statusLabel.Text = on and "On" or "Off"
        statusLabel.TextColor3 = on and Palette.accent or Palette.subtext
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
        Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Palette.text,
        Size = UDim2.new(1, 0, 0, 40),
    })
    corner(btn, 14)
    stroke(btn, Palette.accent, 1, 0.45)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

----------------------------------------------------------------
-- 6. НАПОЛНЕНИЕ ВКЛАДОК
----------------------------------------------------------------

-- ===== Motion Blur =====
createToggle(motionBlurPage, 1, "Enable Motion Blur", "blurEnabled")
createSlider(motionBlurPage, 2, "Strength", "blurStrength", 0, 40, 0)
createSlider(motionBlurPage, 3, "Intensity", "blurIntensity", 0, 3, 1)
createSlider(motionBlurPage, 4, "Sensitivity", "blurSensitivity", 0, 2, 2)
createSlider(motionBlurPage, 5, "Fade In", "blurFadeIn", 0.05, 1, 2)
createSlider(motionBlurPage, 6, "Fade Out", "blurFadeOut", 0.05, 1.5, 2)

-- ===== Settings =====
local function applyAppearance()
    tween(floatingWidget, { BackgroundTransparency = Settings.guiTransparency }, 0.2)
    tween(mainWindow, { BackgroundTransparency = Settings.guiTransparency }, 0.2)
    tween(windowScale, { Scale = Settings.guiScale }, 0.2)

    if State.isOpen then
        local base = computeBaseWindowSize()
        tween(mainWindow, { Size = UDim2.new(0, base.X, 0, base.Y) }, 0.25)
    end

    floatingWidget.Visible = Settings.widgetVisible and not State.isOpen
end

createSlider(settingsPage, 1, "Transparency", "guiTransparency", 0, 0.5, 2, applyAppearance)
createSlider(settingsPage, 2, "Glass Strength", "glassStrength", 0, 1, 2, applyAppearance)
createSlider(settingsPage, 3, "Interface Size", "guiScale", 0.85, 1.2, 2, applyAppearance)
createToggle(settingsPage, 4, "Animations", "animationsEnabled")
createSlider(settingsPage, 5, "Animation Speed", "animationSpeed", 0.5, 2, 2)
createToggle(settingsPage, 6, "Floating Widget", "widgetVisible", function(on)
    floatingWidget.Visible = on and not State.isOpen
end)
createToggle(settingsPage, 7, "Remember Position", "rememberPosition", function(on)
    if not on then
        Settings.pillPosition = DEFAULT_PILL_POSITION
        Settings.windowPosition = DEFAULT_WINDOW_POSITION
        floatingWidget.Position = Settings.pillPosition
        if State.isOpen then
            mainWindow.Position = Settings.windowPosition
        end
    end
end)
createActionButton(settingsPage, 8, "Reset to Default", function()
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
-- 7. ВКЛАДКИ / ОТКРЫТИЕ / ЗАКРЫТИЕ / DRAG
----------------------------------------------------------------

local function switchTab(name)
    if State.activeTab == name then return end
    local toMotion = name == "MotionBlur"
    State.activeTab = name

    tween(sidebarHighlight, { Position = toMotion and UDim2.new(0, 0, 0, 0) or UDim2.new(0, 0, 0, 64) }, 0.22)
    tween(motionBadge, { BackgroundColor3 = toMotion and Palette.accent or Palette.bgLight }, 0.18)
    tween(motionCaption, { TextColor3 = toMotion and Palette.text or Palette.subtext }, 0.18)
    tween(settingsBadge, { BackgroundColor3 = toMotion and Palette.bgLight or Palette.accent }, 0.18)
    tween(settingsCaption, { TextColor3 = toMotion and Palette.subtext or Palette.text }, 0.18)

    local showPage = toMotion and motionBlurPage or settingsPage
    local hidePage = toMotion and settingsPage or motionBlurPage

    showPage.Visible = true
    showPage.Position = UDim2.new(toMotion and -0.08 or 0.08, 0, 0, 0)
    showPage.GroupTransparency = 1
    tween(showPage, { Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0 }, 0.22)

    tween(hidePage, { Position = UDim2.new(toMotion and 0.08 or -0.08, 0, 0, 0), GroupTransparency = 1 }, 0.18)
    task.delay(0.18, function()
        if hidePage.GroupTransparency > 0.9 then
            hidePage.Visible = false
        end
    end)
end

motionNavBtn.MouseButton1Click:Connect(function() switchTab("MotionBlur") end)
settingsNavBtn.MouseButton1Click:Connect(function() switchTab("Settings") end)

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

    tween(floatingWidget, { GroupTransparency = 1 }, 0.2)
    tween(mainWindow, {
        Size = UDim2.new(0, base.X, 0, base.Y),
        Position = destination,
    }, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

    task.delay(0.2, function()
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

    tween(mainWindow, { Size = WIDGET_SIZE, Position = pillDest }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    tween(floatingWidget, { GroupTransparency = 0 }, 0.3)

    task.delay(0.3, function()
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

-- ===== Плавное (сглаженное) перетаскивание =====
-- Вместо мгновенной установки позиции курсора, рамка "догоняет" целевую
-- точку через экспоненциальное сглаживание в RenderStepped — без рывков
-- и без ощущения ускорения, одинаково хорошо работает для мыши и touch.
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

-- Floating widget: клик открывает меню, перетаскивание перемещает и
-- (если включено Remember Position) сохраняет новую позицию.
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

-- Главное окно перетаскивается за верхнюю панель.
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
-- 8. РАНТАЙМ MOTION BLUR (работает независимо от состояния GUI)
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
-- 9. АДАПТИВНОСТЬ / ИНИЦИАЛИЗАЦИЯ
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

print("[NeizMotion] loaded.")
