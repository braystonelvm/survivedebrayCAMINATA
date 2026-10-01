-- ==============================================================================
-- EXTRACTOR DE DATOS / INSPECTOR EN VIVO (COPIADO AUTOMÁTICO AL PORTAPAPELES)
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")

local report = {}
local function log(str)
    table.insert(report, str)
    print(str)
end

log("=================== REPORTE DE INSPECCIÓN DE DATOS ===================")
log("Fecha/Hora: " .. os.date("%Y-%m-%d %H:%M:%S"))

-- 1. INSPECCIÓN DE LA BARRA DE HAMBRE / INTERFAZ
log("\n--- [1. INTERFAZ / PLAYERGUI (HAMBRE Y VALORES)] ---")
local pGui = lp:FindFirstChild("PlayerGui")
if pGui then
    for _, gui in ipairs(pGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled then
            for _, desc in ipairs(gui:GetDescendants()) do
                local name = desc.Name:lower()
                -- Buscar textos y números de interés
                if desc:IsA("TextLabel") and desc.Visible then
                    local txt = desc.Text
                    if txt:find("%d") or name:find("hung") or name:find("hambre") or name:find("bar") or name:find("food") then
                        log(string.format("TextLabel: [%s] | Ruta: %s | Texto actual: '%s'", desc.Name, desc:GetFullName(), txt))
                    end
                elseif (desc:IsA("NumberValue") or desc:IsA("IntValue")) then
                    log(string.format("ValueObject: [%s] | Ruta: %s | Valor: %s", desc.Name, desc:GetFullName(), tostring(desc.Value)))
                elseif desc:IsA("Frame") or desc:IsA("ImageLabel") then
                    if name:find("hung") or name:find("hambre") or name:find("food") or name:find("bar") then
                        log(string.format("Barra/Elemento: [%s] | Tipo: %s | Size: (X: %.2f, Y: %.2f)", desc.Name, desc.ClassName, desc.Size.X.Scale, desc.Size.Y.Scale))
                    end
                end
            end
        end
    end
else
    log("PlayerGui no disponible.")
end

-- Atributos del jugador / personaje
log("\n--- [Atributos del Jugador/Personaje] ---")
for k, v in pairs(lp:GetAttributes()) do log(string.format("Player Attr: %s = %s", k, tostring(v))) end
for k, v in pairs(char:GetAttributes()) do log(string.format("Character Attr: %s = %s", k, tostring(v))) end

-- 2. INSPECCIÓN DE HERRAMIENTAS Y MARTILLO
log("\n--- [2. MOCHILA E ÍTEMS EN MANO] ---")
local function scanTools(container, label)
    if not container then return end
    for _, item in ipairs(container:GetChildren()) do
        if item:IsA("Tool") then
            log(string.format("Herramienta en %s: [%s]", label, item.Name))
            for _, sub in ipairs(item:GetChildren()) do
                if sub:IsA("RemoteEvent") or sub:IsA("RemoteFunction") or sub:IsA("Animation") then
                    log(string.format("   -> Recurso interno: [%s] (%s)", sub.Name, sub.ClassName))
                end
            end
            for k, v in pairs(item:GetAttributes()) do
                log(string.format("   -> Atributo: %s = %s", k, tostring(v)))
            end
        end
    end
end
scanTools(char, "Mano / Character")
scanTools(lp:FindFirstChild("Backpack"), "Mochila / Backpack")

-- 3. INSPECCIÓN DEL VEHÍCULO ACTUAL
log("\n--- [3. VEHÍCULO / ASIENTO] ---")
if hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
    local seat = hum.SeatPart
    local car = seat:FindFirstAncestorOfClass("Model")
    log(string.format("Montado en Asiento: [%s] | Modelo del Auto: [%s]", seat.Name, car and car.Name or "Desconocido"))
    log(string.format("Masa del asiento: %.1f | AssemblyMass: %.1f", seat.Mass, seat.AssemblyMass))
    if car then
        for k, v in pairs(car:GetAttributes()) do
            log(string.format("Auto Attr: %s = %s", k, tostring(v)))
        end
        for _, obj in ipairs(car:GetChildren()) do
            if obj:IsA("NumberValue") or obj:IsA("IntValue") or obj.Name:lower():find("health") or obj.Name:lower():find("vida") then
                log(string.format("Valor en Auto: [%s] (%s) = %s", obj.Name, obj.ClassName, tostring(obj.Value)))
            end
        end
    end
else
    log("No estás sentado en un vehículo en este momento.")
end

-- 4. REMOTES CLAVE EN REPLICATEDSTORAGE
log("\n--- [4. EVENTOS DE RED (REMOTES RELEVANTES)] ---")
for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
        local n = obj.Name:lower()
        if n:find("eat") or n:find("com") or n:find("repair") or n:find("mart") or n:find("dam") or n:find("hit") or n:find("interact") then
            log(string.format("Remote: [%s] | Ruta: %s", obj.Name, obj:GetFullName()))
        end
    end
end

log("\n=================== FIN DEL REPORTE ===================")

local fullText = table.concat(report, "\n")
if setclipboard then
    setclipboard(fullText)
elseif toclipboard then
    toclipboard(fullText)
end

warn("[INSPECTOR COMPLETO]: Todo el reporte fue copiado al portapapeles exitosamente.")
