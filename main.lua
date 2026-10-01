-- ==============================================================================
-- MAP PATROL HUB - DESATASCO CON PAUSA DE 3.5s, SUSPENSIÓN SEGURA Y RETORNO
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

    -- Desatasco inteligente seguro
    UnstuckEnabled = true
}

local Waypoints = {}
local MarkerInstances = {}
local LastRecordPos = nil
local PatrolThread = nil
local ConsecutiveSkips = 0

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "MAP PATROL HUB | 500+ NODOS",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(590, 510),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Patrullaje", Icon = "play" }),
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
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local carModel = seat:FindFirstAncestorOfClass("Model")
        return carModel, seat
    end
    return nil, nil
end

-- DETECTOR DE DÍA / NOCHE
local function scanGameDayNight()
    if Config.IgnoreDayNight then
        return true, 999
    end

    local detectedDay = true
    local remainingSecs = 999

    local pGui = lp:FindFirstChild("PlayerGui")
    if pGui then
        for _, lbl in ipairs(pGui:GetDescendants()) do
            if lbl:IsA("TextLabel") and lbl.Visible then
                local txt = lbl.Text:lower()
                if txt:find("noche") or txt:find("night") then
                    detectedDay = false
                end
                local m, s = txt:match("(%d+):(%d+)")
                if m and s and not txt:find("revivir") and not txt:find("espera") then
                    remainingSecs = (tonumber(m) * 60) + tonumber(s)
                end
            end
        end
    end

    local clock = Lighting.ClockTime
    if clock < 5.8 or clock > 18.2 then
        detectedDay = false
    end

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

