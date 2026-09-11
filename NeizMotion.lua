--[[
    ================================================================
    NeizMotion — premium glassmorphism floating overlay + cinematic
    motion blur for Roblox.

    Поместите этот скрипт как LocalScript в StarterPlayerScripts
    (или выполните через executor как LocalScript).

    Структура файла:
      1. Сервисы / базовые переменные
      2. Конфигурация и настройки по умолчанию (включая ICON_ASSET_ID)
      3. Вспомогательные функции (tween, corner, stroke, create)
      4. Построение ScreenGui: floating widget + главное окно
      5. Вкладки Motion Blur / Settings и их контролы
      6. Логика открытия/закрытия (морфинг), перетаскивание, клик вне окна
      7. Рантайм цикл motion blur (работает независимо от GUI)
    ================================================================
]]

----------------------------------------------------------------
-- 1. СЕРВИСЫ
----------------------------------------------------------------
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")

local player  = Players.LocalPlayer
local camera  = workspace.CurrentCamera

----------------------------------------------------------------
-- 2. КОНФИГ / НАСТРОЙКИ ПО УМОЛЧАНИЮ
----------------------------------------------------------------

-- ЗАМЕНЯЕМАЯ ИКОНКА: вставьте сюда свой rbxassetid
local ICON_ASSET_ID = "rbxassetid://14211724302" -- <- замените на свою иконку

local DEFAULT_SETTINGS = {
    -- Motion Blur
    blurEnabled      = true,
    blurStrength     = 18,     -- максимальный размер блюра (0-40)
    blurIntensity    = 1,      -- множитель силы (0-3)
    blurSensitivity  = 0.6,    -- чувствительность к скорости камеры (0-2)
    blurFadeIn       = 0.15,   -- скорость нарастания эффекта (сек)
    blurFadeOut      = 0.35,   -- скорость затухания эффекта (сек)

    -- Внешний вид / поведение GUI
    guiTransparency    = 0.12, -- прозрачность фона карточек (0-0.6)
    glassStrength      = 0.7,  -- сила стекло-эффекта (0-1)
    guiScale           = 1,    -- масштаб интерфейса (0.8-1.3)
    animationsEnabled  = true,
    animationSpeed     = 1,    -- множитель скорости анимаций (0.5-2)
    widgetVisible      = true,
    widgetPosition     = UDim2.new(0.5, 0, 0.38, 0),
    iconId             = ICON_ASSET_ID,
}

local Settings = {}
for k, v in pairs(DEFAULT_SETTINGS) do
    Settings[k] = v
end

local Palette = {
    bg       = Color3.fromRGB(20, 20, 26),
    bgLight  = Color3.fromRGB(34, 34, 42),
    accent   = Color3.fromRGB(124, 136, 255),
    text     = Color3.fromRGB(240, 240, 246),
    subtext  = Color3.fromRGB(162, 162, 176),
    white    = Color3.fromRGB(255, 255, 255),
}

local WIDGET_SIZE = UDim2.new(0, 132, 0, 44)
local WINDOW_BASE_SIZE = Vector2.new(300, 380)

----------------------------------------------------------------
-- 3. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
----------------------------------------------------------------

local controlRefreshers = {} -- функции, синхронизирующие UI со Settings (для reset)

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
    local c = new("UICorner", { CornerRadius = UDim.new(0, radius or 16), Parent = parent })
    return c
end

local function stroke(parent, color, thickness, transparency)
    return new("UIStroke", {
        Color = color or Palette.white,
        Thickness = thickness or 1,
        Transparency = transparency or 0.8,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function gradient(parent, rotation, transp1, transp2)
    return new("UIGradient", {
        Rotation = rotation or 100,
        Color = ColorSequence.new(Palette.white, Color3.fromRGB(205, 205, 215)),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, transp1 or 0.88),
            NumberSequenceKeypoint.new(1, transp2 or 0.97),
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

-- ===== Floating Widget (pill) =====
local floatingWidget = new("CanvasGroup", {
    Name = "FloatingWidget",
    Parent = screenGui,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = Settings.widgetPosition,
    Size = WIDGET_SIZE,
    BackgroundColor3 = Palette.bg,
    BackgroundTransparency = Settings.guiTransparency,
    ClipsDescendants = true,
    Active = true,
    ZIndex = 10,
})
corner(floatingWidget, 22)
stroke(floatingWidget, Palette.white, 1, 0.85)
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
    Image = Settings.iconId,
    Size = UDim2.new(0, 22, 0, 22),
    Position = UDim2.new(0, 13, 0.5, 0),
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
    Position = UDim2.new(0, 44, 0, 0),
    Size = UDim2.new(1, -54, 1, 0),
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

-- ===== Backdrop (click outside to close) =====
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
    Position = Settings.widgetPosition,
    Size = WIDGET_SIZE,
    BackgroundColor3 = Palette.bg,
    BackgroundTransparency = Settings.guiTransparency,
    ClipsDescendants = true,
    Visible = false,
    Active = true,
    ZIndex = 20,
})
corner(mainWindow, 26)
stroke(mainWindow, Palette.white, 1, 0.85)
gradient(mainWindow, 100)

local windowScale = new("UIScale", { Parent = mainWindow, Scale = Settings.guiScale })

-- Top bar
local topBar = new("Frame", {
    Name = "TopBar",
    Parent = mainWindow,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 50),
    Position = UDim2.new(0, 0, 0, 0),
    ZIndex = 21,
})

