local setDead = false
local TimeToRespawn = 1
local cam
local angleY = 0.0
local angleZ = 0.0
local prompts = GetRandomIntInRange(0, 0xffffff)
local prompt
local medicprompt
local PressKey = false
local carried = false
local Done = false
local T = Translation[Lang].MessageOfSystem
local keepdown
local Dead = false
local deadcam = nil

local function CheckLabel()
    if not carried then
        if not Done then
            local label = CreateVarString(10, 'LITERAL_STRING',
                T.RespawnIn .. TimeToRespawn .. T.SecondsMove)
            return label
        else
            local label = CreateVarString(10, 'LITERAL_STRING', T.message2)
            return label
        end
    else
        local label = CreateVarString(10, 'LITERAL_STRING', T.YouAreCarried)
        return label
    end
end

local function RespawnTimer()
    TimeToRespawn = Config.RespawnTime
    CreateThread(function() -- asyncronous
        while true do
            Wait(1000)
            TimeToRespawn = TimeToRespawn - 1
            if TimeToRespawn < 0 and setDead then
                TimeToRespawn = 0
                break
            end

            if not setDead then
                TimeToRespawn = Config.RespawnTime
                break
            end
        end
    end)
end

local StartDeathCam = function()
    ClearFocus()

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local fov = GetGameplayCamFov()

    deadcam = Citizen.InvokeNative(0x40C23491CE83708E, 'DEFAULT_SCRIPTED_CAMERA', coords, 0, 0, 0, fov)

    SetCamActive(deadcam, true)
    RenderScriptCams(true, true, 1000, true, false)
end

local EndDeathCam = function()
    ClearFocus()

    RenderScriptCams(false, false, 0, true, false)
    DestroyCam(deadcam, false)

    deadcam = nil
end

local ProcessNewPosition = function()
    local mouseX = 0.0
    local mouseY = 0.0
    local ped = PlayerPedId()

    if IsInputDisabled(0) then
        mouseX = GetDisabledControlNormal(1, 0x6BC904FC) * 8.0
        mouseY = GetDisabledControlNormal(1, 0x84574AE8) * 8.0
    else
        mouseX = GetDisabledControlNormal(1, 0x6BC904FC) * 0.5
        mouseY = GetDisabledControlNormal(1, 0x84574AE8) * 0.5
    end

    angleZ = angleZ - mouseX
    angleY = angleY + mouseY

    if angleY > 89.0 then
        angleY = 89.0
    elseif angleY < -89.0 then
        angleY = -89.0
    end

    local pCoords = GetEntityCoords(ped)

    local behindCam =
    {
        x = pCoords.x + ((Cos(angleZ) * Cos(angleY)) + (Cos(angleY) * Cos(angleZ))) / 2 * (0.5 + 0.5),
        y = pCoords.y + ((Sin(angleZ) * Cos(angleY)) + (Cos(angleY) * Sin(angleZ))) / 2 * (0.5 + 0.5),
        z = pCoords.z + ((Sin(angleY))) * (0.5 + 0.5)
    }

    local rayHandle = StartShapeTestRay(pCoords.x, pCoords.y, pCoords.z + 0.5, behindCam.x, behindCam.y, behindCam.z, -1, ped, 0)

    local _, hitBool, hitCoords, _, _ = GetShapeTestResult(rayHandle)

    local maxRadius = 5.5

    if (hitBool and Vdist(pCoords.x, pCoords.y, pCoords.z + 0.0, hitCoords) < 0.5 + 0.5) then
        maxRadius = Vdist(pCoords.x, pCoords.y, pCoords.z + 0.0, hitCoords)
    end

    local offset =
    {
        x = ((Cos(angleZ) * Cos(angleY)) + (Cos(angleY) * Cos(angleZ))) / 2 * maxRadius,
        y = ((Sin(angleZ) * Cos(angleY)) + (Cos(angleY) * Sin(angleZ))) / 2 * maxRadius,
        z = ((Sin(angleY))) * maxRadius
    }

    local pos =
    {
        x = pCoords.x + offset.x,
        y = pCoords.y + offset.y,
        z = pCoords.z + offset.z
    }

    return pos
end

