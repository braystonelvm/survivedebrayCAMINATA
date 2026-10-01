-- ==============================================================================
-- INMUNIDAD TOTAL A EXPLOSIONES Y ATURDIMIENTO (ANTI-STUN + ANTI-PUSH)
-- ==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local Config = {
    AntiStun = true,            -- Desactiva el aturdimiento de inmediato
    AntiFlip = true,            -- Evita que el auto se voltee o gire en el aire
    NeutralizeExplosions = true, -- Fuerza BlastPressure = 0
    RepelAura = true,           -- Empuja Bloaters a distancia antes de que toquen el auto
    RepelRadius = 32            -- Rango del escudo repelente
}

local function getRoot()
    local char = lp.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function getCurrentVehicle()
    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.SeatPart and hum.SeatPart:IsA("VehicleSeat") then
        local seat = hum.SeatPart
        local carModel = seat:FindFirstAncestorOfClass("Model")
        local mainPart = carModel and (carModel.PrimaryPart or seat) or seat
        return carModel, seat, mainPart
    end
    return nil, nil, nil
end

-- 1. ANTI-STUN INSTANTÁNEO (LEE Y RESETEA EL ATRIBUTO "Stunned")
RunService.Heartbeat:Connect(function()
    if not Config.AntiStun then return end

    local char = lp.Character
    if char then
        -- Forzar atributo a false si el juego intentó aturdirte
        if char:GetAttribute("Stunned") == true then
            char:SetAttribute("Stunned", false)
        end

        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            if hum.PlatformStand then hum.PlatformStand = false end
            if hum.Sit == false and hum.SeatPart then hum.Sit = true end
        end
    end
end)

-- 2. NEUTRALIZAR TODAS LAS EXPLOSIONES DEL JUEGO
workspace.DescendantAdded:Connect(function(desc)
    if Config.NeutralizeExplosions and desc:IsA("Explosion") then
        desc.BlastPressure = 0
        desc.BlastRadius = 0
    end
end)

-- 3. ESTABILIZADOR ANTI-VUELCO Y REPELENTE DE BLOATERS A ALTA VELOCIDAD
RunService.Stepped:Connect(function()
    local car, seat, mainPart = getCurrentVehicle()
    local root = getRoot()
    local centerPart = mainPart or seat or root
    if not centerPart then return end

    -- A) Estabilizar vehículo: Anula giros descontrolados (Roll y Pitch)
    if Config.AntiFlip and seat then
        local currentRot = seat.AssemblyAngularVelocity
        -- Solo permite girar hacia los lados (Yaw / Eje Y), bloquea vuelcos en X y Z
        seat.AssemblyAngularVelocity = Vector3.new(0, currentRot.Y, 0)
    end

    -- B) Escudo Repelente: Detecta Bloaters antes de que detonen en tu cara
    if Config.RepelAura then
        local charFolder = workspace:FindFirstChild("Characters") or workspace
        local myPos = centerPart.Position

        for _, entity in ipairs(charFolder:GetChildren()) do
            if entity:IsA("Model") and entity ~= lp.Character and not Players:GetPlayerFromCharacter(entity) then
                local name = entity.Name:lower()
                -- Identificar Bloaters y zombies suicidas/explosivos
                if name:find("bloat") or name:find("boom") or name:find("explo") or name:find("bomb") then
                    local eRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso")
                    if eRoot then
                        local toZombie = (eRoot.Position - myPos)
                        local dist = toZombie.Magnitude

                        -- Si entra al radio del escudo, lo expulsa hacia arriba y atrás
                        if dist <= Config.RepelRadius then
                            local pushDir = Vector3.new(toZombie.Unit.X, 1.2, toZombie.Unit.Z).Unit
                            eRoot.AssemblyLinearVelocity = pushDir * 95
                        end
                    end
                end
            end
        end
    end
end)

print("[INMUNIDAD ACTIVA]: Anti-Stun, Estabilizador Anti-Vuelco y Escudo Anti-Bloaters funcionando.")