local topBarIcon = new("ImageLabel", {
    Parent = topBar,
    BackgroundTransparency = 1,
    Image = Settings.iconId,
    Size = UDim2.new(0, 22, 0, 22),
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
    Position = UDim2.new(0, 48, 0, 0),
    Size = UDim2.new(1, -100, 1, 0),
    ZIndex = 21,
})

local closeButton = new("TextButton", {
    Parent = topBar,
    BackgroundColor3 = Palette.bgLight,
    BackgroundTransparency = 0.4,
    Text = "×",
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextColor3 = Palette.subtext,
    Size = UDim2.new(0, 28, 0, 28),
    Position = UDim2.new(1, -16, 0, 11),
    AnchorPoint = Vector2.new(1, 0),
    ZIndex = 21,
})
corner(closeButton, 14)

-- Tab bar
local tabBar = new("Frame", {
    Name = "TabBar",
    Parent = mainWindow,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -32, 0, 34),
    Position = UDim2.new(0, 16, 0, 54),
    ZIndex = 21,
})

local tabButtonMotion = new("TextButton", {
    Parent = tabBar,
    BackgroundTransparency = 1,
    Text = "Motion Blur",
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = Palette.text,
    Size = UDim2.new(0.5, 0, 1, 0),
    Position = UDim2.new(0, 0, 0, 0),
    ZIndex = 22,
})

local tabButtonSettings = new("TextButton", {
    Parent = tabBar,
    BackgroundTransparency = 1,
    Text = "Settings",
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = Palette.subtext,
    Size = UDim2.new(0.5, 0, 1, 0),
    Position = UDim2.new(0.5, 0, 0, 0),
    ZIndex = 22,
})

local tabIndicator = new("Frame", {
    Parent = tabBar,
    BackgroundColor3 = Palette.accent,
    Size = UDim2.new(0.5, -8, 0, 3),
    Position = UDim2.new(0, 4, 1, -3),
    ZIndex = 22,
})
corner(tabIndicator, 2)

