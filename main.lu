-- ==============================================================================
-- PATROL & SURVIVAL HUB - RUTA AMARILLA DÍA/NOCHE, AUTO-EAT Y EXPORTADOR
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local lp = Players.LocalPlayer

-- Carpetas y estado
local MarkersFolder = workspace:FindFirstChild("YellowRouteMarkers")
if not MarkersFolder then
    MarkersFolder = Instance.new("Folder")
    MarkersFolder.Name = "YellowRouteMarkers"
    MarkersFolder.Parent = workspace
end

local Config = {
    PatrolRunning = false,
    WaypointWait = 0,         -- Segundos de parada por punto (por defecto 0)
    AutoRecord = false,
    StepDist = 35,            -- Distancia automática entre bolitas
    ShowMarkers = true,       -- Visibilidad de bolitas (anti-lag)

    -- Ciclo Día / Noche (ClockTime en Roblox: 0 a 24)
    DayStartHour = 6.2,       -- Hora en la que amanece y sale a patrullar
    NightReturnHour = 17.5,   -- Hora en la que regresa a la base antes de anochecer

    -- Auto-Eat
    AutoEatEnabled = true,
    EatDurationAtBase = 4,    -- Segundos comiendo antes de partir
    HungerThreshold = 75      -- Se detiene al superar el 75% de comida
}

local Waypoints = {}          -- Lista de Vector3
local MarkerInstances = {}    -- Lista de Parts
local LastRecordPos = nil
local CurrentWaypointIndex = 1
local IsReturningHome = false

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "MAP PATROL HUB",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 500),
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

-- PÁRRAFOS DE ESTADO EN VIVO
local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Estado del Sistema",
    Content = "Inactivo. Graba o importa una ruta y presiona Iniciar."
})