-- process camera controls
local ProcessCamControls = function()
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)

    -- disable 1st person as the 1st person camera can cause some glitches
    Citizen.InvokeNative(0x05AB44D906738426)

    -- calculate new position
    local newPos = ProcessNewPosition()

    -- set coords of cam
    Citizen.InvokeNative(0xF9EE7D419EE49DE6, deadcam, newPos.x, newPos.y, newPos.z)

    -- set rotation
    Citizen.InvokeNative(0x948B39341C3A40C2, deadcam, playerCoords.x, playerCoords.y, playerCoords.z)
end

function CoreAction.Player.ResurrectPlayer(currentHospital, currentHospitalName, justrevive)
    local player = PlayerPedId()
    Citizen.InvokeNative(0xCE7A90B160F75046, false) --SET_CINEMATIC_MODE_ACTIVE
    TriggerEvent("vorp:showUi", not Config.HideUi)
    ResurrectPed(player)
    Wait(200)
    EndDeathCam()
    TriggerServerEvent("vorp:ImDead", false)
    setDead = false
    DisplayHud(true)
    DisplayRadar(true)
    CoreAction.Utils.setPVP()
    TriggerEvent("vorpcharacter:reloadafterdeath")
    Wait(500)
    if currentHospital and currentHospital then
        Citizen.InvokeNative(0x203BEFFDBE12E96A, player, currentHospital, false, false, false) -- _SET_ENTITY_COORDS_AND_HEADING
    end
    Wait(2000)
    CoreAction.Admin.HealPlayer()
    if Config.RagdollOnResurrection and not justrevive then
        keepdown = true
        CreateThread(function()
            while keepdown do
                Wait(0)
                SetPedToRagdoll(player, 4000, 4000, 0, false, false, false)
                ResetPedRagdollTimer(player)
                DisablePedPainAudio(player, true)
            end
        end)
        AnimpostfxPlay("Title_Gen_FewHoursLater")
        Wait(3000)
        DoScreenFadeIn(2000)
        AnimpostfxPlay("PlayerWakeUpInterrogation")
        Wait(19000)
        keepdown = false
        VorpNotification:NotifyLeft(currentHospitalName or T.message6, T.message5, "minigames_hud", "five_finger_burnout",
            8000, "COLOR_PURE_WHITE")
    else
        -- BM Doctor
        if not LocalPlayer.state.IsUsingMedicalService then
            DoScreenFadeIn(2000)
        end
    end
    -- BM Doctor
    LocalPlayer.state:set('isdead', false, false)
end

function CoreAction.Player.RespawnPlayer()
    local player = PlayerPedId()
    TriggerServerEvent("vorp:PlayerForceRespawn")
    TriggerEvent("vorp:PlayerForceRespawn")
    local closestDistance = math.huge
    local closestLocation = ""
    local coords = nil
    local pedCoords = GetEntityCoords(player)
    for _, location in pairs(Config.Hospitals) do
        local locationCoords = vector3(location.pos.x, location.pos.y, location.pos.z)
        local currentDistance = #(pedCoords - locationCoords)

        if currentDistance < closestDistance then
            closestDistance = currentDistance
            closestLocation = location.name
            coords = location.pos
        end
    end

    TriggerEvent("vorpmetabolism:changeValue", "Thirst", 1000)
    TriggerEvent("vorpmetabolism:changeValue", "Hunger", 1000)
    CoreAction.Player.ResurrectPlayer(coords, closestLocation, false)
end

-- CREATE PROMPT
CreateThread(function()
    Wait(1000)
    local str = T.prompt
    local keyPress = Config.RespawnKey
    prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, keyPress)
    str = CreateVarString(10, 'LITERAL_STRING', str)
    PromptSetText(prompt, str)
    PromptSetEnabled(prompt, 1)
    PromptSetVisible(prompt, 1)
    PromptSetHoldMode(prompt, Config.RespawnKeyTime)
    PromptSetGroup(prompt, prompts)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, prompt, true)
    PromptRegisterEnd(prompt)

    -- BM Doctor
    str = T.medicprompt
    keyPress = Config.CallMedicKey
    medicprompt = PromptRegisterBegin()
    PromptSetControlAction(medicprompt, keyPress)
    str = CreateVarString(10, 'LITERAL_STRING', str)
    PromptSetText(medicprompt, str)
    PromptSetEnabled(medicprompt, 1)
    PromptSetVisible(medicprompt, 1)
    PromptSetHoldMode(medicprompt, Config.CallMedicKeyTime)
    PromptSetGroup(medicprompt, prompts)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, medicprompt, true)
    PromptRegisterEnd(medicprompt)
end)

