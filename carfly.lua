local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- !!! GITHUB RAW LINK !!!
local REPO_URL = "https://raw.githubusercontent.com/Poldi2007x/obobrick/main/" 

-- 1. Funktion: Auto/Teil holen
local function getMobileRoot()
    local player = Players.LocalPlayer
    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid")
    local root = char:WaitForChild("HumanoidRootPart")

    -- Immer Auto Spawn Befehl senden
    local remote = ReplicatedStorage:WaitForChild("GarageSpawnVehicle", 2)
    if remote then 
        remote:FireServer("Chassis", "Deja") 
    end
    
    task.wait(1)

    if hum.SeatPart then
        return hum.SeatPart 
    end

    warn("Sitz nicht erkannt! Bewege HumanoidRootPart...")
    return root
end

-- 2. Flug-Physik mit SANFTER LANDUNG
-- Neuer Parameter: isLanding (true/false)
local function flyTo(moverPart, targetPos, maxSpeed, bg, bv, isLanding)
    local arrived = false
    local connection
    
    connection = RunService.Heartbeat:Connect(function()
        if not moverPart or not moverPart.Parent then 
            if connection then connection:Disconnect() end
            return 
        end
        
        local currentPos = moverPart.Position
        local diff = targetPos - currentPos
        local dist = diff.Magnitude
        
        -- GESCHWINDIGKEITS-LOGIK
        local currentSpeed = maxSpeed
        
        if isLanding then
            -- Bremsweg beginnt bei 150 Studs Abstand
            local brakeDistance = 150
            if dist < brakeDistance then
                -- Wir berechnen einen Faktor von 0 bis 1
                local factor = dist / brakeDistance
                -- Die Geschwindigkeit wird langsamer, aber nie unter 15 (damit wir ankommen)
                currentSpeed = math.max(15, maxSpeed * factor)
            end
        end

        -- BEWEGUNG SETZEN
        bv.Velocity = diff.Unit * currentSpeed
        
        -- DREHUNG (Gyro) - Waagerecht bleiben
        local flatDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude
        
        if flatDist > 5 then
            -- Zum Ziel drehen, aber Y ignorieren (flach bleiben)
            bg.CFrame = CFrame.new(currentPos, Vector3.new(targetPos.X, currentPos.Y, targetPos.Z))
        else
            -- Wenn wir fast nur vertikal fallen: Ausrichtung beibehalten und gerade ziehen
            local _, rotY, _ = moverPart.CFrame:ToOrientation()
            bg.CFrame = CFrame.new(currentPos) * CFrame.fromOrientation(0, rotY, 0)
        end
        
        -- ANKUNFT CHECK
        -- Bei Landung sind wir strenger (5 studs), sonst 10
        local threshold = isLanding and 5 or 10
        if dist < threshold then 
            arrived = true
            connection:Disconnect()
        end
    end)
    
    repeat task.wait() until arrived or not moverPart.Parent
end

-- 3. Hauptfunktion
getgenv().startRoute = function(jsonFileName, speed)
    local moverPart = getMobileRoot()

    -- JSON Laden
    local routeData
    if jsonFileName:find(".json") then
        local url = REPO_URL .. jsonFileName
        print("Lade Route: " .. url)
        local success, response = pcall(function() return game:HttpGet(url) end)
        if not success then return warn("Fehler beim Laden von GitHub!", response) end
        local decodeSuccess, decoded = pcall(function() return HttpService:JSONDecode(response) end)
        if not decodeSuccess then return warn("JSON Fehler:", decoded) end
        routeData = decoded
    else
        routeData = HttpService:JSONDecode(jsonFileName)
    end

    -- Physik Setup
    for _, v in pairs(moverPart:GetChildren()) do
        if v:IsA("BodyGyro") or v:IsA("BodyVelocity") then v:Destroy() end
    end

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P = 3000; bg.D = 500
    bg.Parent = moverPart
    
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = moverPart

    -- Route abfahren
    print("Starte Route...")
    for i, point in ipairs(routeData) do
        if not moverPart.Parent then break end

        if point.type == "wait" then
            task.wait(point.time or 0.5)
        elseif point.type == "move" then
            local target = Vector3.new(point.x, point.y, point.z)
            
            if i == 1 then
                -- Start Manöver: Hoch -> Rüber -> Runter
                local startPos = moverPart.Position
                
                -- 1. Hoch (Schnell, keine Landung)
                flyTo(moverPart, Vector3.new(startPos.X, 300, startPos.Z), speed, bg, bv, false)
                
                -- 2. Rüber (Schnell, keine Landung)
                flyTo(moverPart, Vector3.new(target.X, 300, target.Z), speed, bg, bv, false)
                
                -- 3. Runter (SANFTE LANDUNG AKTIVIEREN)
                -- Hier setzen wir 'true' am Ende
                flyTo(moverPart, target, speed, bg, bv, true)
            else
                -- Normal weiter zu den nächsten Punkten (Schnell)
                flyTo(moverPart, target, speed, bg, bv, false)
            end
        end
    end
    
    if bg then bg:Destroy() end
    if bv then bv:Destroy() end
    print("Fertig!")
end

print("Geladen. Nutze: startRoute('Prison.json', 300)")
