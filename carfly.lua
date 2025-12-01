local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- !!! GITHUB RAW LINK !!!
local REPO_URL = "https://raw.githubusercontent.com/Poldi2007x/obobrick/main/" 

-- 1. Funktion: Physik-Teil holen (Ohne Checks)
local function getMobileRoot()
    local player = Players.LocalPlayer
    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid")
    local root = char:WaitForChild("HumanoidRootPart")

    -- IMMER Auto spawnen (egal ob man sitzt oder nicht)
    local remote = ReplicatedStorage:WaitForChild("GarageSpawnVehicle", 2)
    if remote then 
        remote:FireServer("Chassis", "Deja") 
    end
    
    -- Kurz warten, damit das Auto lädt
    task.wait(1)

    -- Versuch 1: Wir schauen, ob das Spiel den Sitz erkennt
    if hum.SeatPart then
        return hum.SeatPart -- Wir bewegen den Sitz (und damit das Auto)
    end

    -- Versuch 2: Fallback -> Wir bewegen einfach DICH (HumanoidRootPart)
    warn("Sitz nicht erkannt! Bewege HumanoidRootPart...")
    return root
end

-- 2. Flug-Physik (Angepasst: Bleibt immer waagerecht!)
local function flyTo(moverPart, targetPos, speed, bg, bv)
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
        
        -- BEWEGUNG (Velocity): Geht weiterhin zum echten Ziel (auch hoch/runter)
        bv.Velocity = diff.Unit * speed
        
        -- DREHUNG (Gyro): Ignoriert die Höhe des Ziels!
        local flatDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude
        
        if flatDist > 2 then
            -- Wenn wir uns seitwärts bewegen: Zum Ziel drehen, aber Y gleich lassen (damit es flach bleibt)
            bg.CFrame = CFrame.new(currentPos, Vector3.new(targetPos.X, currentPos.Y, targetPos.Z))
        else
            -- Wenn wir nur strikt nach oben/unten fliegen (keine seitwärts Bewegung):
            -- Behalten wir die aktuelle Blickrichtung bei, zwingen sie aber waagerecht (Pitch/Roll = 0)
            local _, rotY, _ = moverPart.CFrame:ToOrientation()
            bg.CFrame = CFrame.new(currentPos) * CFrame.fromOrientation(0, rotY, 0)
        end
        
        if dist < 10 then 
            arrived = true
            connection:Disconnect()
        end
    end)
    
    repeat task.wait() until arrived or not moverPart.Parent
end

-- 3. Hauptfunktion
getgenv().startRoute = function(jsonFileName, speed)
    -- A) Teil holen, das fliegen soll
    local moverPart = getMobileRoot()

    -- B) JSON Laden
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

    -- C) Physik Setup
    -- Alte Physik löschen
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

    -- D) Route abfahren
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
                -- 1. Hoch (Bleibt jetzt flach!)
                flyTo(moverPart, Vector3.new(startPos.X, 300, startPos.Z), speed, bg, bv)
                -- 2. Rüber (Bleibt flach)
                flyTo(moverPart, Vector3.new(target.X, 300, target.Z), speed, bg, bv)
                -- 3. Runter (Bleibt flach, keine Sturzflug-Optik)
                flyTo(moverPart, target, speed, bg, bv)
            else
                -- Normal weiter
                flyTo(moverPart, target, speed, bg, bv)
            end
        end
    end
    
    if bg then bg:Destroy() end
    if bv then bv:Destroy() end
    print("Fertig!")
end

print("Geladen. Nutze: startRoute('Prison.json', 300)")