-- EVENTS
RegisterNetEvent('vorp:resurrectPlayer', function(just)
    local dont = false
    local justrevive = just or true
    CoreAction.Player.ResurrectPlayer(dont, nil, justrevive)
end)

RegisterNetEvent('vorp_core:respawnPlayer', function()
    CoreAction.Player.RespawnPlayer()
end)

RegisterNetEvent("vorp_core:Client:AddTimeToRespawn")
AddEventHandler("vorp_core:Client:AddTimeToRespawn", function(time)
    if TimeToRespawn >= 1 then
        TimeToRespawn = TimeToRespawn + time
    else
        RespawnTimer()
    end
end)

AddEventHandler('vorp_core:client:StartDeathCam', function()
    CreateThread(function()
        while true do
            Wait(1000)

            if setDead and deadcam then
                local active = IsCamRendering(deadcam)

                if not active then
                    EndDeathCam()
                    StartDeathCam()
                end
            end

            if not Dead and setDead then
                Dead = true

                Citizen.InvokeNative(0x69D65E89FFD72313, true, true)

                StartDeathCam()
            elseif Dead and not setDead then
                Dead = false

                Citizen.InvokeNative(0x69D65E89FFD72313, false, false)

                EndDeathCam()
            end

            if not setDead then
                Dead = false

                Citizen.InvokeNative(0x69D65E89FFD72313, false, false)

                EndDeathCam()

                return
            end
        end
    end)
end)

AddEventHandler('vorp_core:client:StartCamControl', function()
    CreateThread(function()
        while true do
            Wait(0)

            if deadcam and Dead then
                ProcessCamControls()
            end

            if Dead and not deadcam then
                StartDeathCam()
            end

            if not setDead then return end
        end
    end)
end)

AddEventHandler('vorp_core:client:ResetPrompts', function()
    PressKey = false
end)

--DEATH HANDLER
CreateThread(function()
    repeat Wait(1000) until LocalPlayer.state.IsInSession
    while Config.UseDeathHandler do
        local sleep = 1000
        if IsPlayerDead(PlayerId()) then
            if not setDead then
                setDead = true
                PressKey = false
                PromptSetEnabled(prompt, true)
                PromptSetEnabled(medicprompt, true)
                NetworkSetInSpectatorMode(false, PlayerPedId())
                exports.spawnmanager.setAutoSpawn(false)
                TriggerServerEvent("vorp:ImDead", true)
                DisplayRadar(false)
                CreateThread(function()
                    RespawnTimer()
                    StartDeathCam()
                end)

                -- BM Doctor
                LocalPlayer.state:set('isdead', true, false)

                TriggerEvent('vorp_core:client:StartDeathCam')
                TriggerEvent('vorp_core:client:StartCamControl')
            end
            if not PressKey and setDead then
                sleep = 0
                if not IsEntityAttachedToAnyPed(PlayerPedId()) then
                    -- BM Doctor
                    if not LocalPlayer.state.IsUsingMedicalService then
                        PromptSetActiveGroupThisFrame(prompts, CheckLabel())

                        if PromptHasHoldModeCompleted(prompt) then
                            DoScreenFadeOut(3000)
                            Wait(3000)
                            CoreAction.Player.RespawnPlayer()
                            PressKey      = true
                            carried       = false
                            Done          = false
                            TimeToRespawn = Config.RespawnTime
                        end

                        if PromptHasHoldModeCompleted(medicprompt) then
                            PressKey      = true
                            carried       = false
                            Done          = false
                            TimeToRespawn = Config.RespawnTime

                            TriggerEvent('bm-doctor:client:SpawnMedic')
                        end
                    end

                    if TimeToRespawn >= 1 and setDead then
                        Done = false
                        -- BM Doctor
                        if not LocalPlayer.state.IsUsingMedicalService then
                            PromptSetEnabled(prompt, false)
                        end
                    else
                        Done = true
                        -- BM Doctor
                        if not LocalPlayer.state.IsUsingMedicalService then
                            PromptSetEnabled(prompt, true)
                        end
                    end
                    carried = false
                else
                    if setDead then
                        -- BM Doctor
                        if not LocalPlayer.state.IsUsingMedicalService then
                            PromptSetActiveGroupThisFrame(prompts, CheckLabel())
                            PromptSetEnabled(prompt, false)
                            PromptSetEnabled(medicprompt, false)
                        end
                        carried = true
                    end
                end
            end
        end

        Wait(sleep)
    end
end)