local TimeParagraph = Tabs.Main:AddParagraph({
    Title = "Ciclo del Mapa",
    Content = "Consultando hora del juego..."
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

-- LECTURA DE HAMBRE DEL PERSONAJE
local function getPlayerHunger()
    local char = lp.Character
    if not char then return 100 end

    -- 1. Atributo directo
    local attr = char:GetAttribute("Hunger") or char:GetAttribute("Hambre") or lp:GetAttribute("Hunger")
    if attr and type(attr) == "number" then return attr end

    -- 2. Valor dentro del modelo
    local val = char:FindFirstChild("Hunger") or char:FindFirstChild("Hambre")
    if val and val:IsA("NumberValue") or (val and val:IsA("IntValue")) then
        return val.Value
    end

    -- 3. Barra en PlayerGui (búsqueda rápida)
    local pGui = lp:FindFirstChild("PlayerGui")
    if pGui then
        for _, obj in ipairs(pGui:GetDescendants()) do
            if obj:IsA("TextLabel") and (obj.Name:lower():find("hunger") or obj.Name:lower():find("hambre")) then
                local num = tonumber(obj.Text:match("%d+"))
                if num then return num end
            end
        end
    end

    return 50 -- Si no se detecta la barra, asume un nivel medio seguro
end

-- RUTINA DE AUTO-EAT (SOLO EN EL PUNTO 1)
local function performBaseEating()
    if not Config.AutoEatEnabled then return end
    updateStatus("Base: Comiendo y recuperando energías...")

    local startTime = tick()
    while tick() - startTime < Config.EatDurationAtBase do
        task.wait(0.2)
        local hunger = getPlayerHunger()
        if hunger >= Config.HungerThreshold then
            break
        end

        -- 1. Intentar interactuar con alimentos cercanos en la base
        local root = getRootPart()
        if root then
            for _, prompt in ipairs(workspace:GetDescendants()) do
                if prompt:IsA("ProximityPrompt") then
                    local pText = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
                    if pText:find("com") or pText:find("eat") or pText:find("food") or pText:find("aliment") or pText:find("tomar") then
                        local pPart = prompt.Parent
                        if pPart and pPart:IsA("BasePart") and (pPart.Position - root.Position).Magnitude <= 15 then
                            prompt.HoldDuration = 0
                            fireproximityprompt(prompt)
                        end
                    end
                end
            end
        end

        -- 2. Equipar y usar comida del inventario si existe
        local backpack = lp:FindFirstChild("Backpack")
        local char = lp.Character
        local tool = (char and char:FindFirstChildWhichIsA("Tool")) or (backpack and backpack:FindFirstChildWhichIsA("Tool"))
        if tool then
            local tName = tool.Name:lower()
            if tName:find("food") or tName:find("comida") or tName:find("manzana") or tName:find("bread") or tName:find("meat") then
                if tool.Parent == backpack and char then
                    local hum = getHumanoid()
                    if hum then hum:EquipTool(tool) end
                end
                pcall(function() tool:Activate() end)
            end
        end
    end
end

-- CREACIÓN OPTIMIZADA DE BOLITAS (0 LAG)
local function createMarker(pos, index)
    local marker = Instance.new("Part")
    marker.Name = "RouteNode_" .. index
    marker.Shape = Enum.PartType.Ball
    marker.Size = Vector3.new(1.8, 1.8, 1.8)
    marker.Material = Enum.Material.Neon
    marker.Color = (index == 1) and Color3.fromRGB(0, 255, 120) or Color3.fromRGB(255, 220, 0) -- Verde base, amarillo ruta
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

-- MONITOR DE RELOJ Y TIEMPO DEL JUEGO
task.spawn(function()
    while true do
        task.wait(1)
        local clock = Lighting.ClockTime
        local hours = math.floor(clock)
        local mins = math.floor((clock - hours) * 60)
        local isDay = (clock >= Config.DayStartHour and clock < Config.NightReturnHour)

        TimeParagraph:SetDesc(string.format("Hora del Mapa: %02d:%02d | Estado: %s", hours, mins, isDay and "☀️ DÍA (Seguro para recorrer)" or "🌙 NOCHE (Esperando en Base)"))
    end
end)

-- PESTAÑA 1: PATRULLAJE
Tabs.Main:AddSection("Operación de la Ruta")

Tabs.Main:AddButton({
    Title = "▶ INICIAR PATRULLAJE DÍA/NOCHE",
    Callback = function()
        if #Waypoints < 2 then
            Fluent:Notify({ Title = "Ruta Insuficiente", Content = "Graba al menos 2 puntos para comenzar.", Duration = 3 })
            return
        end
        Config.PatrolRunning = true
        updateStatus("Iniciado. Evaluando ciclo día/noche...")
    end
})

Tabs.Main:AddButton({
    Title = "⏹ DETENER PATRULLAJE",
    Callback = function()
        Config.PatrolRunning = false
        IsReturningHome = false
        local hum = getHumanoid()
        local root = getRootPart()
        if hum and root then
            hum:MoveTo(root.Position)
        end
        updateStatus("Patrullaje detenido manualmente.")
    end
})

Tabs.Main:AddSlider("WaitTimeSlider", {
    Title = "Espera en cada punto (Segundos)",
    Default = 0,
    Min = 0,
    Max = 10,
    Rounding = 1,
    Callback = function(Value) Config.WaypointWait = Value end
})

-- PESTAÑA 2: GRABADOR DE RUTA
Tabs.Recorder:AddSection("Grabado Manual y Automático")

Tabs.Recorder:AddToggle("AutoRecordToggle", {
    Title = "Auto-Grabar al Caminar",
    Default = false,
    Callback = function(Value)
        Config.AutoRecord = Value
        LastRecordPos = nil
    end
})

Tabs.Recorder:AddSlider("StepDistSlider", {
    Title = "Distancia entre Bolitas (Studs)",
    Default = 35,
    Min = 15,
    Max = 80,
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
            Fluent:Notify({ Title = "Punto Guardado", Content = "Total de puntos: " .. #Waypoints, Duration = 1.5 })
        end
    end
})

Tabs.Recorder:AddButton({
    Title = "Borrar Toda la Ruta",
    Callback = function()
        table.clear(Waypoints)
        MarkersFolder:ClearAllChildren()
        table.clear(MarkerInstances)
        LastRecordPos = nil
        CurrentWaypointIndex = 1
        Fluent:Notify({ Title = "Ruta Eliminada", Content = "Se borraron todos los puntos.", Duration = 2 })
    end
})

Tabs.Recorder:AddToggle("ShowMarkersToggle", {
    Title = "Mostrar Bolitas Amarillas (Anti-Lag)",
    Description = "Desactívalo si tienes 300+ puntos para ganar el 100% de FPS",
    Default = true,
    Callback = function(Value)
        Config.ShowMarkers = Value
        for _, m in ipairs(MarkerInstances) do
            if m and m.Parent then
                m.Transparency = Value and 0 or 1
            end
        end
    end
})

-- PESTAÑA 3: IMPORTAR / EXPORTAR
Tabs.Port:AddSection("Copia de Seguridad de la Ruta")

Tabs.Port:AddButton({
    Title = "📋 EXPORTAR RUTA (Copiar al Portapapeles)",
    Description = "Copia todas las coordenadas en formato JSON para no perderlas",
    Callback = function()
        if #Waypoints == 0 then
            Fluent:Notify({ Title = "Sin Puntos", Content = "No hay puntos grabados para exportar.", Duration = 2 })
            return
        end

        local cleanData = {}
        for _, v in ipairs(Waypoints) do
            table.insert(cleanData, {math.floor(v.X * 10) / 10, math.floor(v.Y * 10) / 10, math.floor(v.Z * 10) / 10})
        end

        local jsonString = HttpService:JSONEncode(cleanData)
        if setclipboard then
            setclipboard(jsonString)
        elseif toclipboard then
            toclipboard(jsonString)
        end

        print("\n[RUTA EXPORTADA - TOTAL PUNTOS: " .. #Waypoints .. "]:\n" .. jsonString .. "\n")
        Fluent:Notify({
            Title = "¡Ruta Copiada!",
            Content = string.format("Se copiaron %d puntos al portapapeles.", #Waypoints),
            Duration = 4
        })
    end
})

local ImportInput = Tabs.Port:AddInput("ImportBox", {
    Title = "Pegar Código de Ruta aquí",
    Default = "",
    Placeholder = "Pega aquí el JSON exportado...",
    Numeric = false,
    Finished = false,
    Callback = function() end
})

Tabs.Port:AddButton({
    Title = "📥 CARGAR RUTA IMPORTADA",
    Callback = function()
        local rawText = ImportInput.Value
        if not rawText or #rawText < 5 then
            Fluent:Notify({ Title = "Texto Vacío", Content = "Pega primero el código en la casilla.", Duration = 2 })
            return
        end

        local success, decoded = pcall(function()
            return HttpService:JSONDecode(rawText)
        end)

        if success and type(decoded) == "table" then
            table.clear(Waypoints)
            for _, item in ipairs(decoded) do
                table.insert(Waypoints, Vector3.new(item[1], item[2], item[3]))
            end
            redrawAllMarkers()
            CurrentWaypointIndex = 1
            Fluent:Notify({
                Title = "Ruta Cargada",
                Content = string.format("Se cargaron %d puntos exitosamente.", #Waypoints),
                Duration = 4
            })
        else
            Fluent:Notify({ Title = "Error de Formato", Content = "El texto pegado no es un código de ruta válido.", Duration = 3 })
        end
    end
})

-- PESTAÑA 4: BASE & COMIDA
Tabs.Survival:AddSection("Auto-Alimentación en Base (Punto 1)")

Tabs.Survival:AddToggle("AutoEatToggle", {
    Title = "Activar Auto-Eat en la Base",
    Default = true,
    Callback = function(Value) Config.AutoEatEnabled = Value end
})

Tabs.Survival:AddSlider("EatDurationSlider", {
    Title = "Tiempo de comida en Base (Segundos)",
    Default = 4,
    Min = 2,
    Max = 15,
    Rounding = 0,
    Callback = function(Value) Config.EatDurationAtBase = Value end
})

Tabs.Survival:AddSlider("HungerLimitSlider", {
    Title = "Límite de saciedad (%)",
    Default = 75,
    Min = 50,
    Max = 95,
    Rounding = 0,
    Callback = function(Value) Config.HungerThreshold = Value end
})

-- PESTAÑA 5: AJUSTES DE HORARIO
Tabs.Settings:AddSection("Umbrales de Horario Día/Noche")

Tabs.Settings:AddSlider("DayStartSlider", {
    Title = "Hora de Salida matutina",
    Default = 6.2,
    Min = 5.0,
    Max = 9.0,
    Rounding = 1,
    Callback = function(Value) Config.DayStartHour = Value end
})

Tabs.Settings:AddSlider("NightReturnSlider", {
    Title = "Hora de Retiro a la Base",
    Default = 17.5,
    Min = 15.0,
    Max = 20.0,
    Rounding = 1,
    Callback = function(Value) Config.NightReturnHour = Value end
})

-- BOTÓN FLOTANTE CÍRCULAR (Y = 0.40)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PatrolHubFloatingBtn"
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

-- BUCLE DE AUTO-GRABADO AL CAMINAR
task.spawn(function()
    while true do
        task.wait(0.3)
        if Config.AutoRecord then
            local root = getRootPart()
            if root then
                local currentPos = root.Position
                if not LastRecordPos or (currentPos - LastRecordPos).Magnitude >= Config.StepDist then
                    LastRecordPos = currentPos
                    table.insert(Waypoints, currentPos)
                    createMarker(currentPos, #Waypoints)
                end
            end
        end
    end
end)

-- BUCLE MAESTRO DE PATRULLAJE Y CICLO DÍA/NOCHE
task.spawn(function()
    while true do
        task.wait(0.2)

        if Config.PatrolRunning and #Waypoints >= 2 then
            local clock = Lighting.ClockTime
            local isDay = (clock >= Config.DayStartHour and clock < Config.NightReturnHour)
            local root = getRootPart()
            local hum = getHumanoid()

            if root and hum and hum.Health > 0 then
                local basePos = Waypoints[1]

                -- CASO 1: ES DE NOCHE O ESTÁ POR ANOCHECER -> VOLVER A LA BASE
                if not isDay then
                    local distToBase = (root.Position - basePos).Magnitude

                    if distToBase > 6 then
                        updateStatus("Anocheciendo: Regresando a la Base (Punto 1)...")
                        hum:MoveTo(basePos)
                    else
                        updateStatus("Noche activa: Resguardado en la Base. Esperando el amanecer...")
                        -- Comer en la base mientras pasa la noche
                        performBaseEating()
                        task.wait(2)
                    end

                -- CASO 2: ES DE DÍA -> RECORRER LA RUTA
                else
                    -- Si apenas va a salir de la base, come primero
                    local distToBase = (root.Position - basePos).Magnitude
                    if CurrentWaypointIndex == 1 and distToBase < 8 then
                        performBaseEating()
                        CurrentWaypointIndex = 2
                    end

                    -- Avanzar al siguiente punto
                    local targetPos = Waypoints[CurrentWaypointIndex]
                    if targetPos then
                        updateStatus(string.format("Patrullando: Punto [%d / %d]", CurrentWaypointIndex, #Waypoints))
                        hum:MoveTo(targetPos)

                        local reached = false
                        local moveTimeout = tick() + 15

                        while Config.PatrolRunning and not reached and tick() < moveTimeout do
                            task.wait(0.05)
                            -- Comprobar si se hizo de noche a mitad de camino
                            local currentClock = Lighting.ClockTime
                            if not (currentClock >= Config.DayStartHour and currentClock < Config.NightReturnHour) then
                                break
                            end

                            if (root.Position - targetPos).Magnitude <= 5 then
                                reached = true
                            end
                        end

                        if reached then
                            if Config.WaypointWait > 0 then
                                task.wait(Config.WaypointWait)
                            end
                            CurrentWaypointIndex = CurrentWaypointIndex + 1
                            if CurrentWaypointIndex > #Waypoints then
                                CurrentWaypointIndex = 1 -- Bucle completo, vuelve a la base
                            end
                        end
                    end
                end
            end
        end
    end
end)

Fluent:Notify({
    Title = "MAP PATROL LISTO",
    Content = "Gestor de rutas con ciclo día/noche y exportador cargado.",
    Duration = 4
})

Window:SelectTab(1)