-- Content container
local contentContainer = new("Frame", {
    Name = "Content",
    Parent = mainWindow,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -32, 1, -100),
    Position = UDim2.new(0, 16, 0, 96),
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
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

local settingsPage = new("CanvasGroup", {
    Name = "SettingsPage",
    Parent = contentContainer,
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 1, 0),
    Position = UDim2.new(0.12, 0, 0, 0),
    GroupTransparency = 1,
    Visible = false,
    ZIndex = 21,
})
local settingsLayout = new("UIListLayout", {
    Parent = settingsPage,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

----------------------------------------------------------------
-- 5. КОНТРОЛЫ: TOGGLE / SLIDER / TEXTBOX / BUTTON
----------------------------------------------------------------

local function createSlider(parent, order, text, key, min, max, decimals, onChange)
    local row = new("Frame", { Parent = parent, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = order })

    new("TextLabel", {
        Parent = row, BackgroundTransparency = 1, Text = text,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Palette.subtext,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(0.65, 0, 0, 18),
    })

    local valueLabel = new("TextLabel", {
        Parent = row, BackgroundTransparency = 1, Text = tostring(Settings[key]),
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Palette.text,
        TextXAlignment = Enum.TextXAlignment.Right,
        Size = UDim2.new(0.35, 0, 0, 18), Position = UDim2.new(0.65, 0, 0, 0),
    })

    local track = new("Frame", {
        Parent = row, BackgroundColor3 = Palette.bgLight, BackgroundTransparency = 0.15,
        Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 28),
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
    stroke(knob, Palette.accent, 2, 0.1)

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

    return row
end

local function createToggle(parent, order, text, key, onChange)
    local row = new("Frame", { Parent = parent, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order })

    new("TextLabel", {
        Parent = row, BackgroundTransparency = 1, Text = text,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Palette.subtext,
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.7, 0, 1, 0),
    })

    local track = new("TextButton", {
        Parent = row, Text = "", BackgroundColor3 = Palette.bgLight,
        Size = UDim2.new(0, 40, 0, 22), AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
    })
    corner(track, 11)

    local knob = new("Frame", {
        Parent = track, BackgroundColor3 = Palette.white,
        Size = UDim2.new(0, 16, 0, 16), AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
    })
    corner(knob, 8)

    local function refresh()
        local on = Settings[key]
        tween(track, { BackgroundColor3 = on and Palette.accent or Palette.bgLight }, 0.15)
        tween(knob, { Position = on and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, 0.15)
    end
    refresh()
    table.insert(controlRefreshers, refresh)

    track.MouseButton1Click:Connect(function()
        Settings[key] = not Settings[key]
        refresh()
        if onChange then onChange(Settings[key]) end
    end)

    return row
end

local function createButton(parent, order, text, callback)
    local btn = new("TextButton", {
        Parent = parent, LayoutOrder = order,
        BackgroundColor3 = Palette.bgLight, BackgroundTransparency = 0.1,
        Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Palette.text,
        Size = UDim2.new(1, 0, 0, 34),
    })
    corner(btn, 12)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

local function createTextInput(parent, order, text, key, callback)
    local row = new("Frame", { Parent = parent, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = order })

    new("TextLabel", {
        Parent = row, BackgroundTransparency = 1, Text = text,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Palette.subtext,
        TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 16),
    })

    local box = new("TextBox", {
        Parent = row, BackgroundColor3 = Palette.bgLight, BackgroundTransparency = 0.15,
        Text = tostring(Settings[key]), PlaceholderText = "rbxassetid://...",
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Palette.text,
        ClearTextOnFocus = false,
        Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 20),
    })
    corner(box, 8)
    new("UIPadding", { Parent = box, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })

    local function refresh()
        box.Text = tostring(Settings[key])
    end
    table.insert(controlRefreshers, refresh)

    box.FocusLost:Connect(function(enterPressed)
        if box.Text ~= "" then
            callback(box.Text)
        end
    end)

    return row
end

----------------------------------------------------------------
-- MOTION BLUR TAB
----------------------------------------------------------------
createToggle(motionBlurPage, 1, "Enable Motion Blur", "blurEnabled")
createSlider(motionBlurPage, 2, "Strength", "blurStrength", 0, 40, 0)
createSlider(motionBlurPage, 3, "Intensity", "blurIntensity", 0, 3, 1)
createSlider(motionBlurPage, 4, "Sensitivity", "blurSensitivity", 0, 2, 2)
createSlider(motionBlurPage, 5, "Fade In Smoothness", "blurFadeIn", 0.05, 1, 2)
createSlider(motionBlurPage, 6, "Fade Out Smoothness", "blurFadeOut", 0.05, 1.5, 2)

----------------------------------------------------------------
-- SETTINGS TAB
----------------------------------------------------------------
local function applyAppearance()
    tween(floatingWidget, { BackgroundTransparency = Settings.guiTransparency }, 0.2)
    tween(mainWindow, { BackgroundTransparency = Settings.guiTransparency }, 0.2)
    windowScale.Scale = Settings.guiScale
    if isOpenGlobalRef then
        -- resized live while open
        mainWindow.Size = UDim2.new(0, WINDOW_BASE_SIZE.X, 0, WINDOW_BASE_SIZE.Y)
    end
    floatingWidget.Visible = Settings.widgetVisible and not isOpenGlobalRef
end

createSlider(settingsPage, 1, "Interface Transparency", "guiTransparency", 0, 0.6, 2, applyAppearance)
createSlider(settingsPage, 2, "Glass Strength", "glassStrength", 0, 1, 2, applyAppearance)
createSlider(settingsPage, 3, "GUI Size", "guiScale", 0.8, 1.3, 2, applyAppearance)
createToggle(settingsPage, 4, "Animations", "animationsEnabled")
createSlider(settingsPage, 5, "Animation Speed", "animationSpeed", 0.5, 2, 2)
createToggle(settingsPage, 6, "Show Floating Widget", "widgetVisible", function(on)
    floatingWidget.Visible = on and not isOpenGlobalRef
end)
createTextInput(settingsPage, 7, "NeizMotion Icon (Asset ID)", "iconId", function(text)
    Settings.iconId = text
    widgetIcon.Image = text
    topBarIcon.Image = text
end)
createButton(settingsPage, 8, "Reset to Default", function()
    for k, v in pairs(DEFAULT_SETTINGS) do
        Settings[k] = v
    end
    widgetIcon.Image = Settings.iconId
    topBarIcon.Image = Settings.iconId
    floatingWidget.Position = Settings.widgetPosition
    applyAppearance()
    for _, fn in ipairs(controlRefreshers) do
        fn()
    end
end)

----------------------------------------------------------------
-- 6. ОТКРЫТИЕ / ЗАКРЫТИЕ / ПЕРЕТАСКИВАНИЕ / ВКЛАДКИ
----------------------------------------------------------------

isOpenGlobalRef = false -- глобальная (для applyAppearance выше); объявим локально ниже тоже
local isOpen = false

local function switchTab(name)
    local toMotion = name == "MotionBlur"
    tween(tabButtonMotion, { TextColor3 = toMotion and Palette.text or Palette.subtext }, 0.15)
    tween(tabButtonSettings, { TextColor3 = toMotion and Palette.subtext or Palette.text }, 0.15)
    tween(tabIndicator, { Position = toMotion and UDim2.new(0, 4, 1, -3) or UDim2.new(0.5, 4, 1, -3) }, 0.2)

    local showPage = toMotion and motionBlurPage or settingsPage
    local hidePage = toMotion and settingsPage or motionBlurPage

    showPage.Visible = true
    showPage.Position = UDim2.new(toMotion and -0.12 or 0.12, 0, 0, 0)
    showPage.GroupTransparency = 1
    tween(showPage, { Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0 }, 0.25)

    tween(hidePage, { Position = UDim2.new(toMotion and 0.12 or -0.12, 0, 0, 0), GroupTransparency = 1 }, 0.2)
    task.delay(0.2, function()
        if hidePage.GroupTransparency > 0.9 then
            hidePage.Visible = false
        end
    end)
end

tabButtonMotion.MouseButton1Click:Connect(function() switchTab("MotionBlur") end)
tabButtonSettings.MouseButton1Click:Connect(function() switchTab("Settings") end)

local function openMenu()
    if isOpen then return end
    isOpen = true
    isOpenGlobalRef = true

    mainWindow.Position = floatingWidget.Position
    mainWindow.Size = WIDGET_SIZE
    mainWindow.GroupTransparency = 0
    mainWindow.Visible = true
    backdrop.Visible = true

    tween(floatingWidget, { GroupTransparency = 1 }, 0.2)
    tween(mainWindow, {
        Size = UDim2.new(0, WINDOW_BASE_SIZE.X, 0, WINDOW_BASE_SIZE.Y),
    }, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

    task.delay(0.2, function()
        if isOpen then
            floatingWidget.Visible = false
        end
    end)
end

local function closeMenu()
    if not isOpen then return end
    isOpen = false
    isOpenGlobalRef = false

    floatingWidget.Position = Settings.widgetPosition
    floatingWidget.Size = WIDGET_SIZE
    floatingWidget.GroupTransparency = 1
    floatingWidget.Visible = Settings.widgetVisible

    tween(mainWindow, { Size = WIDGET_SIZE, Position = Settings.widgetPosition }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    tween(floatingWidget, { GroupTransparency = 0 }, 0.3)

    task.delay(0.3, function()
        if not isOpen then
            mainWindow.Visible = false
            backdrop.Visible = false
            mainWindow.Size = UDim2.new(0, WINDOW_BASE_SIZE.X, 0, WINDOW_BASE_SIZE.Y)
        end
    end)
end

closeButton.MouseButton1Click:Connect(closeMenu)
backdrop.MouseButton1Click:Connect(closeMenu)

-- Перетаскивание (общая функция)
local function makeDraggable(frame, handle, onEnd)
    local dragging = false
    local dragInput, dragStart, startPos
    local moved = false

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = input.Position
            startPos = frame.Position
            local conn
            conn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    conn:Disconnect()
                    if onEnd then onEnd(moved) end
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            if delta.Magnitude > 4 then moved = true end
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- Floating widget: клик открывает меню, перетаскивание перемещает и сохраняет позицию
makeDraggable(floatingWidget, widgetButton, function(moved)
    if not moved then
        openMenu()
    else
        Settings.widgetPosition = floatingWidget.Position
    end
end)

-- Главное окно перетаскивается за верхнюю панель
makeDraggable(mainWindow, topBar, nil)

----------------------------------------------------------------
-- 7. РАНТАЙМ MOTION BLUR (работает независимо от состояния GUI)
----------------------------------------------------------------

local blurEffect = Lighting:FindFirstChild("NeizMotionBlur")
if not blurEffect then
    blurEffect = new("BlurEffect", { Name = "NeizMotionBlur", Size = 0, Parent = Lighting })
end

local lastPosition = camera.CFrame.Position
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
-- ИНИЦИАЛИЗАЦИЯ
----------------------------------------------------------------
switchTab("MotionBlur")
applyAppearance()

print("[NeizMotion] loaded.")
