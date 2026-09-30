-- ==============================================================================
-- MAP PATROL HUB - RUTA UNIVERSAL (PIE / AUTO), CICLO REAL Y AUTO-EAT
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
    WaypointWait = 0,             -- Segundos de parada por punto (por defecto 0)
    AutoRecord = false,
    StepDist = 30,                -- Distancia entre bolitas automáticas
    ShowMarkers = true,

    -- Velocidad y Movimiento
    CarSpeed = 75,                -- Velocidad de empuje si vas en auto
    WaypointTolerance = 5.5,      -- Distancia para considerar alcanzado el punto

    -- Detección Día / Noche
    IgnoreDayNight = false,       -- Si está activo, recorre las 24 horas sin volver
    ReturnEarlySeconds = 30,      -- Segundos antes de anochecer para regresar a base

    -- Auto-Eat
    AutoEatEnabled = true,
    EatDurationAtBase = 4,
    HungerThreshold = 75
}

local Waypoints = {}
local MarkerInstances = {}
local LastRecordPos = nil
local CurrentWaypointIndex = 1
local IsDaytimeGlobal = true
local SecondsUntilNight = 999

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
    Survival = Window:AddTab({ Title = "Base & Comida", Icon = "coffee" }),
    Settings = Window:AddTab({ Title = "Ajustes", Icon = "settings" })
}

-- PÁRRAFOS DE ESTADO
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

-- DETECTOR AVANZADO DEL CICLO DÍA / NOCHE (LEE LA PANTALLA Y EL RELOJ)
local function scanGameDayNight()
    if Config.IgnoreDayNight then
        IsDaytimeGlobal = true
        SecondsUntilNight = 999
        return true, 999
    end

    local detectedDay = true
    local remainingSecs = 999

    -- 1. Buscar en la interfaz de pantalla (PlayerGui) por texto de tiempo y estado
    local pGui = lp:FindFirstChild("PlayerGui")
    if pGui then
        for _, lbl in ipairs(pGui:GetDescendants()) do
            if lbl:IsA("TextLabel") and lbl.Visible then
                local txt = lbl.Text:lower()
                
                -- Detectar si dice explícitamente Noche
                if txt:find("noche") or txt:find("night") then
                    detectedDay = false
                end

                -- Detectar cronómetro mm:ss (ej: 03:45 o 00:25)
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

    -- 2. Verificación secundaria con la luz del mapa (Lighting)
    local clock = Lighting.ClockTime
    if clock < 5.8 or clock > 18.2 then
        detectedDay = false
    end

    IsDaytimeGlobal = detectedDay
    SecondsUntilNight = remainingSecs
    return detectedDay, remainingSecs
end

-- MONITOR DE ESTADO EN PANTALLA
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

-- SISTEMA DE MOVIMIENTO UNIVERSAL (PIE Y AUTO CON ANTI-ATASCO)
local function navigateToPosition(targetPos, timeoutSecs)
    local timeout = tick() + (timeoutSecs or 20)
    local lastPos = nil
    local stuckFrames = 0

    while Config.PatrolRunning and tick() < timeout do
        RunService.Heartbeat:Wait()

        local root = getRootPart()
        local hum = getHumanoid()
        local car, seat = getCurrentVehicle()

        if not root or not hum or hum.Health <= 0 then return false end

        -- Distancia horizontal
        local myPos = (car and seat) and seat.Position or root.Position
        local delta = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
        local dist = delta.Magnitude

        if dist <= Config.WaypointTolerance then
            if seat then
                seat.Throttle = 0
                seat.AssemblyLinearVelocity = Vector3.new(0, seat.AssemblyLinearVelocity.Y, 0)
            end
            return true
        end

        -- Detección de atascos (salto o impulso si no avanza)
        if lastPos and (myPos - lastPos).Magnitude < 0.2 then
            stuckFrames = stuckFrames + 1
            if stuckFrames >= 30 then
                if not car then
                    hum.Jump = true
                else
                    seat.AssemblyLinearVelocity = seat.AssemblyLinearVelocity + Vector3.new(0, 15, 0)
                end
                stuckFrames = 0
            end
        else
            stuckFrames = 0
            lastPos = myPos
        end

        -- A) MOVIMIENTO EN AUTO
        if car and seat then
            seat.Throttle = 1
            -- Orientar suavemente hacia el punto
            car:PivotTo(CFrame.new(myPos, Vector3.new(targetPos.X, myPos.Y, targetPos.Z)))
            local driveVel = delta.Unit * Config.CarSpeed
            seat.AssemblyLinearVelocity = Vector3.new(driveVel.X, seat.AssemblyLinearVelocity.Y, driveVel.Z)
        
        -- B) MOVIMIENTO A PIE
        else
            hum:MoveTo(targetPos)
        end
    end

    return false
end

-- LECTURA DE HAMBRE DEL PERSONAJE
local function getPlayerHunger()
    local char = lp.Character
    if not char then return 100 end

    local val = char:FindFirstChild("Hunger") or char:FindFirstChild("Hambre")
    if val and (val:IsA("NumberValue") or val:IsA("IntValue")) then
        return val.Value
    end

    local pGui = lp:FindFirstChild("PlayerGui")
    if pGui then
        for _, obj in ipairs(pGui:GetDescendants()) do
            if obj:IsA("TextLabel") and (obj.Name:lower():find("hunger") or obj.Name:lower():find("hambre")) then
                local num = tonumber(obj.Text:match("%d+"))
                if num then return num end
            end
        end
    end
    return 50
end

