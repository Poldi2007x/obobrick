local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- !!! GITHUB RAW LINK !!!
local REPO_URL = "https://raw.githubusercontent.com/Poldi2007x/obobrick/main/" 

-- -------------------------------------------------------------------------
-- 1. FLUG-PHYSIK (Bleibt gleich)
-- -------------------------------------------------------------------------
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
        
        -- Speed Control
        local currentSpeed = maxSpeed
        if isLanding then
            local brakeDistance = 150
            if dist < brakeDistance then
                local factor = dist / brakeDistance
                currentSpeed = math.max(15, maxSpeed * factor)
            end
        end

        bv.Velocity = diff.Unit * currentSpeed
        
        -- Gyro Control
        local flatDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude
        if flatDist > 5 then
            bg.CFrame = CFrame.new(currentPos, Vector3.new(targetPos.X, currentPos.Y, targetPos.Z))
        else
            local _, rotY, _ = moverPart.CFrame:ToOrientation()
            bg.CFrame = CFrame.new(currentPos) * CFrame.fromOrientation(0, rotY, 0)
        end
        
        local threshold = isLanding and 5 or 10
        if dist < threshold then 
            arrived = true
            connection:Disconnect()
        end
    end)
    
    repeat task.wait() until arrived or not moverPart.Parent
end

-- -------------------------------------------------------------------------
-- 2. STRENGE AUTO-SUCHE (Finden -> Hinfliegen -> Einsteigen)
-- -------------------------------------------------------------------------
local function getCarStrict()
    local player = Players.LocalPlayer
    local myName = player.Name
    local char = player.Character or player.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    
    local vehiclesFolder = workspace:WaitForChild("Vehicles", 5)
    
    -- HILFSFUNKTION: Scannt Workspace nach deinem Auto
    local function scanForMyCar()
        if not vehiclesFolder then return nil end
        for _, car in pairs(vehiclesFolder:GetChildren()) do
            -- Wir suchen nach dem State-Objekt mit deinem Namen
            if car:FindFirstChild("_VehicleState_" .. myName) then
                return car
            end
        end
        return nil
    end

    print("Suche nach existierendem Auto...")
    local myCar = scanForMyCar()

    -- ---------------------------------------------------
    -- SZENARIO A: Auto gefunden!
    -- ---------------------------------------------------
    if myCar then
        print("Auto gefunden: " .. myCar.Name)
        local seat = myCar:FindFirstChild("Seat")
        
        -- 1. Sitzen wir schon drin?
        if seat and seat:FindFirstChild("PlayerName") and seat.PlayerName.Value == myName then
            print("Du sitzt bereits im Auto. Startklar.")
            return myCar.PrimaryPart or seat
        end

        -- 2. Wir sitzen NICHT, aber Auto existiert -> HINFLIEGEN
        if seat then
            warn("Auto leer gefunden. Fliege Spieler hin zum Einsteigen...")
            
            -- Physik am Spieler (HumanoidRootPart)
            for _, v in pairs(root:GetChildren()) do
                if v:IsA("BodyGyro") or v:IsA("BodyVelocity") then v:Destroy() end
            end
            local bg = Instance.new("BodyGyro", root); bg.MaxTorque = Vector3.new(math.huge,math.huge,math.huge); bg.P=3000; bg.D=500
            local bv = Instance.new("BodyVelocity", root); bv.MaxForce = Vector3.new(math.huge,math.huge,math.huge)

            local target = seat.Position
            local startPos = root.Position
            
            -- Flugsequenz zum Auto (Speed 194, Höhe 360)
            flyTo(root, Vector3.new(startPos.X, 360, startPos.Z), 194, bg, bv, false) -- Hoch
            flyTo(root, Vector3.new(target.X, 360, target.Z), 194, bg, bv, false) -- Rüber
            flyTo(root, target, 194, bg, bv, true) -- Runter (Sanft)

            bg:Destroy(); bv:Destroy()
            
            -- E Drücken Simulation
            warn("Am Auto angekommen. Drücke E...")
            task.wait(0.5)
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.1)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            
            -- Warten ob wir sitzen
            task.wait(2)
            
            -- CHECK: Sitzen wir JETZT?
            if seat.PlayerName.Value == myName then
                print("Erfolgreich eingestiegen!")
                return myCar.PrimaryPart or seat
            else
                warn("FEHLER: Konnte nicht einsteigen (Auto abgeschlossen oder Bug). Breche ab.")
                return nil -- ABBRUCH! Nicht als Mensch weiterfliegen!
            end
        end
    end

    -- ---------------------------------------------------
    -- SZENARIO B: Kein Auto gefunden -> SPAWNEN
    -- ---------------------------------------------------
    warn("Kein existierendes Auto gefunden. Spawne neu...")
    local remote = ReplicatedStorage:WaitForChild("GarageSpawnVehicle", 2)
    if remote then 
        remote:FireServer("Chassis", "Deja") 
    end
    
    -- Warten und scannen
    for i = 1, 30 do -- 3 Sekunden warten
        task.wait(0.1)
        myCar = scanForMyCar()
        if myCar then
            local seat = myCar:FindFirstChild("Seat")
            -- Wenn gespawnt, sitzen wir meistens automatisch drin.
            if seat and seat:FindFirstChild("PlayerName") and seat.PlayerName.Value == myName then
                print("Auto gespawnt und eingestiegen!")
                return myCar.PrimaryPart or seat
            end
        end
    end

    warn("FEHLER: Auto Spawn fehlgeschlagen oder nicht automatisch eingestiegen.")
    return nil -- ABBRUCH!
