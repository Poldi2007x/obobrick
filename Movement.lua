local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager") -- Für Taste E

-- !!! GITHUB RAW LINK !!!
local REPO_URL = "https://raw.githubusercontent.com/Poldi2007x/obobrick/main/" 

-- -------------------------------------------------------------------------
-- 1. FLUG-PHYSIK (Jetzt ganz oben, damit wir sie überall nutzen können)
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
        
        -- DREHUNG (Gyro) - Waagerecht bleiben
        local flatDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude
        
        if flatDist > 5 then
            bg.CFrame = CFrame.new(currentPos, Vector3.new(targetPos.X, currentPos.Y, targetPos.Z))
        else
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

-- -------------------------------------------------------------------------
-- 2. AUTO FINDEN / ZUM AUTO FLIEGEN / SPAWNEN
-- -------------------------------------------------------------------------
local function getMobileRoot()
    local player = Players.LocalPlayer
    local myName = player.Name
    local char = player.Character or player.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    
    local vehicles = workspace:FindFirstChild("Vehicles")

    -- Suche nach meinem Auto-Model (egal ob ich sitze oder nicht)
    local myCarModel = nil
    if vehicles then
        for _, car in pairs(vehicles:GetChildren()) do
            if car:FindFirstChild("_VehicleState_" .. myName) then
                myCarModel = car
                break
            end
        end
    end

    -- FALL A: Auto existiert bereits auf der Map
    if myCarModel then
        local seat = myCarModel:FindFirstChild("Seat")
        
        -- Check 1: Sitze ich schon drin?
        if seat and seat:FindFirstChild("PlayerName") and seat.PlayerName.Value == myName then
            print("Bereits im Auto.")
            return myCarModel.PrimaryPart or seat
        end

        -- Check 2: Auto ist da, aber ich sitze nicht -> HINFLIEGEN
        if seat then
            warn("Auto gefunden (leer). Fliege als Spieler hin...")
            
            -- Physik am Spieler erstellen
            for _, v in pairs(root:GetChildren()) do
                if v:IsA("BodyGyro") or v:IsA("BodyVelocity") then v:Destroy() end
            end
            
            local bg = Instance.new("BodyGyro", root)
            bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge); bg.P = 3000; bg.D = 500
            
            local bv = Instance.new("BodyVelocity", root)
            bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)

            -- Flug-Sequenz zum Auto (Speed 194, Höhe 360)
            local target = seat.Position
            local startPos = root.Position
            
            -- 1. Hoch auf 360
            flyTo(root, Vector3.new(startPos.X, 360, startPos.Z), 194, bg, bv, false)
            -- 2. Rüber zum Auto auf 360
            flyTo(root, Vector3.new(target.X, 360, target.Z), 194, bg, bv, false)
            -- 3. Runter (Sanfte Landung)
            flyTo(root, target, 194, bg, bv, true)

            -- Physik entfernen damit wir einsteigen können
            bg:Destroy()
            bv:Destroy()
            
            -- Taste E simulieren
            warn("Angekommen. Drücke E...")
            task.wait(0.2)
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.1)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            
            -- Kurz warten bis wir sitzen
            task.wait(1.5)
            
            -- Prüfen ob wir jetzt sitzen
            if seat.PlayerName.Value == myName then
                print("Erfolgreich eingestiegen!")
                return myCarModel.PrimaryPart or seat
            else
                warn("Einsteigen fehlgeschlagen (vielleicht abgeschlossen?). Mache weiter...")
                -- Fallback: Wir versuchen trotzdem das Auto zu nehmen, falls der Name nur laggt
                return myCarModel.PrimaryPart or seat
            end
        end
    end

    -- FALL B: Kein Auto auf der Map -> SPAWNEN
    warn("Kein Auto gefunden. Spawne neu...")
    local remote = ReplicatedStorage:WaitForChild("GarageSpawnVehicle", 2)
    if remote then 
        remote:FireServer("Chassis", "Deja") 
    end
    
    -- Warten bis Auto da ist
    for i = 1, 20 do
        task.wait(0.1)
        -- Schnellsuche nach Spawn
        if vehicles then
            for _, car in pairs(vehicles:GetChildren()) do
                if car:FindFirstChild("_VehicleState_" .. myName) then
                     local seat = car:FindFirstChild("Seat")
                     if seat and seat:FindFirstChild("PlayerName") and seat.PlayerName.Value == myName then
                         return car.PrimaryPart or seat
                     end
                end
            end
        end
    end

    warn("Fallback: Nutze HumanoidRootPart.")
    return root
end

-- -------------------------------------------------------------------------
-- 3. ROUTE STARTEN
-- -------------------------------------------------------------------------
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

    -- Physik Setup am Auto
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
    print("Starte Route mit Auto...")
    for i, point in ipairs(routeData) do
        if not moverPart.Parent then break end

        if point.type == "wait" then
            task.wait(point.time or 0.5)
        elseif point.type == "move" then
            local target = Vector3.new(point.x, point.y, point.z)
            
            if i == 1 then
                -- Start Manöver: Hoch -> Rüber -> Landen
                local startPos = moverPart.Position
                
                -- 1. Hoch (Schnell, keine Landung)
                flyTo(moverPart, Vector3.new(startPos.X, 300, startPos.Z), speed, bg, bv, false)
                
                -- 2. Rüber (Schnell, keine Landung)
                flyTo(moverPart, Vector3.new(target.X, 300, target.Z), speed, bg, bv, false)
                
                -- 3. Runter (SANFTE LANDUNG)
                flyTo(moverPart, target, speed, bg, bv, true)
            else
                -- Normal weiter
                flyTo(moverPart, target, speed, bg, bv, false)
            end
        end
    end
    
    if bg then bg:Destroy() end
    if bv then bv:Destroy() end
    print("Fertig!")
end

print("Geladen. Nutze: startRoute('Prison.json', 300)")
