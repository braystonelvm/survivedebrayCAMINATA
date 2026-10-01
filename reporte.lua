-- ==============================================================================
-- SURVIVAL UTILITY HUB | AUTO-EAT, REPARACIÓN FANTASMA Y ANTI-EXPLOSIONES
-- ==============================================================================

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local Config = {
    -- Hambre / Auto-Eat
    AutoEat = true,
    TargetHunger = 75,           -- Límite configurable (por defecto 75%)
    EatDelay = 0.4,

    -- Reparación Fantasma (Estilo ZHUB)
    AutoRepair = true,
    RepairSpeed = 0.08,          -- Milisegundos entre martillazos
    RepairRadius = 25,

    -- Inmunidad a Explosiones (Auto)
    AntiExplosionPush = true,
    MaxAllowedPush = 45          -- Límite de aceleración normal antes de neutralizar
}

-- Lista de comidas confirmadas
local FOOD_NAMES = {
    "carrot", "bloxy cola", "cake", "chips", "mre",
    "apple", "bread", "soup", "cookie", "ration", "canned"
}

-- 1. VENTANA PRINCIPAL
local Window = Fluent:CreateWindow({
    Title = "SURVIVAL UTILITIES",
    SubTitle = "Sobrevive al Apocalipsis",
    TabWidth = 160,
    Size = UDim2.fromOffset(560, 460),
    Acrylic = true,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Eat = Window:AddTab({ Title = "Auto-Eat", Icon = "coffee" }),
    Repair = Window:AddTab({ Title = "Reparación ZHUB", Icon = "hammer" }),
    Vehicle = Window:AddTab({ Title = "Anti-Explosión", Icon = "shield" })
}

-- PESTAÑA 1: AUTO-EAT
local HungerParagraph = Tabs.Eat:AddParagraph({
    Title = "Hambre Actual",
    Content = "Leyendo atributo..."
})

Tabs.Eat:AddToggle("AutoEatToggle", {
    Title = "Activar Auto-Eat",
    Default = true,
    Callback = function(v) Config.AutoEat = v end
})

Tabs.Eat:AddSlider("HungerLimitSlider", {
    Title = "Límite de Saciedad Deseado (%)",
    Description = "El script dejará de consumir cuando tu hambre llegue aquí",
    Default = 75,
    Min = 30,
    Max = 100,
    Rounding = 0,
    Callback = function(v) Config.TargetHunger = v end
})

-- PESTAÑA 2: REPARACIÓN FANTASMA
Tabs.Repair:AddParagraph({
    Title = "Sistema ZHUB",
    Content = "Repara autos y muros usando 'Repair Hammer' y regresa de inmediato al arma que tenías en mano."
})

Tabs.Repair:AddToggle("AutoRepairToggle", {
    Title = "Reparación Rápida con Martillo",
    Default = true,
    Callback = function(v) Config.AutoRepair = v end
})

Tabs.Repair:AddSlider("RepairDelaySlider", {
    Title = "Velocidad de Martillazo (Segundos)",
    Default = 0.08,
    Min = 0.03,
    Max = 0.35,
    Rounding = 2,
    Callback = function(v) Config.RepairSpeed = v end
})

-- PESTAÑA 3: ANTI-EXPLOSIÓN
Tabs.Vehicle:AddParagraph({
    Title = "Inmunidad al Empuje de Bloaters",
    Content = "Elimina la onda expansiva y bloquea los picos de velocidad que hacen volar tu auto."
})

Tabs.Vehicle:AddToggle("AntiExploToggle", {
    Title = "Inmunidad a Explosiones en Auto",
    Default = true,
    Callback = function(v) Config.AntiExplosionPush = v end
})

-- BOTÓN FLOTANTE CÍRCULAR (Y = 0.40)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SurvivalUtilFloatBtn"
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
FloatBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
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

-- FUNCIONES AUXILIARES
local function getExactHunger()
    local char = lp.Character
    if char then
        local val = char:GetAttribute("Hunger")
        if val and type(val) == "number" then
            return math.floor(val)
        end
    end
    return 100
end

local function getFoodTool()
    local char = lp.Character
    local bp = lp:FindFirstChild("Backpack")

    -- 1. En mano
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") then
                local n = item.Name:lower()
                for _, f in ipairs(FOOD_NAMES) do
                    if n:find(f) then return item, true end
                end
            end
        end
    end

    -- 2. En mochila
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") then
                local n = item.Name:lower()
                for _, f in ipairs(FOOD_NAMES) do
                    if n:find(f) then return item, false end
                end
            end
        end
    end

    return nil, false
end

-- BUCLE 1: AUTO-EAT EXACTO (BASADO EN EL ATRIBUTO "Hunger")
task.spawn(function()
    while true do
        task.wait(Config.EatDelay)

        local currentHunger = getExactHunger()
        HungerParagraph:SetDesc(string.format("Hambre: %d%% | Límite objetivo: %d%%", currentHunger, Config.TargetHunger))

        if Config.AutoEat and currentHunger < Config.TargetHunger then
            local char = lp.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                -- A) Comer de inventario
                local food, isEquipped = getFoodTool()
                if food then
                    if not isEquipped then
                        hum:EquipTool(food)
                        task.wait(0.08)
                    end
                    pcall(function() food:Activate() end)
                else
                    -- B) Comer de ProximityPrompts cercanos (zanahorias en el suelo o mesas)
                    local root = char:FindFirstChild("HumanoidRootPart")
                    if root then
                        for _, prompt in ipairs(workspace:GetDescendants()) do
                            if prompt:IsA("ProximityPrompt") then
                                local text = (prompt.ObjectText .. " " .. prompt.ActionText):lower()
                                local isF = false
                                for _, fn in ipairs(FOOD_NAMES) do
                                    if text:find(fn) or text:find("eat") or text:find("comer") then
                                        isF = true
                                        break
                                    end
                                end

                                if isF then
                                    local part = prompt.Parent
                                    if part and part:IsA("BasePart") and (part.Position - root.Position).Magnitude <= 14 then
                                        prompt.HoldDuration = 0
                                        fireproximityprompt(prompt)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- BUCLE 2: AUTO-REPARACIÓN FANTASMA CON SWAP INSTANTÁNEO (ZHUB REPAIR)
