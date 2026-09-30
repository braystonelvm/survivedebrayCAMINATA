-- ==============================================================================
-- MAP PATROL HUB - RUTA CONTINUA (PIE / AUTO) CON RETORNO A LOS 15s
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
    WaypointWait = 0,             -- Segundos de parada por punto (0 = continuo)
    AutoRecord = false,
    StepDist = 30,
    ShowMarkers = true,

    -- Vehículo y Movimiento
    CarSpeed = 80,

    -- Detección Día / Noche
    IgnoreDayNight = false,
    ReturnEarlySeconds = 15       -- 15 segundos antes de la noche regresa a base
}

local Waypoints = {}
local MarkerInstances = {}
local LastRecordPos = nil
local CurrentWaypointIndex = 1
local PatrolThread = nil
local WaypointTimeoutTick = 0

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "MAP PATROL HUB | 500+ NODOS",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(590, 520),
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
    Title = "Ciclo Detectado en Vivo",
    Content = "Analizando pantalla..."
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

-- DETECTOR DEL TIEMPO Y CRONÓMETRO DE PANTALLA
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
                if m and s then
                    local total = (tonumber(m) * 60) + tonumber(s)
                    if not txt:find("revivir") and not txt:find("espera") then
                        remainingSecs = total
                    end
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

-- MONITOR DE PANTALLA
task.spawn(function()
    while true do
        task.wait(0.5)
        local isDay, secs = scanGameDayNight()
        local car = getCurrentVehicle()
        local modeText = car and "🚗 EN VEHÍCULO" or "🏃 A PIE"

        if Config.IgnoreDayNight then
            CycleParagraph:SetDesc(string.format("Modo: %s | Ciclo: ☀️ DÍA FORZADO (24h Activo)", modeText))
        else
            local timeInfo = (secs < 900) and string.format(" (Quedan: %ds)", secs) or ""
            CycleParagraph:SetDesc(string.format("Modo: %s | Ciclo: %s%s", modeText, isDay and "☀️ DÍA" or "🌙 NOCHE", timeInfo))
        end
    end
end)

-- CREACIÓN OPTIMIZADA DE BOLITAS (0 LAG)
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

-- DETENER PATRULLAJE
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
        seat.AssemblyLinearVelocity = Vector3.new(0, seat.AssemblyLinearVelocity.Y, 0)
    end
    updateStatus("Patrullaje detenido.")
end

