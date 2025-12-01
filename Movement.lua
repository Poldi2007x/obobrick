local ReplicatedStorage       = game:GetService("ReplicatedStorage")
local Players                 = game:GetService("Players")
local RunService              = game:GetService("RunService")
local HttpService             = game:GetService("HttpService")
local VirtualInputManager     = game:GetService("VirtualInputManager")

-- !!! GITHUB RAW LINK !!!
local REPO_URL = "https://raw.githubusercontent.com/Poldi2007x/obobrick/main/"

-- -------------------------------------------------------------------------
-- 0. ANTI FALL DAMAGE
-- -------------------------------------------------------------------------
local function applyAntiFallDamage(char)
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)

    RunService.Heartbeat:Connect(function()
        if hum.Parent and root.Parent then
            if root.Velocity.Y < -120 then
                root.Velocity = Vector3.new(root.Velocity.X, 0, root.Velocity.Z)
            end
        end
    end)
end


-- -------------------------------------------------------------------------
-- 1. FLUG-PHYSIK (für Spieler & Auto)
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
        local diff       = targetPos - currentPos
        local dist       = diff.Magnitude

        if dist == 0 then
            arrived = true
            if connection then connection:Disconnect() end
            return
        end

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

        -- Gyro Control (waagerecht ausrichten)
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
            if connection then connection:Disconnect() end
        end
    end)

    repeat
        task.wait()
    until arrived or not moverPart.Parent
end

-- -------------------------------------------------------------------------
-- 2. HILFSFUNKTIONEN FÜR SITZE & CAMARO-FALLBACK
-- -------------------------------------------------------------------------

local function isSeatOwnedByPlayer(seat, playerName)
    if not seat then return false end
    local pn = seat:FindFirstChild("PlayerName")
    if pn and typeof(pn.Value) == "string" then
        return pn.Value == playerName
    end
    return false
end

local function isSeatFree(seat)
    if not seat then return false end
    local pn = seat:FindFirstChild("PlayerName")
    if pn and typeof(pn.Value) == "string" then
        return pn.Value == ""
    end
    return false
end

-- Nur EINMAL E drücken + 3 Sekunden warten
local function pressEOnce()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    task.wait(3)
end

-- Suche nach dem nächsten freien Camaro (workspace.Vehicles)
local function findNearestFreeCamaro(rootPart)
    if not rootPart then return nil, nil end

    local vehicles = workspace:FindFirstChild("Vehicles")
    if not vehicles then return nil, nil end

    local nearestCar  = nil
    local nearestSeat = nil
    local nearestDist = math.huge

    for _, v in ipairs(vehicles:GetChildren()) do
        if v.Name == "Camaro" then
            local seat = v:FindFirstChild("Seat")
            if seat and isSeatFree(seat) then
                local dist = (rootPart.Position - seat.Position).Magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    nearestCar  = v
                    nearestSeat = seat
                end
            end
        end
    end

    return nearestCar, nearestSeat
end

-- Fliegt zum nächsten freien Camaro, versucht einzusteigen und gibt das Auto zurück
local function takeOverNearestCamaro(rootPart, playerName)
    local camaro, seat = findNearestFreeCamaro(rootPart)
    if not camaro or not seat then
        warn("Kein freier Camaro gefunden.")
        return nil
    end

    local startPos = rootPart.Position
    local target   = seat.Position

    -- Physik am Spieler setzen
    for _, v in pairs(rootPart:GetChildren()) do
        if v:IsA("BodyGyro") or v:IsA("BodyVelocity") then
            v:Destroy()
        end
    end

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P         = 3000
    bg.D         = 500
    bg.Parent    = rootPart

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent   = rootPart

    -- Hoch auf 360 → rüber → landen (Speed 150)
    flyTo(rootPart, Vector3.new(startPos.X, 360, startPos.Z), 150, bg, bv, false)
    flyTo(rootPart, Vector3.new(target.X, 360, target.Z),     150, bg, bv, false)
    flyTo(rootPart, target,                                   150, bg, bv, true)

    bg:Destroy()
    bv:Destroy()

    -- Einsteigen (nur 1x E + 3 Sek warten)
    pressEOnce()

    if isSeatOwnedByPlayer(seat, playerName) then
        print("Camaro übernommen.")
        return camaro.PrimaryPart or seat
    else
        warn("Konnte nicht in den Camaro einsteigen.")
        return nil
    end
end

