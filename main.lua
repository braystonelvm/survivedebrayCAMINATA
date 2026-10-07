-- ==============================================================================
-- MAP PATROL HUB - MULTIMODO DE MOVIMIENTO (5 MOTORES FÍSICOS SELECCIONABLES)
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer

local MarkersFolder = workspace:FindFirstChild("YellowRouteMarkers")
if not MarkersFolder then
    MarkersFolder = Instance.new("Folder")
    MarkersFolder.Name = "YellowRouteMarkers"
    MarkersFolder.Parent = workspace
end

local Config = {
    PatrolRunning = false,
    AutoRecord = false,
    StepDist = 30,
    ShowMarkers = true,
    CarSpeed = 80,
    IgnoreDayNight = false,
    ReturnEarlySeconds = 15,
    MoveMode = "1. Zombie Hub (Root Velocity)" -- Modo activo
}

local Waypoints = {}
local MarkerInstances = {}
local LastRecordPos = nil
local PatrolThread = nil
local LastKnownCar = nil

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "MAP PATROL HUB | MULTIMODO",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(590, 540),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Patrullaje", Icon = "play" }),
    Vehicle = Window:AddTab({ Title = "Control Auto", Icon = "truck" }),
    Recorder = Window:AddTab({ Title = "Grabador", Icon = "map-pin" }),
    Port = Window:AddTab({ Title = "Import/Export", Icon = "clipboard" }),
    Settings = Window:AddTab({ Title = "Ajustes", Icon = "settings" })
}

local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Estado del Patrullaje",
    Content = "Inactivo. Carga tu ruta y presiona Iniciar."
})

local CycleParagraph = Tabs.Main:AddParagraph({
    Title = "Ciclo Detectado",
    Content = "Analizando hora..."
})

local function updateStatus(text)
    StatusParagraph:SetDesc(text)
end

local function getRootPart()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function getHumanoid()
    local char = lp.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function getCurrentVehicle()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart then
        local seat = hum.SeatPart
        local carModel = seat:FindFirstAncestorOfClass("Model") or seat.Parent
        if carModel and carModel:IsA("Model") then
            LastKnownCar = carModel
            return carModel, seat
        end
        return nil, seat
    end
    return nil, nil
end

-- RASTREADOR EN SEGUNDO PLANO DEL AUTO
task.spawn(function()
    while true do
        task.wait(0.5)
        local car = getCurrentVehicle()
        if car then LastKnownCar = car end
    end
end)

-- RESETEAR FÍSICAS Y DESBUGEAR AUTO
local function resetVehiclePhysics()
    local car, seat = getCurrentVehicle()
    if not car and LastKnownCar and LastKnownCar.Parent then
        car = LastKnownCar
        seat = car:FindFirstChildWhichIsA("VehicleSeat", true) or car:FindFirstChildWhichIsA("Seat", true)
    end

    if car then
        for _, p in ipairs(car:GetDescendants()) do
            if p:IsA("BasePart") then
                p.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            elseif p:IsA("BodyMover") or p:IsA("VectorForce") or p:IsA("LinearVelocity") then
                p:Destroy()
            end
        end

        if seat then
            if seat:IsA("VehicleSeat") then
                seat.Throttle = 0
                seat.Steer = 0
            end
            local curPos = seat.Position
            local safeY = math.max(curPos.Y, 3.5)
            pcall(function()
                local look = seat.CFrame.LookVector
                car:PivotTo(CFrame.new(Vector3.new(curPos.X, safeY, curPos.Z), Vector3.new(curPos.X + look.X, safeY, curPos.Z + look.Z)))
            end)
        end
    end

    local root = getRootPart()
    if root then
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        for _, p in ipairs(lp.Character:GetDescendants()) do
            if p:IsA("BodyMover") or p:IsA("LinearVelocity") then p:Destroy() end
        end
    end

    Fluent:Notify({ Title = "Auto Normalizado", Content = "Físicas y velocidades reseteadas.", Duration = 2.5 })
end

