-- ==============================================================================
-- MAP PATROL HUB - 4 INTENTOS, RETORNO EN REVERSA Y DESATASCO CON NOCLIP 1s
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

    -- Desatasco inteligente
    UnstuckFlyEnabled = true      -- Toggle para el impulso arriba + noclip 1s
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

-- MANIOBRA EVASIVA LATERAL (CADA VEZ QUE SE CHOQUE)
local function evasiveManeuver(attempt)
    local root = getRootPart()
    local car, seat = getCurrentVehicle()
    local controlledPart = seat or root
    if not controlledPart then return end

    local cf = controlledPart.CFrame
    -- Intento 1 y 3: Derecha | Intento 2 y 4: Izquierda
    local sideDir = (attempt % 2 == 1) and cf.RightVector or -cf.RightVector

    if car and seat then
        seat.Throttle = -1
        seat.AssemblyLinearVelocity = (-cf.LookVector * 40) + (sideDir * 30)
        task.wait(0.35)
        seat.Throttle = 1
        seat.AssemblyLinearVelocity = (sideDir * 35) + Vector3.new(0, 10, 0)
        task.wait(0.25)
    else
        local hum = getHumanoid()
        if hum then
            hum.Jump = true
            controlledPart.AssemblyLinearVelocity = (-cf.LookVector * 25) + (sideDir * 25)
            task.wait(0.3)
        end
    end
end

-- SISTEMA DE DESATASCO (SUBIDA PREVENTIVA + NOCLIP 1s)
local function performUnstuckManeuver()
    if not Config.UnstuckFlyEnabled then return end
    updateStatus("⚠️ Atasco detectado: Elevando auto y Noclip 1s...")

    local car, seat = getCurrentVehicle()
    local root = getRootPart()
    local controlledPart = seat or root
    if not controlledPart then return end

    -- 1. Impulso hacia arriba primero (evita hundirse al activar noclip)
    controlledPart.AssemblyLinearVelocity = Vector3.new(0, 50, 0)
    task.wait(0.15)

    -- 2. Activar Noclip durante 1 segundo exacto
    local char = lp.Character
    local noclipConn = RunService.Stepped:Connect(function()
        if car then
            for _, p in ipairs(car:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end)

    -- Mantener el vehículo flotando y avanzando mientras atraviesa el obstáculo
    controlledPart.AssemblyLinearVelocity = Vector3.new(controlledPart.AssemblyLinearVelocity.X, 20, controlledPart.AssemblyLinearVelocity.Z)
    task.wait(1.0)

    -- 3. Desactivar Noclip y restaurar físicas
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

-- INTENTAR HASTA 4 VECES CON ESQUIVE LATERAL
local function moveToPointWithRetry(targetPos)
    for attempt = 1, 4 do
        if not Config.PatrolRunning then return false end
        local success = walkOrDriveTo(targetPos, 3.8)
        if success then
            return true
        else
            if attempt < 4 then
                evasiveManeuver(attempt)
            end
        end
    end
    return false -- Si falló los 4 intentos, se omite
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

-- DETENER TODO EN SECO
local function stopPatrol()
    Config.PatrolRunning = false
    if PatrolThread then
        task.cancel(PatrolThread)
        PatrolThread = nil
    end

    local hum = getHumanoid()
    local root = getRootPart()
    if hum and root then hum:MoveTo(root.Position) end

    local _, seat = getCurrentVehicle()
    if seat then
        seat.Throttle = 0
        seat.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end

    updateStatus("Patrullaje cancelado y detenido por completo.")
end

-- INICIAR: VA AL PUNTO 1, ESPERA 5s Y RECORRE
local function startPatrol()
    if #Waypoints < 2 then
        Fluent:Notify({ Title = "Sin Puntos", Content = "Carga o graba puntos primero.", Duration = 3 })
        return
    end

    stopPatrol()
    Config.PatrolRunning = true
    ConsecutiveSkips = 0

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

        -- 3. Recorrer todos los demás puntos continuamente
        while Config.PatrolRunning do
            for i = 2, #Waypoints do
                if not Config.PatrolRunning then break end

                -- Chequeo de Noche (15s antes de la noche: Regreso en reversa por la ruta)
                local isDay, secsLeft = scanGameDayNight()
                if (not isDay or secsLeft <= Config.ReturnEarlySeconds) and not Config.IgnoreDayNight then
                    updateStatus(string.format("⚠️ Anocheciendo (%ds): Regresando en reversa por la ruta...", secsLeft))
                    
                    -- Retrocede nodo por nodo desde el actual hasta el Punto 1
                    for backIdx = i - 1, 1, -1 do
                        if not Config.PatrolRunning then break end
                        local d, s = scanGameDayNight()
                        if d and s > Config.ReturnEarlySeconds then
                            break -- Si amanece antes de llegar, continúa el avance
                        end
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
                updateStatus(string.format("Caminando: Punto [%d / %d]", i, #Waypoints))
                local reached = moveToPointWithRetry(Waypoints[i])

                -- Detección de omisiones para aplicar Auto-Desatasco
                if not reached then
                    ConsecutiveSkips = ConsecutiveSkips + 1
                    if ConsecutiveSkips >= 2 then
                        performUnstuckManeuver()
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
                    moveToPointWithRetry(Waypoints[backIdx])
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
    Description = "Cancela todo y frena al muñeco de inmediato",
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
Tabs.Settings:AddSection("Anti-Atasco y Vehículo")

Tabs.Settings:AddToggle("UnstuckFlyToggle", {
    Title = "Auto-Desatasco (Subida + Noclip 1s)",
    Description = "Si omite 2 puntos seguidos por atasco, eleva el auto y activa noclip 1 segundo",
    Default = true,
    Callback = function(Value) Config.UnstuckFlyEnabled = Value end
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
    Content = "4 intentos, retorno inverso y desatasco de 1s activos.",
    Duration = 4
})

Window:SelectTab(1)