task.spawn(function()
    while true do
        task.wait(Config.RepairSpeed)

        if Config.AutoRepair then
            local char = lp.Character
            local bp = lp:FindFirstChild("Backpack")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if char and hum and bp and hum.Health > 0 then
                -- Buscar el Repair Hammer confirmado en el reporte
                local hammerInChar = char:FindFirstChild("Repair Hammer")
                local hammerInBp = bp:FindFirstChild("Repair Hammer")
                local hammer = hammerInChar or hammerInBp

                if hammer then
                    -- Detectar qué arma tienes en mano antes de reparar
                    local weaponEquipped = nil
                    for _, item in ipairs(char:GetChildren()) do
                        if item:IsA("Tool") and item ~= hammer then
                            weaponEquipped = item
                            break
                        end
                    end

                    -- Ejecutar reparación directa mediante su RemoteEvent interno o activación
                    local repairEvent = hammer:FindFirstChild("Repair")
                    if repairEvent and repairEvent:IsA("RemoteEvent") then
                        pcall(function() repairEvent:FireServer() end)
                    end

                    -- Si no estaba equipado, hacer el swap fantasma
                    if hammerInBp then
                        hum:EquipTool(hammer)
                        pcall(function() hammer:Activate() end)
                        task.wait(0.04)

                        -- Regresar instantáneamente al arma original
                        if weaponEquipped and weaponEquipped.Parent == bp then
                            hum:EquipTool(weaponEquipped)
                        end
                    else
                        pcall(function() hammer:Activate() end)
                    end
                end
            end
        end
    end
end)

-- BUCLE 3: INMUNIDAD A EXPLOSIONES EN EL VEHÍCULO (ANTI-KNOCKBACK)
local lastSafeLinearVelocity = Vector3.new(0, 0, 0)

RunService.Heartbeat:Connect(function()
    if not Config.AntiExplosionPush then return end

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    -- 1. Neutralizar presión de cualquier objeto Explosión en el juego
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Explosion") then
            obj.BlastPressure = 0 -- Cero fuerza destructiva de empuje
        end
    end

    -- 2. Si estás dentro del auto, absorber el impacto violento de los Bloaters
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local currentVel = seat.AssemblyLinearVelocity

        -- Si la velocidad horizontal pega un salto brusco (explosión de zombie)
        local hVel = Vector3.new(currentVel.X, 0, currentVel.Z).Magnitude
        local lastHVel = Vector3.new(lastSafeLinearVelocity.X, 0, lastSafeLinearVelocity.Z).Magnitude

        if (hVel - lastHVel) > Config.MaxAllowedPush then
            -- Anular la explosión: restablecer la velocidad previa y evitar que gire en el aire
            seat.AssemblyLinearVelocity = Vector3.new(lastSafeLinearVelocity.X, currentVel.Y, lastSafeLinearVelocity.Z)
            seat.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        else
            lastSafeLinearVelocity = currentVel
        end
    end
end)

Fluent:Notify({
    Title = "SURVIVAL UTILITIES LISTO",
    Content = "Auto-Eat (Hunger), Martillo ZHUB y Anti-Explosiones activos.",
    Duration = 4
})

Window:SelectTab(1)