-- RESCATAR AUTO PERDIDO
local function rescueLostCar()
    local car = LastKnownCar
    if not car or not car.Parent then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("VehicleSeat") or (obj:IsA("Seat") and obj.Name:lower():find("drive")) then
                car = obj:FindFirstAncestorOfClass("Model")
                if car then
                    LastKnownCar = car
                    break
                end
            end
        end
    end

    if not car then
        Fluent:Notify({ Title = "Sin Auto", Content = "No se encontró ningún vehículo en el mapa.", Duration = 3 })
        return
    end

    local seat = car:FindFirstChildWhichIsA("VehicleSeat", true) or car:FindFirstChildWhichIsA("Seat", true)
    local root = getRootPart()
    local hum = getHumanoid()
    if not root or not hum then return end

    updateStatus("🚨 Rescatando auto del abismo/cielo...")

    local targetPos = (Waypoints and #Waypoints > 0 and Waypoints[1]) or Vector3.new(root.Position.X, 4.0, root.Position.Z)
    local safeCF = CFrame.new(targetPos.X, math.max(targetPos.Y, 3.5) + 2.5, targetPos.Z)

    for _, p in ipairs(car:GetDescendants()) do
        if p:IsA("BasePart") then
            p.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        elseif p:IsA("BodyMover") or p:IsA("LinearVelocity") then
            p:Destroy()
        end
    end

    pcall(function() car:PivotTo(safeCF) end)
    task.wait(0.1)

    root.CFrame = safeCF + Vector3.new(0, 3, 0)
    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

    if seat then
        if seat:IsA("VehicleSeat") then
            seat.Throttle = 0
            seat.Steer = 0
        end
        task.wait(0.15)
        pcall(function() seat:Sit(hum) end)
    end

    resetVehiclePhysics()
    updateStatus("Auto rescatado y colocado a salvo en el suelo.")
    Fluent:Notify({ Title = "¡Auto Rescatado!", Content = "El auto volvió a la superficie y está listo.", Duration = 4 })
end

-- DETECTOR DE DÍA / NOCHE
local function scanGameDayNight()
    if Config.IgnoreDayNight then return true, 999 end

    local detectedDay = true
    local remainingSecs = 999

    local pGui = lp:FindFirstChild("PlayerGui")
    if pGui then
        for _, lbl in ipairs(pGui:GetDescendants()) do
            if lbl:IsA("TextLabel") and lbl.Visible then
                local txt = lbl.Text:lower()
                if txt:find("noche") or txt:find("night") then detectedDay = false end
                local m, s = txt:match("(%d+):(%d+)")
                if m and s and not txt:find("revivir") and not txt:find("espera") then
                    remainingSecs = (tonumber(m) * 60) + tonumber(s)
                end
            end
        end
    end

    local clock = Lighting.ClockTime
    if clock < 5.8 or clock > 18.2 then detectedDay = false end

    return detectedDay, remainingSecs
end

task.spawn(function()
    while true do
        task.wait(0.5)
        local isDay, secs = scanGameDayNight()
        local car = getCurrentVehicle()
        local modeText = car and "🚗 EN VEHÍCULO" or "🏃 A PIE"

        if Config.IgnoreDayNight then
            CycleParagraph:SetDesc(string.format("Modo: %s | Ciclo: ☀️ DÍA FORZADO (24h)", modeText))
        else
            local timeInfo = (secs < 900) and string.format(" (Quedan: %ds)", secs) or ""
            CycleParagraph:SetDesc(string.format("Modo: %s | Ciclo: %s%s", modeText, isDay and "☀️ DÍA" or "🌙 NOCHE", timeInfo))
        end
    end
end)

-- MANIOBRAS DE DESATASCO
local function evasiveManeuver(attempt, targetPos)
    local root = getRootPart()
    if not root then return end

    local cf = root.CFrame
    if attempt == 1 then
        root.AssemblyLinearVelocity = (-cf.LookVector * 50) + (cf.RightVector * 35)
        task.wait(0.4)
    elseif attempt == 2 then
        root.AssemblyLinearVelocity = (-cf.LookVector * 50) - (cf.RightVector * 35)
        task.wait(0.4)
    elseif attempt == 3 then
        root.AssemblyLinearVelocity = (-cf.LookVector * 60) + Vector3.new(0, 8, 0)
        task.wait(0.4)
    elseif attempt >= 4 and targetPos then
        updateStatus("⚠️ Desatascando hacia el nodo...")
        root.AssemblyLinearVelocity = Vector3.zero
        local car = getCurrentVehicle()
        if car then
            pcall(function() car:PivotTo(CFrame.new(targetPos.X, targetPos.Y + 2.0, targetPos.Z)) end)
        else
            root.CFrame = CFrame.new(targetPos.X, targetPos.Y + 2.0, targetPos.Z)
        end
        task.wait(0.3)
    end
end

-- ==============================================================================
-- MOTOR DE MOVIMIENTO MULTIMODO (EJECUCIÓN POR HEARTBEAT)
-- ==============================================================================
local function walkOrDriveTo(targetPos, maxTime)
    local startT = tick()
    local reached = false

    while Config.PatrolRunning and (tick() - startT < maxTime) do
        local dt = RunService.Heartbeat:Wait()

        local root = getRootPart()
        local hum = getHumanoid()
        local car, seat = getCurrentVehicle()

        if not root or not hum or hum.Health <= 0 then break end

        -- Punto de referencia
        local myPos = (seat and seat.Position) or root.Position
        local direction = (targetPos - myPos)
        local horizontalDir = Vector3.new(direction.X, 0, direction.Z)

        if horizontalDir.Magnitude <= 4.0 then
            reached = true
            break
        end

        local dirUnit = horizontalDir.Unit
        local speed = Config.CarSpeed
        local targetVel = dirUnit * speed

        -- ================== SELECCIÓN DE MOTOR FÍSICO ==================

        -- MODO 1: ZOMBIE HUB EXACTO (VELOCIDAD FÍSICA DIRECTA EN ROOT SIN PIVOTTO)
        if Config.MoveMode:find("1") then
            root.AssemblyLinearVelocity = Vector3.new(targetVel.X, root.AssemblyLinearVelocity.Y, targetVel.Z)

        -- MODO 2: VELOCIDAD DIRECTA EN SEAT / RUEDAS (HEREDA EL CHASSIS)
        elseif Config.MoveMode:find("2") then
            local mainSeat = seat or root
            mainSeat.AssemblyLinearVelocity = Vector3.new(targetVel.X, mainSeat.AssemblyLinearVelocity.Y, targetVel.Z)
            if seat and seat:IsA("VehicleSeat") then seat.Throttle = 1 end

        -- MODO 3: BODYVELOCITY (FUERZA BRUTA INFINITA ANTI-FRICCIÓN)
        elseif Config.MoveMode:find("3") then
            local mainPart = seat or root
            local bv = mainPart:FindFirstChild("PatrolBV")
            if not bv then
                bv = Instance.new("BodyVelocity")
                bv.Name = "PatrolBV"
                bv.MaxForce = Vector3.new(1e8, 0, 1e8) -- Bloquea eje Y para no volar ni hundirse
                bv.Parent = mainPart
            end
            bv.Velocity = Vector3.new(targetVel.X, 0, targetVel.Z)

        -- MODO 4: LINEARVELOCITY (CONSTRAINT DE FÍSICA MODERNA ROBLOX)
        elseif Config.MoveMode:find("4") then
            local mainPart = seat or root
            local att = mainPart:FindFirstChild("PatrolAtt")
            if not att then
                att = Instance.new("Attachment")
                att.Name = "PatrolAtt"
                att.Parent = mainPart
            end
            local lv = mainPart:FindFirstChild("PatrolLV")
            if not lv then
                lv = Instance.new("LinearVelocity")
                lv.Name = "PatrolLV"
                lv.Attachment0 = att
                lv.MaxForce = 1e9
                lv.RelativeTo = Enum.ActuatorRelativeTo.World
                lv.Parent = mainPart
            end
            lv.VectorVelocity = Vector3.new(targetVel.X, 0, targetVel.Z)

        -- MODO 5: CFRAME STEP (DESPLAZAMIENTO PASO A PASO / IGNORA SUSPENSIÓN)
        elseif Config.MoveMode:find("5") then
            local stepDist = speed * dt
            local moveOffset = dirUnit * math.min(stepDist, horizontalDir.Magnitude)
            if car then
                pcall(function() car:PivotTo(car:GetPivot() + moveOffset) end)
            else
                root.CFrame = root.CFrame + moveOffset
            end
        end
    end

    -- LIMPIEZA DE OBJETOS FÍSICOS TEMPORALES AL SALIR DEL NODO
    local rootPart = getRootPart()
    local _, seatPart = getCurrentVehicle()
    for _, part in ipairs({rootPart, seatPart}) do
        if part then
            local bv = part:FindFirstChild("PatrolBV")
            if bv then bv:Destroy() end
            local lv = part:FindFirstChild("PatrolLV")
            if lv then lv:Destroy() end
            local att = part:FindFirstChild("PatrolAtt")
            if att then att:Destroy() end
        end
    end

    return reached
end

-- INTENTAR HASTA 4 VECES
local function moveToPointWithRetry(targetPos)
    for attempt = 1, 4 do
        if not Config.PatrolRunning then return false end
        local success = walkOrDriveTo(targetPos, 4.0)
        if success then
            return true
        else
            evasiveManeuver(attempt, targetPos)
        end
    end
    return false
end

-- CREACIÓN DE MARCADORES (0 LAG)
local function createMarker(pos, index)
    local marker = Instance.new("Part")
    marker.Name = "RouteNode_" .. index
    marker.Shape = Enum.PartType.Ball
    marker.Size = Vector3.new(1.8, 1.8, 1.8)
    marker.Material = Enum.Material.Neon
    marker.Color = (index == 1) and Color3.fromRGB(0, 255, 120) or Color3.fromRGB(255, 220, 0)
    marker.Anchored = true
    marker.CanCollide = false
    marker.CanTouch = false
    marker.CanQuery = false
    marker.CastShadow = false
    marker.Position = pos - Vector3.new(0, 1.4, 0)
    marker.Transparency = Config.ShowMarkers and 0 or 1
    marker.Parent = MarkersFolder
    table.insert(MarkerInstances, marker)
    return marker
end

local function redrawAllMarkers()
    MarkersFolder:ClearAllChildren()
    table.clear(MarkerInstances)
    for i, pos in ipairs(Waypoints) do
        createMarker(pos, i)
    end
end

-- DETENER Y NORMALIZAR TODO
local function stopPatrol()
    Config.PatrolRunning = false
    if PatrolThread then
        task.cancel(PatrolThread)
        PatrolThread = nil
    end

    local hum = getHumanoid()
    local root = getRootPart()
    if hum and root then hum:MoveTo(root.Position) end

    resetVehiclePhysics()
    updateStatus("Patrullaje detenido. Físicas restauradas.")
end

-- INICIAR: VA AL PUNTO 1, ESPERA 5s Y RECORRE
local function startPatrol()
    if #Waypoints < 2 then
        Fluent:Notify({ Title = "Sin Puntos", Content = "Carga o graba puntos primero.", Duration = 3 })
        return
    end

    stopPatrol()
    Config.PatrolRunning = true

    PatrolThread = task.spawn(function()
        -- 1. Ir al Punto 1 (Base)
        updateStatus("Iniciando: Yendo al Punto 1...")
        moveToPointWithRetry(Waypoints[1])

        if not Config.PatrolRunning then return end

        -- 2. Esperar 5 segundos en el Punto 1
        for s = 5, 1, -1 do
            if not Config.PatrolRunning then return end
            updateStatus(string.format("En Punto 1: Esperando %d segundos...", s))
            task.wait(1)
        end

        -- 3. Recorrer todos los puntos continuamente
        while Config.PatrolRunning do
            for i = 2, #Waypoints do
                if not Config.PatrolRunning then break end

                -- Chequeo de Noche (15s antes: Regreso en reversa por la ruta)
                local isDay, secsLeft = scanGameDayNight()
                if (not isDay or secsLeft <= Config.ReturnEarlySeconds) and not Config.IgnoreDayNight then
                    updateStatus(string.format("⚠️ Anocheciendo (%ds): Regresando a base...", secsLeft))

                    for backIdx = i - 1, 1, -1 do
                        if not Config.PatrolRunning then break end
                        local d, s = scanGameDayNight()
                        if d and s > Config.ReturnEarlySeconds then break end

                        updateStatus(string.format("Retorno nocturno: Nodo [%d / 1]", backIdx))
                        moveToPointWithRetry(Waypoints[backIdx])
                    end

                    -- Esperar amanecer en el Punto 1
                    while Config.PatrolRunning do
                        local d, s = scanGameDayNight()
                        if d and s > Config.ReturnEarlySeconds then break end
                        updateStatus("🌙 Esperando amanecer en Punto 1...")
                        task.wait(2)
                    end

                    updateStatus("Amaneció. Esperando 5s para reiniciar...")
                    task.wait(5)
                    break
                end

                -- Avanzar al siguiente punto
                updateStatus(string.format("Desplazando: Nodo [%d / %d]", i, #Waypoints))
                moveToPointWithRetry(Waypoints[i])
            end

            -- Al completar toda la ruta, vuelve por los nodos al Punto 1
            if Config.PatrolRunning then
                updateStatus("Fin de ruta. Regresando a Punto 1...")
                for backIdx = #Waypoints - 1, 1, -1 do
                    if not Config.PatrolRunning then break end
                    moveToPointWithRetry(Waypoints[backIdx])
                end
                task.wait(1)
            end
        end
    end)
end

-- PESTAÑA 1: PATRULLAJE
Tabs.Main:AddSection("Control de Ruta")

Tabs.Main:AddDropdown("MoveModeDropdown", {
    Title = "Modo de Movimiento",
    Values = {
        "1. Zombie Hub (Root Velocity)",
        "2. Chasis / Seat Velocity",
        "3. BodyVelocity (Fuerza Bruta)",
        "4. LinearVelocity (Constraint)",
        "5. CFrame Step (Micro-Paso 360°)"
    },
    Default = "1. Zombie Hub (Root Velocity)",
    Callback = function(Value)
        Config.MoveMode = Value
        Fluent:Notify({ Title = "Modo Cambiado", Content = Value, Duration = 2 })
    end
})

Tabs.Main:AddButton({
    Title = "▶ INICIAR PATRULLAJE",
    Description = "Va a Punto 1, espera 5s y recorre todos los puntos en 360°",
    Callback = function()
        startPatrol()
    end
})

Tabs.Main:AddButton({
    Title = "⏹ DETENER PATRULLAJE",
    Description = "Cancela todo y normaliza las físicas de inmediato",
    Callback = function()
        stopPatrol()
    end
})

Tabs.Main:AddButton({
    Title = "🔧 DESBUGEAR AUTO (Reset Físicas)",
    Description = "Frena el auto en seco, elimina fuerzas y asienta el chasis",
    Callback = function()
        resetVehiclePhysics()
    end
})

Tabs.Main:AddToggle("IgnoreDayNightToggle", {
    Title = "Forzar Modo Día (Ignorar Noche)",
    Description = "Recorre sin volver a base las 24 horas",
    Default = false,
    Callback = function(Value) Config.IgnoreDayNight = Value end
})

-- PESTAÑA 2: CONTROL Y RESCATE DE VEHÍCULO
Tabs.Vehicle:AddSection("Herramientas de Emergencia")

Tabs.Vehicle:AddButton({
    Title = "🚨 RESCATAR AUTO PERDIDO",
    Description = "Extrae el auto del abismo/cielo y te sienta adentro",
    Callback = function()
        rescueLostCar()
    end
})

Tabs.Vehicle:AddButton({
    Title = "🔧 Desbugear Auto / Frenar en Seco",
    Callback = function()
        resetVehiclePhysics()
    end
})

Tabs.Vehicle:AddSlider("CarSpeedSlider", {
    Title = "Velocidad de Movimiento",
    Default = 80,
    Min = 20,
    Max = 150,
    Rounding = 0,
    Callback = function(Value) Config.CarSpeed = Value end
})

-- PESTAÑA 3: GRABADOR
Tabs.Recorder:AddSection("Grabado de Coordenadas")

Tabs.Recorder:AddToggle("AutoRecordToggle", {
    Title = "Auto-Grabar al Moverse",
    Default = false,
    Callback = function(Value)
        Config.AutoRecord = Value
        LastRecordPos = nil
    end
})

Tabs.Recorder:AddSlider("StepDistSlider", {
    Title = "Distancia entre Bolitas (Studs)",
    Default = 30,
    Min = 15,
    Max = 70,
    Rounding = 0,
    Callback = function(Value) Config.StepDist = Value end
})

Tabs.Recorder:AddButton({
    Title = "+ Agregar Punto Aquí (Manual)",
    Callback = function()
        local root = getRootPart()
        if root then
            table.insert(Waypoints, root.Position)
            createMarker(root.Position, #Waypoints)
            Fluent:Notify({ Title = "Punto Guardado", Content = "Total: " .. #Waypoints, Duration = 1.5 })
        end
    end
})

Tabs.