end

-- -------------------------------------------------------------------------
-- 3. ROUTE STARTEN
-- -------------------------------------------------------------------------
getgenv().startRoute = function(jsonFileName, speed)
    -- Hier holen wir das Auto. Wenn es nil zurückgibt, wird sofort gestoppt.
    local moverPart = getCarStrict()

    if not moverPart then
        warn("ABBRUCH: Route wurde nicht gestartet, da kein Auto verfügbar ist.")
        -- Hier passiert nichts mehr. Der Spieler fliegt nirgendwo hin.
        return 
    end

    -- Ab hier geht es nur weiter, wenn wir WIRKLICH ein Auto haben
    local routeData
    if jsonFileName:find(".json") then
        local url = REPO_URL .. jsonFileName
        print("Lade Route: " .. url)
        local success, response = pcall(function() return game:HttpGet(url) end)
        if not success then return warn("Fehler beim Laden von GitHub!", response) end
        routeData = HttpService:JSONDecode(response)
    else
        routeData = HttpService:JSONDecode(jsonFileName)
    end

    -- Physik Setup (Am Auto!)
    for _, v in pairs(moverPart:GetChildren()) do
        if v:IsA("BodyGyro") or v:IsA("BodyVelocity") then v:Destroy() end
    end

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge); bg.P = 3000; bg.D = 500; bg.Parent = moverPart
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge); bv.Parent = moverPart

    print("Auto bereit. Starte Route...")
    
    for i, point in ipairs(routeData) do
        if not moverPart.Parent then break end

        if point.type == "wait" then
            task.wait(point.time or 0.5)
        elseif point.type == "move" then
            local target = Vector3.new(point.x, point.y, point.z)
            
            if i == 1 then
                local startPos = moverPart.Position
                -- Hoch -> Rüber -> Landen
                flyTo(moverPart, Vector3.new(startPos.X, 300, startPos.Z), speed, bg, bv, false)
                flyTo(moverPart, Vector3.new(target.X, 300, target.Z), speed, bg, bv, false)
                flyTo(moverPart, target, speed, bg, bv, true)
            else
                flyTo(moverPart, target, speed, bg, bv, false)
            end
        end
    end
    
    if bg then bg:Destroy() end
    if bv then bv:Destroy() end
    print("Route beendet.")
end

print("Geladen. Nutze: startRoute('Prison.json', 300)")