-- INICIAR PATRULLAJE CONTINUO
local function startPatrol()
    if #Waypoints < 2 then
        Fluent:Notify({ Title = "Ruta Vacía", Content = "Carga tu JSON de puntos primero.", Duration = 3 })
        return
    end

    stopPatrol()
    Config.PatrolRunning = true
    CurrentWaypointIndex = (CurrentWaypointIndex > #Waypoints) and 1 or CurrentWaypointIndex
    WaypointTimeoutTick = tick() + 12

    PatrolThread = task.spawn(function()
        while Config.PatrolRunning do
            RunService.Heartbeat:Wait()

            pcall(function()
                local isDay, secsLeft = scanGameDayNight()
                local basePos = Waypoints[1]
                local root = getRootPart()
                local hum = getHumanoid()
                local car, seat = getCurrentVehicle()

                if not root or not hum or hum.Health <= 0 then return end

                local myPos = (car and seat) and seat.Position or root.Position
                local shouldReturnHome = (not isDay) or (secsLeft <= Config.ReturnEarlySeconds)

                -- CASO NOCHE / RETORNO PREVENTIVO A LOS 15s
                if shouldReturnHome and not Config.IgnoreDayNight then
                    local deltaHome = Vector3.new(basePos.X - myPos.X, 0, basePos.Z - myPos.Z)
                    local distHome = deltaHome.Magnitude
                    local baseRadius = car and 12 or 6

                    if distHome <= baseRadius then
                        updateStatus("🌙 Resguardado en Base (Punto 1). Esperando día...")
                        if seat then
                            seat.Throttle = 0
                            seat.AssemblyLinearVelocity = Vector3.new(0, seat.AssemblyLinearVelocity.Y, 0)
                        else
                            hum:MoveTo(basePos)
                        end
                    else
                        updateStatus(string.format("⚠️ Anocheciendo (%ds): Volviendo a Base...", secsLeft))
                        if car and seat then
                            seat.Throttle = 1
                            if deltaHome.Magnitude > 2 then
                                pcall(function()
                                    car:PivotTo(CFrame.new(myPos, Vector3.new(basePos.X, myPos.Y, basePos.Z)))
                                end)
                            end
                            local dir = deltaHome.Unit
                            seat.AssemblyLinearVelocity = Vector3.new(dir.X * Config.CarSpeed, seat.AssemblyLinearVelocity.Y, dir.Z * Config.CarSpeed)
                        else
                            hum:MoveTo(basePos)
                        end
                    end

                -- CASO DÍA: RECORRIDO CONTINUO EN BUCLE
                else
                    if CurrentWaypointIndex < 1 or CurrentWaypointIndex > #Waypoints then
                        CurrentWaypointIndex = 1
                    end

                    local target = Waypoints[CurrentWaypointIndex]
                    if target then
                        updateStatus(string.format("Patrullando: Punto [%d / %d]", CurrentWaypointIndex, #Waypoints))

                        local delta = Vector3.new(target.X - myPos.X, 0, target.Z - myPos.Z)
                        local dist = delta.Magnitude
                        local tolerance = car and 9.5 or 5.0

                        -- PUNTO ALCANZADO O TIEMPO LÍMITE (PASA AL SIGUIENTE AL INSTANTE)
                        if dist <= tolerance or tick() > WaypointTimeoutTick then
                            if Config.WaypointWait > 0 and dist <= tolerance then
                                task.wait(Config.WaypointWait)
                            end

                            CurrentWaypointIndex = CurrentWaypointIndex + 1
                            if CurrentWaypointIndex > #Waypoints then
                                CurrentWaypointIndex = 1
                            end
                            WaypointTimeoutTick = tick() + 12
                        else
                            -- CONDUCIR O CAMINAR HACIA EL PUNTO
                            if car and seat then
                                seat.Throttle = 1
                                if delta.Magnitude > 2 then
                                    pcall(function()
                                        car:PivotTo(CFrame.new(myPos, Vector3.new(target.X, myPos.Y, target.Z)))
                                    end)
                                end
                                local dir = delta.Unit
                                seat.AssemblyLinearVelocity = Vector3.new(dir.X * Config.CarSpeed, seat.AssemblyLinearVelocity.Y, dir.Z * Config.CarSpeed)
                            else
                                hum:MoveTo(target)
                            end
                        end
                    end
                end
            end)
        end
    end)
end

-- PESTAÑA 1: PATRULLAJE
Tabs.Main:AddSection("Control de Ruta")

Tabs.Main:AddButton({
    Title = "▶ INICIAR PATRULLAJE",
    Callback = function()
        startPatrol()
    end
})

Tabs.Main:AddButton({
    Title = "⏹ DETENER PATRULLAJE",
    Callback = function()
        stopPatrol()
    end
})

Tabs.Main:AddSlider("WaitTimeSlider", {
    Title = "Espera en cada punto (Seg)",
    Default = 0,
    Min = 0,
    Max = 8,
    Rounding = 1,
    Callback = function(Value) Config.WaypointWait = Value end
})

Tabs.Main:AddToggle("IgnoreDayNightToggle", {
    Title = "Forzar Modo Día (Ignorar Noche)",
    Description = "Actívalo si quieres que recorra el mapa sin volver a base",
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
        CurrentWaypointIndex = 1
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
            CurrentWaypointIndex = 1
            Fluent:Notify({ Title = "Ruta Cargada", Content = string.format("Cargados %d puntos.", #Waypoints), Duration = 4 })
        else
            Fluent:Notify({ Title = "Error", Content = "Formato de texto inválido.", Duration = 3 })
        end
    end
})

-- PESTAÑA 4: AJUSTES
Tabs.Settings:AddSection("Retiro Preventivo y Vehículo")

Tabs.Settings:AddSlider("ReturnEarlySlider", {
    Title = "Segundos de anticipación antes de noche",
    Default = 15,
    Min = 5,
    Max = 45,
    Rounding = 0,
    Callback = function(Value) Config.ReturnEarlySeconds = Value end
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
    Content = "Ruta continua y retorno a los 15s activos.",
    Duration = 4
})

Window:SelectTab(1)