-- SISTEMA DE DESATASCO CON PAUSA DE 3.5s Y SUSPENSIÓN PROTEGIDA
local function performSafeUnstuck(lastSafePos)
    if not Config.UnstuckEnabled then return end

    local car, seat = getCurrentVehicle()
    local root = getRootPart()
    local controlledPart = seat or root
    if not controlledPart then return end

    -- PASO 1: FRENAR EN SECO Y ESTABILIZAR (3.5 segundos para que repose en el suelo)
    updateStatus("⚠️ Atasco detectado: Frenando y estabilizando 3.5s...")
    if seat then
        seat.Throttle = 0
        seat.Steer = 0
        seat.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        seat.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
    task.wait(3.5)

    if not Config.PatrolRunning then return end

    updateStatus("⚠️ Desatascando: Elevación suave y salida...")

    -- PASO 2: ELEVAR SUAVEMENTE 4 STUDS Y APUNTAR AL CAMINO LIBRE
    if car and seat then
        local currentPos = seat.Position
        local targetLook = lastSafePos and Vector3.new(lastSafePos.X, currentPos.Y, lastSafePos.Z) or (currentPos - seat.CFrame.LookVector * 10)
        pcall(function()
            car:PivotTo(CFrame.new(currentPos + Vector3.new(0, 4.0, 0), targetLook))
        end)
        seat.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        seat.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    else
        if root then
            root.CFrame = root.CFrame + Vector3.new(0, 4.0, 0)
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        end
    end

    -- PASO 3: NOCLIP QUIRÚRGICO (PROTEGIENDO RUEDAS PARA NO BUGUEAR LA SUSPENSIÓN)
    local char = lp.Character
    local noclipConn = RunService.Stepped:Connect(function()
        if car then
            for _, p in ipairs(car:GetDescendants()) do
                if p:IsA("BasePart") then
                    local n = p.Name:lower()
                    -- REGLA DE ORO: Las ruedas y resortes NUNCA pierden colisión
                    if not n:find("wheel") and not n:find("tire") and not n:find("rueda") and not n:find("llanta") and not n:find("susp") then
                        p.CanCollide = false
                    end
                end
            end
        end
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end)

    -- Acelerar hacia adelante para salir de la pared
    if seat then
        seat.Throttle = 1
        seat.AssemblyLinearVelocity = controlledPart.CFrame.LookVector * 40
    end
    task.wait(1.0)

    -- PASO 4: APAGAR NOCLIP Y RESTAURAR FÍSICAS EN EL SUELO
    noclipConn:Disconnect()
    task.wait(0.1)

    if car then
        for _, p in ipairs(car:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end
    if char then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end

    -- Anular cualquier velocidad residual para que no quede flotando
    if seat then
        seat.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        seat.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
end

-- MANIOBRAS DE ESCAPE LARGAS
local function evasiveManeuver(attempt, lastSafePos)
    local root = getRootPart()
    local car, seat = getCurrentVehicle()
    local controlledPart = seat or root
    if not controlledPart then return end

    local cf = controlledPart.CFrame

    if car and seat then
        if attempt == 1 then
            -- Intento 1: Reversa larga con giro a la derecha
            seat.Throttle = -1
            seat.AssemblyLinearVelocity = (-cf.LookVector * 50) + (cf.RightVector * 35)
            task.wait(0.65)
            seat.Throttle = 1
            seat.AssemblyLinearVelocity = (cf.RightVector * 40) + Vector3.new(0, 5, 0)
            task.wait(0.5)
        elseif attempt == 2 then
            -- Intento 2: Reversa larga con giro a la izquierda
            seat.Throttle = -1
            seat.AssemblyLinearVelocity = (-cf.LookVector * 50) - (cf.RightVector * 35)
            task.wait(0.65)
            seat.Throttle = 1
            seat.AssemblyLinearVelocity = (-cf.RightVector * 40) + Vector3.new(0, 5, 0)
            task.wait(0.5)
        elseif attempt == 3 then
            -- Intento 3: Reversa recta prolongada
            seat.Throttle = -1
            seat.AssemblyLinearVelocity = (-cf.LookVector * 60)
            task.wait(0.8)
            seat.Throttle = 1
            task.wait(0.3)
        elseif attempt >= 4 then
            -- Intento 4: Pausa 3.5s + Elevación + Noclip protegido
            performSafeUnstuck(lastSafePos)
        end
    else
        local hum = getHumanoid()
        if hum then
            hum.Jump = true
            local sideDir = (attempt % 2 == 1) and cf.RightVector or -cf.RightVector
            controlledPart.AssemblyLinearVelocity = (-cf.LookVector * 30) + (sideDir * 30)
            task.wait(0.5)
            if attempt >= 4 then
                performSafeUnstuck(lastSafePos)
            end
        end
    end
end

-- MOVIMIENTO HACIA UN PUNTO INDIVIDUAL
local function walkOrDriveTo(targetPos, maxTime)
    local startT = tick()
    local reached = false

    while Config.PatrolRunning and (tick() - startT < maxTime) do
        local root = getRootPart()
        local hum = getHumanoid()
        local car, seat = getCurrentVehicle()

        if not root or not hum or hum.Health <= 0 then break end

        local myPos = (car and seat) and seat.Position or root.Position
        local delta = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
        local dist = delta.Magnitude

        local tolerance = (car and seat) and 9.5 or 5.0
        if dist <= tolerance then
            reached = true
            break
        end

        if car and seat then
            seat.Throttle = 1
            if delta.Magnitude > 2 then
                pcall(function()
                    car:PivotTo(CFrame.new(myPos, Vector3.new(targetPos.X, myPos.Y, targetPos.Z)))
                end)
            end
            local dir = delta.Unit
            seat.AssemblyLinearVelocity = Vector3.new(dir.X * Config.CarSpeed, seat.AssemblyLinearVelocity.Y, dir.Z * Config.CarSpeed)
        else
            hum:MoveTo(targetPos)
        end

        task.wait(0.1)
    end

    return reached
end

-- INTENTAR HASTA 4 VECES CON ESQUIVES LARGOS
local function moveToPointWithRetry(targetPos, lastSafePos)
    for attempt = 1, 4 do
        if not Config.PatrolRunning then return false end
        local success = walkOrDriveTo(targetPos, 3.8)
        if success then
            return true
        else
            if attempt < 4 then
                evasiveManeuver(attempt, lastSafePos)
            else
                evasiveManeuver(4, lastSafePos)
            end
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

-- DETENER TODO EN SECO Y RESTAURAR FÍSICAS
local function stopPatrol()
    Config.PatrolRunning = false
    if PatrolThread then
        task.cancel(PatrolThread)
        PatrolThread = nil
    end

    local hum = getHumanoid()
    local root = getRootPart()
    if hum and root then hum:MoveTo(root.Position) end

    local car, seat = getCurrentVehicle()
    if seat then
        seat.Throttle = 0
        seat.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        seat.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end

    -- Restaurar colisiones en todo el vehículo
    if car then
        for _, p in ipairs(car:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end

    updateStatus("Patrullaje detenido. Físicas restauradas.")
end

-- INICIAR: VA AL PUNTO 1 (CON DESATASCO), ESPERA 5s Y RECORRE
local function startPatrol()
    if #Waypoints < 2 then
        Fluent:Notify({ Title = "Sin Puntos", Content = "Carga o graba puntos primero.", Duration = 3 })
        return
    end

    stopPatrol()
    Config.PatrolRunning = true
    ConsecutiveSkips = 0

    PatrolThread = task.spawn(function()
        -- 1. Ir al Punto 1 (Base) con protección
        updateStatus("Iniciando: Yendo al Punto 1...")
        local reachedP1 = moveToPointWithRetry(Waypoints[1], Waypoints[1])
        if not reachedP1 then
            performSafeUnstuck(Waypoints[1])
            moveToPointWithRetry(Waypoints[1], Waypoints[1])
        end

        if not Config.PatrolRunning then return end

        -- 2. Esperar 5 segundos en el Punto 1
        for s = 5, 1, -1 do
            if not Config.PatrolRunning then return end
            updateStatus(string.format("En Punto 1: Esperando %d segundos...", s))
            task.wait(1)
        end

        -- 3. Recorrer todos los demás puntos continuamente
        while Config.PatrolRunning do
            for i = 2, #Waypoints do
                if not Config.PatrolRunning then break end

                -- Chequeo de Noche (15s antes: Regreso en reversa por la ruta)
                local isDay, secsLeft = scanGameDayNight()
                if (not isDay or secsLeft <= Config.ReturnEarlySeconds) and not Config.IgnoreDayNight then
                    updateStatus(string.format("⚠️ Anocheciendo (%ds): Regresando en reversa...", secsLeft))

                    for backIdx = i - 1, 1, -1 do
                        if not Config.PatrolRunning then break end
                        local d, s = scanGameDayNight()
                        if d and s > Config.ReturnEarlySeconds then break end

                        updateStatus(string.format("Retorno nocturno: Nodo [%d / 1]", backIdx))
                        local safePrev = Waypoints[math.min(#Waypoints, backIdx + 1)]
                        local reachedBack = moveToPointWithRetry(Waypoints[backIdx], safePrev)

                        if not reachedBack then
                            ConsecutiveSkips = ConsecutiveSkips + 1
                            if ConsecutiveSkips >= 2 then
                                performSafeUnstuck(safePrev)
                                ConsecutiveSkips = 0
                            end
                        else
                            ConsecutiveSkips = 0
                        end
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
                updateStatus(string.format("Caminando: Punto [%d / %d]", i, #Waypoints))
                local prevPos = Waypoints[i - 1]
                local reached = moveToPointWithRetry(Waypoints[i], prevPos)

                if not reached then
                    ConsecutiveSkips = ConsecutiveSkips + 1
                    if ConsecutiveSkips >= 2 then
                        performSafeUnstuck(prevPos)
                        ConsecutiveSkips = 0
                    end
                else
                    ConsecutiveSkips = 0
                end
            end

            -- Al completar toda la ruta, vuelve en reversa al Punto 1
            if Config.PatrolRunning then
                updateStatus("Fin de ruta. Regresando en reversa a Punto 1...")
                for backIdx = #Waypoints - 1, 1, -1 do
                    if not Config.PatrolRunning then break end
                    local safePrev = Waypoints[math.min(#Waypoints, backIdx + 1)]
                    local reachedBack = moveToPointWithRetry(Waypoints[backIdx], safePrev)
                    if not reachedBack then
                        ConsecutiveSkips = ConsecutiveSkips + 1
                        if ConsecutiveSkips >= 2 then
                            performSafeUnstuck(safePrev)
                            ConsecutiveSkips = 0
                        end
                    else
                        ConsecutiveSkips = 0
                    end
                end
                task.wait(1)
            end
        end
    end)
end

-- PESTAÑA 1: PATRULLAJE
Tabs.Main:AddSection("Control de Ruta")

Tabs.Main:AddButton({
    Title = "▶ INICIAR PATRULLAJE",
    Description = "Va a Punto 1, espera 5s y recorre todos los puntos sin frenar",
    Callback = function()
        startPatrol()
    end
})

Tabs.Main:AddButton({
    Title = "⏹ DETENER PATRULLAJE",
    Description = "Cancela todo y frena al muñeco/auto de inmediato",
    Callback = function()
        stopPatrol()
    end
})

Tabs.Main:AddToggle("IgnoreDayNightToggle", {
    Title = "Forzar Modo Día (Ignorar Noche)",
    Description = "Recorre sin volver a base las 24 horas",
    Default = false,
    Callback = function(Value) Config.IgnoreDayNight = Value end
})

-- PESTAÑA 2: GRABADOR
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

Tabs.Recorder:AddButton({
    Title = "Borrar Todos los Puntos",
    Callback = function()
        table.clear(Waypoints)
        MarkersFolder:ClearAllChildren()
        table.clear(MarkerInstances)
        LastRecordPos = nil
        Fluent:Notify({ Title = "Ruta Borrada", Content = "Puntos eliminados.", Duration = 2 })
    end
})

Tabs.Recorder:AddToggle("ShowMarkersToggle", {
    Title = "Mostrar Bolitas Amarillas (Anti-Lag)",
    Default = true,
    Callback = function(Value)
        Config.ShowMarkers = Value
        for _, m in ipairs(MarkerInstances) do
            if m and m.Parent then m.Transparency = Value and 0 or 1 end
        end
    end
})

-- PESTAÑA 3: IMPORTAR / EXPORTAR
Tabs.Port:AddSection("Copia de Seguridad JSON")

Tabs.Port:AddButton({
    Title = "📋 EXPORTAR RUTA (Copiar al Portapapeles)",
    Callback = function()
        if #Waypoints == 0 then
            Fluent:Notify({ Title = "Sin Puntos", Content = "No hay puntos para exportar.", Duration = 2 })
            return
        end

        local clean = {}
        for _, v in ipairs(Waypoints) do
            table.insert(clean, {math.floor(v.X * 10) / 10, math.floor(v.Y * 10) / 10, math.floor(v.Z * 10) / 10})
        end

        local json = HttpService:JSONEncode(clean)
        if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end
        print("\n[RUTA EXPORTADA - PUNTOS: " .. #Waypoints .. "]:\n" .. json .. "\n")
        Fluent:Notify({ Title = "¡Copiado!", Content = string.format("%d puntos copiados.", #Waypoints), Duration = 3 })
    end
})

local ImportInput = Tabs.Port:AddInput("ImportBox", {
    Title = "Pegar JSON de Ruta Aquí",
    Default = "",
    Placeholder = "Pega aquí las coordenadas...",
    Numeric = false,
    Finished = false,
    Callback = function() end
})

Tabs.Port:AddButton({
    Title = "📥 CARGAR RUTA IMPORTADA",
    Callback = function()
        local txt = ImportInput.Value
        if not txt or #txt < 5 then
            Fluent:Notify({ Title = "Vacío", Content = "Pega el texto primero.", Duration = 2 })
            return
        end

        local ok, decoded = pcall(function() return HttpService:JSONDecode(txt) end)
        if ok and type(decoded) == "table" then
            table.clear(Waypoints)
            for _, pt in ipairs(decoded) do
                table.insert(Waypoints, Vector3.new(pt[1], pt[2], pt[3]))
            end
            redrawAllMarkers()
            Fluent:Notify({ Title = "Ruta Cargada", Content = string.format("Cargados %d puntos.", #Waypoints), Duration = 4 })
        else
            Fluent:Notify({ Title = "Error", Content = "Formato de texto inválido.", Duration = 3 })
        end
    end
})

-- PESTAÑA 4: AJUSTES
Tabs.Settings:AddSection("Anti-Atasco Seguro y Vehículo")

Tabs.Settings:AddToggle("UnstuckToggle", {
    Title = "Auto-Desatasco con Pausa (3.5s)",
    Description = "Estabiliza el auto 3.5s, eleva suavemente y protege la suspensión",
    Default = true,
    Callback = function(Value) Config.UnstuckEnabled = Value end
})

Tabs.Settings:AddSlider("CarSpeedSlider", {
    Title = "Fuerza de empuje del auto",
    Default = 80,
    Min = 30,
    Max = 150,
    Rounding = 0,
    Callback = function(Value) Config.CarSpeed = Value end
})

-- BOTÓN FLOTANTE CÍRCULAR (Y = 0.40)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MapPatrolFloatBtn"
ScreenGui.ResetOnSpawn = false
if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
else
    ScreenGui.Parent = lp:WaitForChild("PlayerGui")
end

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0.04, 0, 0.40, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(255, 190, 0)
FloatBtn.Image = "rbxassetid://10723415903"
FloatBtn.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(1, 0)
UICorner.Parent = FloatBtn

local isWindowOpen = true
FloatBtn.MouseButton1Click:Connect(function()
    isWindowOpen = not isWindowOpen
    Window.Root.Visible = isWindowOpen
end)

-- BUCLE DE GRABADO
task.spawn(function()
    while true do
        task.wait(0.3)
        if Config.AutoRecord then
            local root = getRootPart()
            if root then
                local myPos = root.Position
                if not LastRecordPos or (myPos - LastRecordPos).Magnitude >= Config.StepDist then
                    LastRecordPos = myPos
                    table.insert(Waypoints, myPos)
                    createMarker(myPos, #Waypoints)
                end
            end
        end
    end
end)

Fluent:Notify({
    Title = "MAP PATROL HUB LISTO",
    Content = "Pausa de 3.5s y suspensión protegida configuradas.",
    Duration = 4
})

Window:SelectTab(1)
