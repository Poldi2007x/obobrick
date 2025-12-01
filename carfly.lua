--[[ 
    Speichere dieses Script auf GitHub als "carfly.lua" 
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- !!! HIER DEINEN GITHUB LINK ZUM ORDNER EINFÜGEN (muss mit / enden) !!!
-- Beispiel: "https://raw.githubusercontent.com/DeinName/DeinRepo/main/"
local REPO_URL = "https://github.com/Poldi2007x/obobrick/main/" 

-- Hilfsfunktion: Auto holen
local function getCar()
    local player = Players.LocalPlayer
    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid")

    if not hum.SeatPart then
        warn("Spawning Car...")
        local remote = ReplicatedStorage:WaitForChild("GarageSpawnVehicle", 5)
        if remote then remote:FireServer("Chassis", "Deja") end
        repeat task.wait(0.1) until hum.SeatPart
    end
    
    local vehicle = hum.SeatPart.Parent
    return vehicle.PrimaryPart or hum.SeatPart
end

-- Hilfsfunktion: Fliegen
local function flyTo(rootPart, targetPos, speed, bg, bv)
    local arrived = false
    local connection
    
    connection = RunService.Heartbeat:Connect(function()
        if not rootPart or not rootPart.Parent then 
            if connection then connection:Disconnect() end
            return 
        end
        
        local currentPos = rootPart.Position
        local diff = targetPos - currentPos
        local dist = diff.Magnitude
        
        bg.CFrame = CFrame.new(currentPos, targetPos)
        bv.Velocity = diff.Unit * speed
        
        if dist < 10 then -- Radius zum Ankommen
            arrived = true
            connection:Disconnect()
        end
    end)
    
    repeat task.wait() until arrived or not rootPart.Parent
end

-- HAUPTFUNKTION (Global verfügbar machen)
getgenv().startRoute = function(jsonFileName, speed)
    -- 1. JSON abrufen
    local routeData
    
    -- Prüfen, ob es eine URL/Dateiname ist oder direkter JSON Text
    if jsonFileName:find(".json") then
        local url = REPO_URL .. jsonFileName
        print("Lade Route von: " .. url)
        
        local success, response = pcall(function()
            return game:HttpGet(url)
        end)
        
        if not success then
            warn("Fehler beim Laden der Datei von GitHub: " .. tostring(response))
            return
        end
        
        routeData = HttpService:JSONDecode(response)
    else
        -- Falls du den JSON String direkt eingibst
        routeData = HttpService:JSONDecode(jsonFileName)
    end

    -- 2. Physik Setup
    local rootPart = getCar()
    
    -- Alte Gyros löschen falls vorhanden
    for _, v in pairs(rootPart:GetChildren()) do
        if v:IsA("BodyGyro") or v:IsA("BodyVelocity") then v:Destroy() end
    end

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 3000; bg.D = 500
    bg.Parent = rootPart
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = rootPart

    print("Starte Route mit Speed:", speed)

    -- 3. Route abfliegen
    for i, point in ipairs(routeData) do
        if point.type == "wait" then
            task.wait(point.time or 0.5)
        elseif point.type == "move" then
            local target = Vector3.new(point.x, point.y, point.z)
            
            if i == 1 then
                -- Erster Punkt Logik (Hoch -> Rüber -> Runter)
                local startPos = rootPart.Position
                -- A: Hoch (300)
                flyTo(rootPart, Vector3.new(startPos.X, 300, startPos.Z), speed, bg, bv)
                -- B: Rüber (300)
                flyTo(rootPart, Vector3.new(target.X, 300, target.Z), speed, bg, bv)
                -- C: Runter
                flyTo(rootPart, target, speed, bg, bv)
            else
                -- Restliche Punkte direkt
                flyTo(rootPart, target, speed, bg, bv)
            end
        end
    end
    
    -- Clean up
    bg:Destroy()
    bv:Destroy()
    print("Route fertig!")
end

print("CarFly Script geladen! Nutze: startRoute('prison.json', 300)")
