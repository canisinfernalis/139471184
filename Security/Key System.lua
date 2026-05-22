-- Services
loadstring('function LPH_NO_VIRTUALIZE(f) return f end;\n')()

local cloneref = cloneref or function(a) return a end
local ContentProvider = cloneref(game:GetService("ContentProvider"))
local Players = cloneref(game:GetService("Players"))
local TweenService = cloneref(game:GetService("TweenService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local RunService = cloneref(game:GetService("RunService"))
local setclipboard = setclipboard or toclipboard or set_clipboard or ((type(Clipboard) == "table") and Clipboard.set)
local getgenv = getgenv or function() return shared end

local function randomName(length)
    local chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local result = ''
    for i = 1, length or 12 do
        local idx = math.random(1, #chars)
        result = result .. chars:sub(idx, idx)
    end
    return result
end

-- Config
local DiscordLink = "https://discord.gg/pW2X3GtveU"
local KeyFileName = "Midgard_Key.txt"
local LuarmorAPI = loadstring(game:HttpGet('https://sdkapi-public.luarmor.net/library.lua'))()

-- Games
local GameIDs = {
    [9186719164] = "d4cea5fdd1f959389cfb728aacfacdb9", -- Sailor Piece
}

-- Links
local GlobalLinks = {
    Linkvertise = "https://ads.luarmor.net/get_key?for=Midgard-NVketkFqfmrr",
    LootLabs = "https://ads.luarmor.net/get_key?for=Midgard-EBpaQhGvGeTo",
    WorkInk = "https://ads.luarmor.net/get_key?for=Midgard-FSTkgdXXOuaC"
}

local DefaultScriptID = "0e0c8f0d265f4b685b0c95c65214772b"
local ActiveScriptID = GameIDs[game.GameId] or DefaultScriptID

-- Key Storage
local function ensureFolder(path)
    if not (isfolder and makefolder) then return end
    local segments = path:split("/")
    local current = ""
    for _, segment in ipairs(segments) do
        current = current .. segment .. "/"
        if not isfolder(current) then makefolder(current) end
    end
end

local function getSavedKey()
    if not isfile then return nil end
    local success, result = pcall(function()
        if isfile("Midgard/Key/" .. KeyFileName) then
            return readfile("Midgard/Key/" .. KeyFileName)
        end
        return nil
    end)
    if success and result and #result > 5 then
        return result:match("^%s*(.-)%s*$")
    end
    return nil
end

local function saveKey(keyToSave)
    if not writefile then return end
    pcall(function()
        ensureFolder("Midgard/Key")
        writefile("Midgard/Key/" .. KeyFileName, keyToSave)
    end)
end

local function deleteSavedKey()
    if not delfile then return end
    pcall(function()
        if isfile and isfile("Midgard/Key/" .. KeyFileName) then
            delfile("Midgard/Key/" .. KeyFileName)
        end
    end)
end

-- Auto Auth
local function tryAutoAuth()
    local envKey = script_key or _G.script_key or _G['%USER_KEY%'] or getgenv().script_key or _G.LuarmorKey or _G.luarmor_key
    local savedKey = getSavedKey()
    
    if type(envKey) ~= 'string' then envKey = nil end
    if type(savedKey) ~= 'string' then savedKey = nil end
    if envKey and (envKey:find('%%') or #envKey < 10) then envKey = nil end
    
    local finalKey = envKey or savedKey
    if not finalKey then return false end
    
    -- Clean key
    finalKey = finalKey:gsub("%s+", "")
    if #finalKey < 10 then return false end
    
    LuarmorAPI.script_id = ActiveScriptID
    local success, status = pcall(function()
        return LuarmorAPI.check_key(finalKey)
    end)
    
    if not success or not status then return false end
    
    if status.code == 'KEY_VALID' then
        getgenv().script_key = finalKey
        _G.script_key = finalKey
        saveKey(finalKey)
        local okLoad, loadErr = pcall(function()
            LuarmorAPI.load_script()
        end)
        if okLoad then
            return true
        end
        warn("[Midgard KeySystem] Failed to load script: " .. tostring(loadErr))
        return false
    else
        deleteSavedKey()
        return false
    end
end

-- UI Guard
if getgenv()._MIDGARD_UI_LOADED then return end
getgenv()._MIDGARD_UI_LOADED = true

-- Auto Load
if tryAutoAuth() then return end

-- Helpers
local function applyTween(obj, props, duration)
    local info = TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local tween = TweenService:Create(obj, info, props)
    tween:Play()
    return tween
end

local function setLucideIcon(imageLabel, iconName)
    imageLabel.ImageTransparency = 0
    if iconName == "loader" then imageLabel.Image = "rbxassetid://84669538604052"
    elseif iconName == "check" then imageLabel.Image = "rbxassetid://136734716346836"
    elseif iconName == "x" then imageLabel.Image = "rbxassetid://139251575138122"
    elseif iconName == "clock" then imageLabel.Image = "rbxassetid://108433892037692"
    else imageLabel.ImageTransparency = 1 end
end

task.spawn(function()
    pcall(function()
        ContentProvider:PreloadAsync({
            "rbxassetid://84669538604052",
            "rbxassetid://136734716346836",
            "rbxassetid://139251575138122",
            "rbxassetid://108433892037692",
        })
    end)
end)

-- Theme
local BackgroundColor = Color3.fromRGB(15, 15, 15)
local MainColor       = Color3.fromRGB(32, 32, 32)
local YellowColor     = Color3.fromHex("ffff00")
local OutlineColor    = Color3.fromRGB(40, 40, 40)
local FontColor       = Color3.fromRGB(255, 255, 255)
local DarkFontColor   = Color3.fromRGB(10, 10, 10)
local KeySystemFont   = Enum.Font.Gotham
local LogoID          = "rbxassetid://86720583626882"

-- Build
local ScreenGui          = Instance.new("ScreenGui")
local MainFrame          = Instance.new("Frame")
local UICorner_Main      = Instance.new("UICorner")
local UIStroke_Main      = Instance.new("UIStroke")
local Header             = Instance.new("Frame")
local Logo               = Instance.new("ImageLabel")
local Title              = Instance.new("TextLabel")
local CloseButton        = Instance.new("TextButton")
local KeyInput           = Instance.new("TextBox")
local UICorner_Input     = Instance.new("UICorner")
local UIStroke_Input     = Instance.new("UIStroke")
local UIPadding_Input    = Instance.new("UIPadding")
local SubmitButton       = Instance.new("TextButton")
local UICorner_Submit    = Instance.new("UICorner")
local ButtonContainer    = Instance.new("Frame")
local UIListLayout_Buttons = Instance.new("UIListLayout")
local LinkvertiseButton  = Instance.new("TextButton")
local LootLabsButton     = Instance.new("TextButton")
local WorkInkButton      = Instance.new("TextButton")
local UICorner_Linkvertise = Instance.new("UICorner")
local UICorner_LootLabs  = Instance.new("UICorner")
local UICorner_WorkInk   = Instance.new("UICorner")

ScreenGui.Name = randomName(16)
local _ok, _parent = pcall(function() return game:GetService("CoreGui") end)
if protect_gui then protect_gui(ScreenGui) end
ScreenGui.Parent = _ok and _parent or Players.LocalPlayer:WaitForChild("PlayerGui")
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

MainFrame.Name = randomName(12); MainFrame.Parent = ScreenGui; MainFrame.BackgroundColor3 = BackgroundColor
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5); MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0); MainFrame.Size = UDim2.new(0, 350, 0, 219); MainFrame.ClipsDescendants = true
UICorner_Main.CornerRadius = UDim.new(0, 8); UICorner_Main.Parent = MainFrame
UIStroke_Main.Color = OutlineColor; UIStroke_Main.Thickness = 1; UIStroke_Main.Parent = MainFrame

Header.Name = "Header"; Header.Parent = MainFrame; Header.BackgroundTransparency = 1; Header.Position = UDim2.new(0, 0, 0, 17); Header.Size = UDim2.new(1, 0, 0, 30)
local HeaderContent = Instance.new("Frame", Header); HeaderContent.Name = "HeaderContent"; HeaderContent.BackgroundTransparency = 1; HeaderContent.Size = UDim2.new(1, 0, 1, 0)
local UIListLayout_Header = Instance.new("UIListLayout", HeaderContent); UIListLayout_Header.FillDirection = Enum.FillDirection.Horizontal; UIListLayout_Header.HorizontalAlignment = Enum.HorizontalAlignment.Center; UIListLayout_Header.VerticalAlignment = Enum.VerticalAlignment.Center; UIListLayout_Header.Padding = UDim.new(0, 10)

Logo.Name = "Logo"; Logo.Parent = HeaderContent; Logo.BackgroundTransparency = 1; Logo.Size = UDim2.new(0, 30, 0, 30); Logo.Image = LogoID
Title.Name = "Title"; Title.Parent = HeaderContent; Title.BackgroundTransparency = 1; Title.Size = UDim2.new(0, 85, 0, 30); Title.Font = Enum.Font.GothamBlack; Title.Text = "Midgard"; Title.TextColor3 = FontColor; Title.TextSize = 20; Title.TextXAlignment = Enum.TextXAlignment.Left

CloseButton.Name = "CloseButton"; CloseButton.Parent = MainFrame; CloseButton.BackgroundTransparency = 1; CloseButton.AnchorPoint = Vector2.new(1, 0); CloseButton.Position = UDim2.new(1, -5, 0, 5); CloseButton.Size = UDim2.new(0, 24, 0, 24); CloseButton.Text = ""; CloseButton.AutoButtonColor = false
local CloseCorner = Instance.new("UICorner", CloseButton); CloseCorner.CornerRadius = UDim.new(1, 0)
local x1 = Instance.new("Frame", CloseButton); x1.Name = "CloseIconPart1"; x1.Size = UDim2.new(0, 2, 0, 14); x1.Position = UDim2.new(0.5, 0, 0.5, 0); x1.AnchorPoint = Vector2.new(0.5, 0.5); x1.Rotation = 45; x1.BackgroundColor3 = Color3.fromRGB(150, 150, 150); x1.BorderSizePixel = 0
local x2 = Instance.new("Frame", CloseButton); x2.Name = "CloseIconPart2"; x2.Size = UDim2.new(0, 2, 0, 14); x2.Position = UDim2.new(0.5, 0, 0.5, 0); x2.AnchorPoint = Vector2.new(0.5, 0.5); x2.Rotation = -45; x2.BackgroundColor3 = Color3.fromRGB(150, 150, 150); x2.BorderSizePixel = 0

local Description = Instance.new("TextButton"); Description.Name = "Description"; Description.Parent = MainFrame; Description.BackgroundTransparency = 1; Description.Position = UDim2.new(0, 0, 0, 52); Description.Size = UDim2.new(1, 0, 0, 20); Description.Font = KeySystemFont; Description.RichText = true; Description.Text = "Need help? Join our <font color=\"rgb(255, 255, 0)\">Discord</font> community"; Description.TextColor3 = Color3.fromRGB(180, 180, 180); Description.TextSize = 12; Description.TextWrapped = true; Description.TextXAlignment = Enum.TextXAlignment.Center; Description.AutoButtonColor = false

KeyInput.Name = "KeyInput"; KeyInput.Parent = MainFrame; KeyInput.BackgroundColor3 = BackgroundColor; KeyInput.Position = UDim2.new(0, 23, 0, 77); KeyInput.Size = UDim2.new(1, -46, 0, 35); KeyInput.Font = KeySystemFont; KeyInput.PlaceholderText = "Enter your key"; KeyInput.PlaceholderColor3 = Color3.fromRGB(110, 110, 110); KeyInput.Text = ""; KeyInput.TextColor3 = FontColor; KeyInput.TextSize = 14; KeyInput.ClipsDescendants = true
UIPadding_Input.Parent = KeyInput; UIPadding_Input.PaddingLeft = UDim.new(0, 10); UIPadding_Input.PaddingRight = UDim.new(0, 10)
UICorner_Input.CornerRadius = UDim.new(0, 8); UICorner_Input.Parent = KeyInput
UIStroke_Input.Color = Color3.fromRGB(70, 70, 70); UIStroke_Input.Thickness = 1; UIStroke_Input.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; UIStroke_Input.Parent = KeyInput

SubmitButton.Name = "SubmitButton"; SubmitButton.Parent = MainFrame; SubmitButton.BackgroundColor3 = YellowColor; SubmitButton.Position = UDim2.new(0, 23, 0, 122); SubmitButton.Size = UDim2.new(1, -46, 0, 32); SubmitButton.Font = KeySystemFont; SubmitButton.Text = "Redeem Key"; SubmitButton.AutoButtonColor = false; SubmitButton.TextColor3 = DarkFontColor; SubmitButton.TextSize = 16
UICorner_Submit.CornerRadius = UDim.new(0, 8); UICorner_Submit.Parent = SubmitButton

local LoadingIcon = Instance.new("ImageLabel", SubmitButton); LoadingIcon.Name = "LoadingIcon"; LoadingIcon.AnchorPoint = Vector2.new(0.5, 0.5); LoadingIcon.BackgroundTransparency = 1; LoadingIcon.Position = UDim2.new(0.5, 0, 0.5, 0); LoadingIcon.Size = UDim2.new(0, 22, 0, 22); LoadingIcon.ZIndex = 10; LoadingIcon.Visible = false; LoadingIcon.ImageColor3 = DarkFontColor; LoadingIcon.ImageTransparency = 1; setLucideIcon(LoadingIcon, "loader")
local CheckIcon  = Instance.new("ImageLabel", SubmitButton); CheckIcon.Name  = "CheckIcon";  CheckIcon.AnchorPoint  = Vector2.new(0.5, 0.5); CheckIcon.BackgroundTransparency  = 1; CheckIcon.Position  = UDim2.new(0.5, 0, 0.5, 0); CheckIcon.Size  = UDim2.new(0, 24, 0, 24); CheckIcon.ZIndex  = 5; CheckIcon.Visible  = false; CheckIcon.ImageColor3  = DarkFontColor; CheckIcon.ImageTransparency  = 1; setLucideIcon(CheckIcon,  "check")
local XIcon      = Instance.new("ImageLabel", SubmitButton); XIcon.Name      = "XIcon";      XIcon.AnchorPoint      = Vector2.new(0.5, 0.5); XIcon.BackgroundTransparency      = 1; XIcon.Position      = UDim2.new(0.5, 0, 0.5, 0); XIcon.Size      = UDim2.new(0, 20, 0, 20); XIcon.ZIndex      = 5; XIcon.Visible      = false; XIcon.ImageColor3      = DarkFontColor; XIcon.ImageTransparency      = 1; setLucideIcon(XIcon,      "x")
local TimerIcon  = Instance.new("ImageLabel", SubmitButton); TimerIcon.Name  = "TimerIcon";  TimerIcon.AnchorPoint  = Vector2.new(0.5, 0.5); TimerIcon.BackgroundTransparency  = 1; TimerIcon.Position  = UDim2.new(0.5, 0, 0.5, 0); TimerIcon.Size  = UDim2.new(0, 20, 0, 20); TimerIcon.ZIndex  = 5; TimerIcon.Visible  = false; TimerIcon.ImageColor3  = DarkFontColor; TimerIcon.ImageTransparency  = 1; setLucideIcon(TimerIcon,  "clock")

ButtonContainer.Name = "ButtonContainer"; ButtonContainer.Parent = MainFrame; ButtonContainer.BackgroundTransparency = 1; ButtonContainer.Position = UDim2.new(0, 23, 0, 164); ButtonContainer.Size = UDim2.new(1, -46, 0, 32)
UIListLayout_Buttons.Parent = ButtonContainer; UIListLayout_Buttons.FillDirection = Enum.FillDirection.Horizontal; UIListLayout_Buttons.Padding = UDim.new(0, 10); UIListLayout_Buttons.SortOrder = Enum.SortOrder.LayoutOrder

LinkvertiseButton.Name = "LinkvertiseButton"; LinkvertiseButton.Parent = ButtonContainer; LinkvertiseButton.BackgroundColor3 = MainColor; LinkvertiseButton.Size = UDim2.new(0.333, -7, 1, 0); LinkvertiseButton.Text = ""; LinkvertiseButton.LayoutOrder = 1; LinkvertiseButton.AutoButtonColor = false; UICorner_Linkvertise.CornerRadius = UDim.new(0, 8); UICorner_Linkvertise.Parent = LinkvertiseButton
local LinkvertiseContent = Instance.new("Frame", LinkvertiseButton); LinkvertiseContent.Name = "Content"; LinkvertiseContent.BackgroundTransparency = 1; LinkvertiseContent.Size = UDim2.new(1, 0, 1, 0)
local LinkvertiseLayout = Instance.new("UIListLayout", LinkvertiseContent); LinkvertiseLayout.FillDirection = Enum.FillDirection.Horizontal; LinkvertiseLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; LinkvertiseLayout.VerticalAlignment = Enum.VerticalAlignment.Center; LinkvertiseLayout.Padding = UDim.new(0, 4)
local LinkvertiseIcon = Instance.new("ImageLabel", LinkvertiseContent); LinkvertiseIcon.Name = "Icon"; LinkvertiseIcon.BackgroundTransparency = 1; LinkvertiseIcon.Size = UDim2.new(0, 18, 0, 18); LinkvertiseIcon.Image = "rbxassetid://138427217607086"; LinkvertiseIcon.ImageColor3 = Color3.fromRGB(255, 255, 255); LinkvertiseIcon.ScaleType = Enum.ScaleType.Fit
local LinkvertiseText = Instance.new("TextLabel", LinkvertiseContent); LinkvertiseText.Name = "Text"; LinkvertiseText.BackgroundTransparency = 1; LinkvertiseText.Size = UDim2.new(0, 0, 1, 0); LinkvertiseText.AutomaticSize = Enum.AutomaticSize.X; LinkvertiseText.Font = Enum.Font.GothamBold; LinkvertiseText.Text = "Linkvertise"; LinkvertiseText.TextColor3 = FontColor; LinkvertiseText.TextSize = 13

LootLabsButton.Name = "LootLabsButton"; LootLabsButton.Parent = ButtonContainer; LootLabsButton.BackgroundColor3 = MainColor; LootLabsButton.Size = UDim2.new(0.334, -6, 1, 0); LootLabsButton.Text = ""; LootLabsButton.LayoutOrder = 2; LootLabsButton.AutoButtonColor = false; UICorner_LootLabs.CornerRadius = UDim.new(0, 8); UICorner_LootLabs.Parent = LootLabsButton
local LootLabsContent = Instance.new("Frame", LootLabsButton); LootLabsContent.Name = "Content"; LootLabsContent.BackgroundTransparency = 1; LootLabsContent.Size = UDim2.new(1, 0, 1, 0)
local LootLabsLayout = Instance.new("UIListLayout", LootLabsContent); LootLabsLayout.FillDirection = Enum.FillDirection.Horizontal; LootLabsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; LootLabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center; LootLabsLayout.Padding = UDim.new(0, 4)
local LootLabsIcon = Instance.new("ImageLabel", LootLabsContent); LootLabsIcon.Name = "Icon"; LootLabsIcon.BackgroundTransparency = 1; LootLabsIcon.Size = UDim2.new(0, 18, 0, 18); LootLabsIcon.Image = "rbxassetid://77347832178479"; LootLabsIcon.ImageColor3 = Color3.fromRGB(255, 255, 255); LootLabsIcon.ScaleType = Enum.ScaleType.Fit
local LootLabsText = Instance.new("TextLabel", LootLabsContent); LootLabsText.Name = "Text"; LootLabsText.BackgroundTransparency = 1; LootLabsText.Size = UDim2.new(0, 0, 1, 0); LootLabsText.AutomaticSize = Enum.AutomaticSize.X; LootLabsText.Font = Enum.Font.GothamBold; LootLabsText.Text = "LootLabs"; LootLabsText.TextColor3 = FontColor; LootLabsText.TextSize = 13

WorkInkButton.Name = "WorkInkButton"; WorkInkButton.Parent = ButtonContainer; WorkInkButton.BackgroundColor3 = MainColor; WorkInkButton.Size = UDim2.new(0.333, -7, 1, 0); WorkInkButton.Text = ""; WorkInkButton.LayoutOrder = 3; WorkInkButton.AutoButtonColor = false; UICorner_WorkInk.CornerRadius = UDim.new(0, 8); UICorner_WorkInk.Parent = WorkInkButton
local WorkInkContent = Instance.new("Frame", WorkInkButton); WorkInkContent.Name = "Content"; WorkInkContent.BackgroundTransparency = 1; WorkInkContent.Size = UDim2.new(1, 0, 1, 0)
local WorkInkLayout = Instance.new("UIListLayout", WorkInkContent); WorkInkLayout.FillDirection = Enum.FillDirection.Horizontal; WorkInkLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; WorkInkLayout.VerticalAlignment = Enum.VerticalAlignment.Center; WorkInkLayout.Padding = UDim.new(0, 4)
local WorkInkIcon = Instance.new("ImageLabel", WorkInkContent); WorkInkIcon.Name = "Icon"; WorkInkIcon.BackgroundTransparency = 1; WorkInkIcon.Size = UDim2.new(0, 18, 0, 18); WorkInkIcon.Image = "rbxassetid://137084367454843"; WorkInkIcon.ImageColor3 = Color3.fromRGB(255, 255, 255); WorkInkIcon.ScaleType = Enum.ScaleType.Fit
local WorkInkText = Instance.new("TextLabel", WorkInkContent); WorkInkText.Name = "Text"; WorkInkText.BackgroundTransparency = 1; WorkInkText.Size = UDim2.new(0, 0, 1, 0); WorkInkText.AutomaticSize = Enum.AutomaticSize.X; WorkInkText.Font = Enum.Font.GothamBold; WorkInkText.Text = "Work.ink"; WorkInkText.TextColor3 = FontColor; WorkInkText.TextSize = 13

-- Buttons
if not GlobalLinks.Linkvertise then LinkvertiseButton.Visible = false end
if not GlobalLinks.LootLabs then LootLabsButton.Visible = false end
if not GlobalLinks.WorkInk then WorkInkButton.Visible = false end


-- Interactions
local dragging, dragInput, dragStart, startPos
MainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
MainFrame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

CloseButton.MouseEnter:Connect(function()
    applyTween(CloseButton, { BackgroundTransparency = 0.9 }, 0.2)
    applyTween(x1, { BackgroundColor3 = Color3.fromRGB(255, 255, 255) }, 0.2)
    applyTween(x2, { BackgroundColor3 = Color3.fromRGB(255, 255, 255) }, 0.2)
end)
CloseButton.MouseLeave:Connect(function()
    applyTween(CloseButton, { BackgroundTransparency = 1 }, 0.2)
    applyTween(x1, { BackgroundColor3 = Color3.fromRGB(150, 150, 150) }, 0.2)
    applyTween(x2, { BackgroundColor3 = Color3.fromRGB(150, 150, 150) }, 0.2)
end)

-- Ad Buttons
local function setupAdButton(button, url)
    if not url then return end
    button.MouseButton1Click:Connect(function()
        if setclipboard then setclipboard(url) end
        local textLabel = button.Content.Text
        local old = textLabel.Text
        textLabel.Text = "Copied!"
        task.delay(1.5, function() textLabel.Text = old end)
    end)
end

setupAdButton(LinkvertiseButton, GlobalLinks.Linkvertise)
setupAdButton(LootLabsButton, GlobalLinks.LootLabs)
setupAdButton(WorkInkButton, GlobalLinks.WorkInk)

Description.MouseButton1Click:Connect(function()
    if setclipboard then setclipboard(DiscordLink) end
    local original = Description.Text
    Description.Text = original:gsub(">Discord<", ">Copied!<")
    task.delay(1.5, function() Description.Text = original end)
end)

CloseButton.MouseButton1Click:Connect(function()
    getgenv()._MIDGARD_UI_LOADED = nil
    ScreenGui:Destroy()
end)


-- Redeem
local isVerifying = false

local startLoading = LPH_NO_VIRTUALIZE(function()
    SubmitButton.TextTransparency = 1
    LoadingIcon.Visible = true
    applyTween(LoadingIcon, { ImageTransparency = 0 }, 0.3)
    task.spawn(function()
        while LoadingIcon.Visible do
            LoadingIcon.Rotation = LoadingIcon.Rotation + 4
            RunService.RenderStepped:Wait()
        end
    end)
end)

local stopLoading = LPH_NO_VIRTUALIZE(function()
    applyTween(LoadingIcon, { ImageTransparency = 1 }, 0.3)
    task.delay(0.3, function() LoadingIcon.Visible = false end)
end)

local showFeedback = LPH_NO_VIRTUALIZE(function(icon, originalText)
    stopLoading()
    SubmitButton.TextTransparency = 1
    icon.Visible = true
    applyTween(icon, { ImageTransparency = 0 }, 0.3)
    task.delay(1.5, function()
        applyTween(icon, { ImageTransparency = 1 }, 0.3)
        applyTween(SubmitButton, { TextTransparency = 0 }, 0.3)
        task.delay(0.3, function()
            icon.Visible = false
            SubmitButton.Text = originalText
            isVerifying = false
        end)
    end)
end)

SubmitButton.MouseButton1Click:Connect(function()
    if isVerifying then return end

    local key_digitada = KeyInput.Text:gsub("%s+", "")
    if key_digitada == "" then
        isVerifying = true
        local oldText = SubmitButton.Text
        SubmitButton.Text = "Enter a key first!"
        task.delay(1.5, function() SubmitButton.Text = oldText; isVerifying = false end)
        return
    end

    isVerifying = true
    local originalText = SubmitButton.Text
    startLoading()

    task.spawn(function()
        LuarmorAPI.script_id = ActiveScriptID
        local ok, status = pcall(function()
            return LuarmorAPI.check_key(key_digitada)
        end)

        if not ok then
            stopLoading()
            isVerifying = false
            warn("[Midgard KeySystem] Verification failed.")
            return
        end

        if status.code == "KEY_VALID" then
            stopLoading()
            SubmitButton.TextTransparency = 1
            CheckIcon.Visible = true
            applyTween(CheckIcon, { ImageTransparency = 0 }, 0.3)
            saveKey(key_digitada)
            getgenv().script_key = key_digitada
            _G.script_key = key_digitada
            task.wait(1)
            getgenv()._MIDGARD_UI_LOADED = nil
            ScreenGui:Destroy()
            local okLoad, loadErr = pcall(function()
                LuarmorAPI.load_script()
            end)
            if not okLoad then
                warn("[Midgard KeySystem] Failed to load script: " .. tostring(loadErr))
            end
        else
            if status.code == "KEY_EXPIRED" then
                showFeedback(TimerIcon, originalText)
            elseif status.code == "KEY_HWID_LOCKED" then
                showFeedback(XIcon, originalText)
                SubmitButton.Text = "HWID Locked"
            elseif status.code == "KEY_BANNED" then
                showFeedback(XIcon, originalText)
                SubmitButton.Text = "Key Banned"
            elseif status.code == "KEY_INCORRECT" then
                showFeedback(XIcon, originalText)
                SubmitButton.Text = "Key Not Found"
            else
                showFeedback(XIcon, originalText)
            end
        end
    end)
end)


-- Intro
local targetSize = UDim2.new(0, 350, 0, 219)
local startSize  = UDim2.new(0, 280, 0, 175)
MainFrame.Size = startSize
MainFrame.BackgroundTransparency = 1; UIStroke_Main.Transparency = 1

for _, v in ipairs(MainFrame:GetDescendants()) do
    if v.Name:find("Icon") or v.Name:find("Line") then continue end
    if v:IsA("TextLabel") or v:IsA("TextBox") or v:IsA("TextButton") then v.TextTransparency = 1
    elseif v:IsA("ImageLabel") then v.ImageTransparency = 1
    elseif v:IsA("Frame") and v ~= MainFrame then v.BackgroundTransparency = 1 end
end

applyTween(MainFrame, { Size = targetSize, BackgroundTransparency = 0 }, 0.8)
applyTween(UIStroke_Main, { Transparency = 0 }, 0.8)

for _, v in ipairs(MainFrame:GetDescendants()) do
    if v.Name:find("Icon") or v.Name:find("Line") then continue end
    task.spawn(function()
        if v:IsA("TextLabel") or v:IsA("TextBox") or v:IsA("TextButton") then applyTween(v, { TextTransparency = 0 }, 0.8)
        elseif v:IsA("ImageLabel") then applyTween(v, { ImageTransparency = 0 }, 0.8) end
        if v:IsA("TextBox") or (v:IsA("TextButton") and v.Name ~= "CloseButton" and v.Name ~= "Description") then applyTween(v, { BackgroundTransparency = 0 }, 0.8) end
    end)
end