-- -------------------------------------------------------------------------
-- 3. AUTO-LOGIK (eigenes Auto -> spawnen -> Camaro-Fallback)
-- -------------------------------------------------------------------------
local function getCarStrict()
    local player = Players.LocalPlayer
    local myName = player.Name
    local char   = player.Character or player.CharacterAdded:Wait()
    local root   = char:WaitForChild("HumanoidRootPart")

    -- Anti-Fall-Damage aktivieren
    applyAntiFallDamage(char)

    local vehiclesFolder = workspace:WaitForChild("Vehicles", 5)

    -- Sucht das Auto-Model über den VehicleState
    local function findMyCarModel()
        if not vehiclesFolder then return nil end
        for _, car in pairs(vehiclesFolder:GetChildren()) do
            local stateValue = car:FindFirstChild("_VehicleState_" .. myName)
            if stateValue then
                return stateValue.Parent
            end
        end
        return nil
    end

    print("Suche nach eigenem Auto...")
    local myCar = findMyCarModel()

    -- ---------------------------------------------------
    -- FALL A: Eigenes Auto auf der Map gefunden
    -- ---------------------------------------------------
    if myCar then
        print("Auto gefunden: " .. myCar.Name)
        local seat = myCar:FindFirstChild("Seat")

        -- 1. Check: Sitzen wir schon drin?
        if seat and isSeatOwnedByPlayer(seat, myName) then
            print("Du sitzt bereits im Auto.")
            return myCar.PrimaryPart or seat
        end

        -- 2. Check: Wir sitzen NICHT -> Hinfliegen (Speed 150)
        if seat then
            warn("Eigenes Auto leer. Fliege Spieler hin (Speed 150)...")

            for _, v in pairs(root:GetChildren()) do
                if v:IsA("BodyGyro") or v:IsA("BodyVelocity") then
                    v:Destroy()
                end
            end

            local bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            bg.P         = 3000
            bg.D         = 500
            bg.Parent    = root

            local bv = Instance.new("BodyVelocity")
            bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bv.Parent   = root

            local target   = seat.Position
            local startPos = root.Position

            -- Hoch auf 360 (Sicherheits-Höhe)
            flyTo(root, Vector3.new(startPos.X, 360, startPos.Z), 150, bg, bv, false)
            -- Rüber zum Auto auf 360
            flyTo(root, Vector3.new(target.X,    360, target.Z), 150, bg, bv, false)
            -- Runter (sanfte Landung)
            flyTo(root, target,                                150, bg, bv, true)

            bg:Destroy()
            bv:Destroy()

            -- Nur 1x E drücken
            warn("Versuche einzusteigen (E einmal)...")
            pressEOnce()

            if isSeatOwnedByPlayer(seat, myName) then
                print("Erfolgreich ins eigene Auto eingestiegen!")
                return myCar.PrimaryPart or seat
            else
                warn("Konnte nicht ins eigene Auto einsteigen → versuche Spawn/Fallback.")
            end
        end
    end

    -- ---------------------------------------------------
    -- FALL B: Kein Auto / nicht drin -> Spawnen
    -- ---------------------------------------------------
    warn("Kein nutzbares Auto gefunden. Versuche Spawn über Garage...")

    local remote = ReplicatedStorage:FindFirstChild("GarageSpawnVehicle")
    if remote then
        remote:FireServer("Chassis", "Deja")
    else
        warn("GarageSpawnVehicle Remote nicht gefunden.")
    end

    -- Kurze Zeit warten und prüfen, ob eigenes Auto gespawnt ist
    local spawnedCar
    for i = 1, 30 do
        task.wait(0.1)
        spawnedCar = findMyCarModel()
        if spawnedCar then
            local seat = spawnedCar:FindFirstChild("Seat")
            if seat and isSeatOwnedByPlayer(seat, myName) then
                print("Auto gespawnt und du sitzt drin.")
                return spawnedCar.PrimaryPart or seat
            end
        end
    end

    warn("Auto Spawn fehlgeschlagen oder du sitzt nicht drin.")

    -- ---------------------------------------------------
    -- FALL C: Kein eigenes Auto & Spawn klappt nicht -> Camaro suchen
    -- ---------------------------------------------------
    warn("Fallback: Suche nach nächstem freien Camaro in workspace.Vehicles...")
    local camaroMover = takeOverNearestCamaro(root, myName)
    if camaroMover then
        print("Camaro als Ersatzfahrzeug übernommen.")
        return camaroMover
    end

    warn("Kein Auto verfügbar. Abbruch.")
    return nil
end

-- -------------------------------------------------------------------------
-- 4. ROUTE STARTEN (mit Auto / Camaro)
-- -------------------------------------------------------------------------
getgenv().startRoute = function(jsonFileName, speed)
    speed = speed or 300

    -- Auto holen (oder einsteigen / Camaro übernehmen)
    local moverPart = getCarStrict()

    if not moverPart then
        warn("ABBRUCH: Keine Route ohne Fahrzeug möglich.")
        return
    end

    -- Route laden (GitHub .json oder direkter JSON-String)
    local routeData
    if jsonFileName:find(".json") then
        local url = REPO_URL .. jsonFileName
        print("Lade Route von GitHub: " .. url)
        local success, response = pcall(function()
            return game:HttpGet(url)
        end)

        if not success then
            warn("Fehler beim Laden von GitHub:", response)
            return
        end

        routeData = HttpService:JSONDecode(response)
    else
        routeData = HttpService:JSONDecode(jsonFileName)
    end

    -- Physik am Fahrzeug setzen
    for _, v in pairs(moverPart:GetChildren()) do
        if v:IsA("BodyGyro") or v:IsA("BodyVelocity") then
            v:Destroy()
        end
    end

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    bg.P         = 3000
    bg.D         = 500
    bg.Parent    = moverPart

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent   = moverPart

    print("Starte Route mit Fahrzeug...")

    for i, point in ipairs(routeData) do
        if not moverPart.Parent then
            warn("Fahrzeug existiert nicht mehr. Route abgebrochen.")
            break
        end

        if point.type == "wait" then
            task.wait(point.time or 0.5)

        elseif point.type == "move" then
            local target = Vector3.new(point.x, point.y, point.z)

            if i == 1 then
                local startPos = moverPart.Position
                -- Hoch -> Rüber -> Landen
                flyTo(moverPart, Vector3.new(startPos.X, 300, startPos.Z), speed, bg, bv, false)
                flyTo(moverPart, Vector3.new(target.X,    300, target.Z), speed, bg, bv, false)
                flyTo(moverPart, target,                                speed, bg, bv, true)
            else
                flyTo(moverPart, target, speed, bg, bv, false)
            end
        end
    end

    if bg then bg:Destroy() end
    if bv then bv:Destroy() end

    print("Route fertig!")
end

print("Geladen. Nutze: startRoute('Prison.json', 300)")
