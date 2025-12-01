local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- !!! GITHUB RAW LINK !!!
local REPO_URL = "https://raw.githubusercontent.com/Poldi2007x/obobrick/main/" 

-- 1. Funktion: Auto finden (Erweiterte Logik: State & PlayerName)
local function getMobileRoot()
    local player = Players.LocalPlayer
    local myName = player.Name
    local char = player.Character or player.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    
    local vehicles = workspace:FindFirstChild("Vehicles")

    -- HILFSFUNKTION: Sucht dein Auto anhand des Namens im Sitz
    local function findMyCar()
        if not vehicles then return nil end
        for _, car in pairs(vehicles:GetChildren()) do
            -- 1. Hat das Auto den State mit deinem Namen?
            if car:FindFirstChild("_VehicleState_" .. myName) then
                -- 2. Steht dein Name im Sitz-Value?
                local seat = car:FindFirstChild("Seat")
                if seat and seat:FindFirstChild("PlayerName") then
                    if seat.PlayerName.Value == myName then
                        return car.PrimaryPart or seat -- Auto gefunden!
                    end
                end
            end
        end
        return nil
    end

    -- SCHRITT 1: Prüfen, ob wir schon sitzen
    local currentCarPart = findMyCar()
    if currentCarPart then
        print("Bereits im Auto gefunden: " .. currentCarPart.Parent.Name)
        return currentCarPart
    end

    -- SCHRITT 2: Falls nicht, neues Auto spawnen
    warn("Kein Auto erkannt. Sende Spawn-Befehl...")
    local remote = ReplicatedStorage:WaitForChild("GarageSpawnVehicle", 2)
    if remote then 
        remote:FireServer("Chassis", "Deja") 
    end
    
    -- SCHRITT 3: Warten bis das Auto da ist (Loop)
    -- Wir prüfen ca. 2 Sekunden lang, ob das Auto aufgetaucht ist
    for i = 1, 20 do
        task.wait(0.1) -- Warte kurz
        currentCarPart = findMyCar() -- Suche erneut
        if currentCarPart then
            print("Auto erfolgreich gespawnt und erkannt!")
            return currentCarPart
        end
    end

    -- NOTFALL: Falls das Spawnen nicht geklappt hat
    warn("Konnte Sitz nicht verifizieren! Nutze Fallback (HumanoidRootPart).")
    return root
end

-- 2. Flug-Physik mit SANFTER LANDUNG & WAAGERECHTEM FLUG
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
        
        -- GESCHWINDIGKEITS-LOGIK (Bremsen bei Landung)
        local currentSpeed = maxSpeed
        if isLanding then
            local brakeDistance = 150
            if dist < brakeDistance then
                local factor = dist / brakeDistance
                currentSpeed = math.max(15, maxSpeed * factor)
            end
        end

        -- BEWEGUNG SETZEN
        bv.Velocity = diff.Unit * currentSpeed
        
        -- DREHUNG (Gyro) - Waagerecht bleiben (keine Rakete)
        local flatDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude
        
        if flatDist > 5 then
            -- Zum Ziel drehen, aber Y ignorieren (flach bleiben)
            bg.CFrame = CFrame.new(currentPos, Vector3.new(targetPos.X, currentPos.Y, targetPos.Z))
        else
            -- Wenn wir fast nur vertikal fallen/steigen: Ausrichtung beibehalten
            local _, rotY, _ = moverPart.CFrame:ToOrientation()
            bg.CFrame = CFrame.new(currentPos) * CFrame.fromOrientation(0, rotY, 0)
        end
        
        -- ANKUNFT CHECK
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
