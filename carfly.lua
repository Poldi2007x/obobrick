local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- !!! GITHUB RAW LINK !!!
local REPO_URL = "https://raw.githubusercontent.com/Poldi2007x/obobrick/main/" 

-- 1. Auto Funktion (Vereinfacht)
local function getCar()
    local player = Players.LocalPlayer
    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid")

    -- Wenn man nicht sitzt: Spawnen & kurz warten
    if not hum.SeatPart then
        local remote = ReplicatedStorage:WaitForChild("GarageSpawnVehicle", 2)
        if remote then 
            remote:FireServer("Chassis", "Deja") 
        end
        
        -- Einfach 1.5 Sekunden warten, damit das Auto da ist. Kein Loop.
        task.wait(1.5)
    end
    
    -- Auto zurückgeben (falls vorhanden)
    if hum.SeatPart then
        return hum.SeatPart.Parent.PrimaryPart or hum.SeatPart
    end
    return nil
end

-- 2. Flug-Physik
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
        
        if dist < 10 then 
            arrived = true
            connection:Disconnect()
        end
    end)
    
    repeat task.wait() until arrived or not rootPart.Parent
end

-- 3. Hauptfunktion
getgenv().startRoute = function(jsonFileName, speed)
    -- A) Auto holen
    local rootPart = getCar()
    
    -- Falls das Spawnen zu lange gedauert hat und man immer noch nicht sitzt:
    if not rootPart then
        warn("Kein Auto gefunden! Bitte sitz ins Auto.")
        return
    end

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

    -- D) Route abfahren
    for i, point in ipairs(routeData) do
        if not rootPart.Parent then break end

        if point.type == "wait" then
            task.wait(point.time or 0.5)
        elseif point.type == "move" then
            local target = Vector3.new(point.x, point.y, point.z)
            
            if i == 1 then
                -- Start Manöver
                local startPos = rootPart.Position
                flyTo(rootPart, Vector3.new(startPos.X, 300, startPos.Z), speed, bg, bv)
                flyTo(rootPart, Vector3.new(target.X, 300, target.Z), speed, bg, bv)
                flyTo(rootPart, target, speed, bg, bv)
            else
                -- Normal
                flyTo(rootPart, target, speed, bg, bv)
            end
        end
    end
    
    if bg then bg:Destroy() end
    if bv then bv:Destroy() end
    print("Fertig!")
end

print("Geladen. Nutze: startRoute('Prison.json', 300)")