-- AUTO-EAT EN EL PUNTO 1
local function performBaseEating()
    if not Config.AutoEatEnabled then return end
    updateStatus("Base: Comiendo...")

    local start = tick()
    while tick() - start < Config.EatDurationAtBase do
        task.wait(0.2)
        if getPlayerHunger() >= Config.HungerThreshold then break end

        local root = getRootPart()
        if root then
            for _, prompt in ipairs(workspace:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") then
                    local pText = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
                    if pText:find("com") or pText:find("eat") or pText:find("food") or pText:find("manzana") then
                        local pPart = prompt.Parent
                        if pPart and pPart:IsA("BasePart") and (pPart.Position - root.Position).Magnitude <= 15 then
                            prompt.HoldDuration = 0
                            fireproximityprompt(prompt)
                        end
                    end
                end
            end
        end

        local backpack = lp:FindFirstChild("Backpack")
        local char = lp.Character
        local tool = (char and char:FindFirstChildWhichIsA("Tool")) or (backpack and backpack:FindFirstChildWhichIsA("Tool"))
        if tool and (tool.Name:lower():find("food") or tool.Name:lower():find("comida") or tool.Name:lower():find("manzana")) then
            if tool.Parent == backpack and char then
                local hum = getHumanoid()
                if hum then hum:EquipTool(tool) end
            end
            pcall(function() tool:Activate() end)
        end
    end
end

-- CREACIÓN OPTIMIZADA DE BOLITAS (0 LAG PARA 500+ PUNTOS)
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

-- PESTAÑA 1: PATRULLAJE
Tabs.Main:AddSection("Control de Ruta")

Tabs.Main:AddButton({
    Title = "▶ INICIAR PATRULLAJE",
    Callback = function()
        if #Waypoints < 2 then
            Fluent:Notify({ Title = "Ruta Vacía", Content = "Importa o graba puntos primero.", Duration = 3 })
            return
        end
        Config.PatrolRunning = true
        updateStatus("Iniciado. Evaluando condiciones...")
    end
})

Tabs.Main:AddButton({
    Title = "⏹ DETENER PATRULLAJE",
    Callback = function()
        Config.PatrolRunning = false
        local hum = getHumanoid()
        local root = getRootPart()
        if hum and root then hum:MoveTo(root.Position) end
        local _, seat = getCurrentVehicle()
        if seat then seat.Throttle = 0 end
        updateStatus("Detenido manualmente.")
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
    Description = "Actívalo si no quieres que regrese a la base y recorra las 24 horas",
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

-- PESTAÑA 4: BASE & COMIDA
Tabs.Survival:AddSection("Auto-Alimentación en Base (Punto 1)")

Tabs.Survival:AddToggle("AutoEatToggle", {
    Title = "Activar Auto-Eat al Salir de Base",
    Default = true,
    Callback = function(Value) Config.AutoEatEnabled = Value end
})

Tabs.Survival:AddSlider("EatTimeSlider", {
    Title = "Segundos comiendo en Base",
    Default = 4,
    Min = 2,
    Max = 12,
    Rounding = 0,
    Callback = function(Value) Config.EatDurationAtBase = Value end
})

-- PESTAÑA 5: AJUSTES
Tabs.Settings:AddSection("Retiro Preventivo y Vehículo")

Tabs.Settings:AddSlider("ReturnEarlySlider", {
    Title = "Segundos de anticipación antes de noche",
    Description = "Tiempo antes de anochecer para abortar y volver a base",
    Default = 30,
    Min = 10,
    Max = 60,
    Rounding = 0,
    Callback = function(Value) Config.ReturnEarlySeconds = Value end
})

Tabs.Settings:AddSlider("CarSpeedSlider", {
    Title = "Fuerza de empuje del auto",
    Default = 75,
    Min = 30,
    Max = 140,
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

-- BUCLE MAESTRO DE PATRULLAJE
task.spawn(function()
    while true do
        task.wait(0.15)

        if Config.PatrolRunning and #Waypoints >= 2 then
            local isDay, secsLeft = scanGameDayNight()
            local basePos = Waypoints[1]
            local root = getRootPart()

            if root then
                -- ¿Debe retirarse a la base? (Es de noche o faltan pocos segundos para anochecer)
                local shouldBeAtBase = (not isDay) or (secsLeft <= Config.ReturnEarlySeconds)

                if shouldBeAtBase and not Config.IgnoreDayNight then
                    local distToBase = (root.Position - basePos).Magnitude
                    if distToBase > Config.WaypointTolerance then
                        updateStatus(string.format("⚠️ Anocheciendo (%ds restantes): Volviendo a Base...", secsLeft))
                        navigateToPosition(basePos, 30)
                    else
                        updateStatus("🌙 Resguardado en Base (Punto 1). Esperando amanecer...")
                        performBaseEating()
                        task.wait(2)
                    end
                else
                    -- ES DE DÍA: Recorrer ruta secuencial
                    if CurrentWaypointIndex == 1 then
                        local distToBase = (root.Position - basePos).Magnitude
                        if distToBase <= Config.WaypointTolerance + 4 then
                            performBaseEating()
                        end
                        CurrentWaypointIndex = 2
                    end

                    local target = Waypoints[CurrentWaypointIndex]
                    if target then
                        updateStatus(string.format("Patrullando: Punto [%d / %d]", CurrentWaypointIndex, #Waypoints))
                        local reached = navigateToPosition(target, 20)

                        if reached then
                            if Config.WaypointWait > 0 then
                                task.wait(Config.WaypointWait)
                            end
                            CurrentWaypointIndex = CurrentWaypointIndex + 1
                            if CurrentWaypointIndex > #Waypoints then
                                CurrentWaypointIndex = 1
                            end
                        end
                    end
                end
            end
        end
    end
end)

Fluent:Notify({
    Title = "MAP PATROL HUB LISTO",
    Content = "Motor universal para auto/a pie y detector de pantalla activos.",
    Duration = 4
})

Window:SelectTab(1)
