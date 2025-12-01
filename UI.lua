local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

-- 1. LADE DIE MOVEMENT LOGIK VON GITHUB
-- Das lädt deine Datei 1 (Movement.lua) automatisch
pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Poldi2007x/obobrick/main/Movement.lua"))()
end)

-- 2. DAS UI STARTEN
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ObobrickUI"
if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
ScreenGui.Parent = CoreGui

-- Farben
local Colors = {Bg = Color3.fromRGB(25, 25, 30), Accent = Color3.fromRGB(0, 120, 215), Text = Color3.fromRGB(255, 255, 255)}

-- Main Frame
local Main = Instance.new("Frame", ScreenGui)
Main.Size = UDim2.new(0, 500, 0, 350)
Main.Position = UDim2.new(0.5, -250, 0.5, -175)
Main.BackgroundColor3 = Colors.Bg
Main.Active = true
Main.Draggable = true

local Title = Instance.new("TextLabel", Main)
Title.Text = "OBOBRICK MANAGER"
Title.Size = UDim2.new(1, 0, 0, 40)
Title.BackgroundColor3 = Colors.Accent
Title.TextColor3 = Colors.Text
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18

-- Scroll Container
local Scroll = Instance.new("ScrollingFrame", Main)
Scroll.Size = UDim2.new(1, -20, 1, -50)
Scroll.Position = UDim2.new(0, 10, 0, 45)
Scroll.BackgroundTransparency = 1
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

local Layout = Instance.new("UIListLayout", Scroll)
Layout.Padding = UDim.new(0, 8)

-- Helper: Button erstellen
local function createBtn(text, func)
    local btn = Instance.new("TextButton", Scroll)
    btn.Size = UDim2.new(1, 0, 0, 35)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    btn.TextColor3 = Colors.Text
    btn.Text = text
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 14
    local c = Instance.new("UICorner", btn); c.CornerRadius = UDim.new(0, 6)
    
    btn.MouseButton1Click:Connect(func)
    return btn
end

-- SECTION: ROUTES
local Label = Instance.new("TextLabel", Scroll)
Label.Text = "Available Routes (GitHub)"
Label.Size = UDim2.new(1, 0, 0, 25)
Label.BackgroundTransparency = 1
Label.TextColor3 = Color3.fromRGB(150, 150, 150)
Label.Font = Enum.Font.GothamBold
Label.TextSize = 14

-- Routen von GitHub laden und Buttons erstellen
task.spawn(function()
    local url = "https://api.github.com/repos/Poldi2007x/obobrick/contents/"
    local success, res = pcall(function() return game:HttpGet(url) end)
    
    if success then
        local files = HttpService:JSONDecode(res)
        for _, file in pairs(files) do
            if file.name:sub(-5) == ".json" then
                createBtn("Start Route: " .. file.name, function()
                    if getgenv().startRoute then
                        getgenv().startRoute(file.name, 300) -- Default Speed 300
                    end
                end)
            end
        end
    else
        createBtn("Manual Start: Prison.json", function()
            getgenv().startRoute("Prison.json", 300)
        end)
    end
end)

-- SECTION: EXTRAS
local Label2 = Label:Clone(); Label2.Parent = Scroll; Label2.Text = "Movement & Visuals"

createBtn("Toggle Fly (WASD)", function()
    -- Simple Fly Toggle Logic
    local plr = game.Players.LocalPlayer
    local mouse = plr:GetMouse()
    local root = plr.Character:WaitForChild("HumanoidRootPart")
    if root:FindFirstChild("FlyVelocity") then
        root.FlyVelocity:Destroy()
        root.FlyGyro:Destroy()
    else
        local bv = Instance.new("BodyVelocity", root); bv.Name = "FlyVelocity"
        bv.MaxForce = Vector3.new(math.huge,math.huge,math.huge)
        local bg = Instance.new("BodyGyro", root); bg.Name = "FlyGyro"
        bg.MaxTorque = Vector3.new(math.huge,math.huge,math.huge)
        
        task.spawn(function()
            while root:FindFirstChild("FlyVelocity") do
                bg.CFrame = workspace.CurrentCamera.CFrame
                bv.Velocity = workspace.CurrentCamera.CFrame.LookVector * 100
                task.wait()
            end
        end)
    end
end)

createBtn("Infinite Jump", function()
    game:GetService("UserInputService").JumpRequest:Connect(function()
        game.Players.LocalPlayer.Character.Humanoid:ChangeState("Jumping")
    end)
end)

createBtn("Freecam (Shift+P)", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/DUR5/Freecam/main/Freecam.lua"))()
end)

createBtn("Fullbright", function()
    local l = game.Lighting
    l.Brightness = 2; l.ClockTime = 14; l.FogEnd = 100000; l.GlobalShadows = false
end)

-- Close Button
local Close = Instance.new("TextButton", Main)
Close.Text = "X"
Close.Size = UDim2.new(0, 40, 0, 40)
Close.Position = UDim2.new(1, -40, 0, 0)
Close.BackgroundTransparency = 1
Close.TextColor3 = Colors.Text
Close.Font = Enum.Font.GothamBold
Close.TextSize = 18
Close.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)
