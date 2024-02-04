local QBCore = exports['qb-core']:GetCoreObject()
local currentHouse, closestHouse
local enterZones, enterTargets, insideTargets, inside, currentCops, houses = {}, {}, {}, false, 0, {}

-- Functions
local function loadAnimDict(dict)
    RequestAnimDict(dict)
    while (not HasAnimDictLoaded(dict)) do Wait(5) end
end

local function openHouseAnim()
    loadAnimDict('anim@heists@keycard@')
    TaskPlayAnim(PlayerPedId(), 'anim@heists@keycard@', 'exit', 5.0, 1.0, -1, 16, 0, 0, 0, 0)
    Wait(400)
    ClearPedTasks(PlayerPedId())
end

local function searchCabin(cabin)
    local ped = PlayerPedId()
    if math.random(1, 100) <= 85 and not QBCore.Functions.IsWearingGloves() then
        local pos = GetEntityCoords(PlayerPedId())
        TriggerServerEvent('evidence:server:CreateFingerDrop', pos)
    end

    loadAnimDict('creatures@rottweiler@tricks@')
    TaskPlayAnim(PlayerPedId(), 'creatures@rottweiler@tricks@', 'petting_franklin', 8.0, 8.0, -1, 17, 0, false, false, false)

    TriggerServerEvent('qb-houserobbery:server:SetBusyState', cabin, currentHouse, true)
    FreezeEntityPosition(ped, true)
    IsLockpicking = true

    local succeededAttempts = 0
    local neededAttempts = 4
    local Skillbar = exports['qb-skillbar']:GetSkillbarObject()
    Skillbar.Start({
        duration = math.random(4500, 7000),
        pos = math.random(10, 30),
        width = math.random(10, 20),
    }, function()
        if succeededAttempts + 1 >= neededAttempts then
            ClearPedTasks(PlayerPedId())
            TriggerServerEvent('qb-houserobbery:server:searchFurniture', cabin, currentHouse)
            houses[currentHouse].furniture[cabin].searched = true
            TriggerServerEvent('qb-houserobbery:server:SetBusyState', cabin, currentHouse, false)
            succeededAttempts = 0
            FreezeEntityPosition(ped, false)
            SetTimeout(500, function()
                IsLockpicking = false
            end)
        else
            Skillbar.Repeat({
                duration = math.random(2000, 4000),
                pos = math.random(10, 40),
                width = math.random(10, 13),
            })
            succeededAttempts = succeededAttempts + 1
        end
    end, function()
        ClearPedTasks(PlayerPedId())
        TriggerServerEvent('qb-houserobbery:server:SetBusyState', cabin, currentHouse, false)
        QBCore.Functions.Notify(Lang:t('error.process_cancelled'), 'error', 3500)
        succeededAttempts = 0
        FreezeEntityPosition(ped, false)
        SetTimeout(500, function()
            IsLockpicking = false
        end)
    end)
end

local function teardownTargets(targets)
    for i = 1, #targets do
        exports['qb-target']:RemoveZone(targets[i])
    end
    return {}
end

local function leaveRobberyHouse(house, houseObj)
    local ped = PlayerPedId()
    insideTargets = teardownTargets(insideTargets)
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'houses_door_open', 0.25)
    openHouseAnim()
    Wait(250)
    DoScreenFadeOut(250)
    Wait(500)
    exports['qb-interior']:DespawnInterior(houseObj, function()
        TriggerEvent('qb-weathersync:client:EnableSync')
        Wait(250)
        DoScreenFadeIn(250)
        SetEntityCoords(ped, houses[house].coords.x, houses[house].coords.y, houses[house].coords.z + 0.5)
        SetEntityHeading(ped, houses[house].coords.h)
        inside = false
        currentHouse = nil
    end)
end

local function enterRobberyHouse(house)
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'houses_door_open', 0.25)
    openHouseAnim()
    Wait(250)
    local coords = { x = houses[house].coords.x, y = houses[house].coords.y, z = houses[house].coords.z - Config.MinZOffset }
    local data = exports['qb-interior']:CreateHouseRobbery(coords)
    if not data then return end

    local houseObj = data[1]
    local POIOffsets = data[2]
    inside = true
    currentHouse = house
    local exitCoords = vector3(
        houses[house]['coords']['x'] + POIOffsets.exit.x,
        houses[house]['coords']['y'] + POIOffsets.exit.y,
        houses[house]['coords']['z'] - Config.MinZOffset + POIOffsets.exit.z)
    Wait(500)
    TriggerEvent('qb-weathersync:client:DisableSync')

    insideTargets = teardownTargets(insideTargets)
    insideTargets[#insideTargets+1] = house .. '_exit'
    exports['qb-target']:AddBoxZone(house .. '_exit', exitCoords, 2.0, 3.0, {
        name = house .. '_exit',
        minZ = exitCoords.z - 1.0,
        maxZ = exitCoords.z + 2.0,
        debugPoly = Config.Debug,
    }, {
        options = {
            {
                label = Lang:t('info.hleave'),
                icon = 'fas fa-door-open',
                action = function()
                    leaveRobberyHouse(currentHouse, houseObj)
                end,
            },
        },
        distance = 2.0,
    })
    for i = 1, #houses[house].furniture do
        insideTargets[#insideTargets+1] = house .. '_furniture_' .. i
        local furnCoords = vector3(
            houses[house].coords.x + houses[house].furniture[i].coords.x,
            houses[house].coords.y + houses[house].furniture[i].coords.y,
            houses[house].coords.z + houses[house].furniture[i].coords.z - Config.MinZOffset)
        exports['qb-target']:AddCircleZone(house .. '_furniture_' .. i, furnCoords, 1.0, {
            name = house .. '_furniture_' .. i,
            useZ = true,
            data = {
                house = house,
            },
            debugPoly = Config.Debug,
        }, {
            options = {
                {
                    label = houses[house].furniture[i].text,
                    icon = 'fas fa-magnifying-glass',
                    action = function()
                        searchCabin(i)
                    end,
                    canInteract = function()
                        return not (houses[currentHouse].furniture[i].searched or houses[currentHouse].furniture[i].isBusy)
                    end,
                },
            },
            distance = 1.5,
        })
    end
end

local function alertCops()
    if math.random(1, 100) < Config.ChanceToAlertPolice then
        exports['ps-dispatch']:HouseRobbery()
    end
end

local function setupEnterTargets()
    teardownTargets(enterZones)

    local requiredItems = {
        [1] = { name = QBCore.Shared.Items['advancedlockpick']['name'], image = QBCore.Shared.Items['advancedlockpick']['image'] },
        [2] = { name = QBCore.Shared.Items['screwdriverset']['name'], image = QBCore.Shared.Items['screwdriverset']['image'] },
    }

    for house, data in pairs(houses) do
        enterZones[#enterZones+1] = BoxZone:Create(vector3(data.coords.x, data.coords.y, data.coords.z), 2.0, 1.5, {
            name = house .. '_door',
            heading = data.coords.h,
            minZ = data.coords.z - 1.0,
            maxZ = data.coords.z + 2.0,
            data = {
                house = house,
            },
            debugPoly = Config.Debug,
        })

        enterZones[#enterZones]:onPlayerInOut(function(isPlayerInside)
            closestHouse = isPlayerInside and house or nil
            TriggerEvent('inventory:client:requiredItems', requiredItems, (not houses[house].opened and isPlayerInside))
        end)

        enterTargets[#enterTargets+1] = exports['qb-target']:AddBoxZone(house .. '_enter', vector3(data.coords.x, data.coords.y, data.coords.z), 2.0, 1.5, {
            name = house .. '_enter',
            heading = data.coords.h,
            minZ = data.coords.z - 1.0,
            maxZ = data.coords.z + 2.0,
            data = {
                house = house,
            },
        }, {
            options = {
                {
                    label = Lang:t('info.henter'),
                    icon = 'fas fa-door-open',
                    action = function()
                        TriggerEvent('inventory:client:requiredItems', requiredItems, false)
                        enterRobberyHouse(closestHouse)
                    end,
                    canInteract = function()
                        return closestHouse and houses[closestHouse].opened
                    end,
                },
            },
            distance = 2.0,
        })
    end
end

-- Events
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    QBCore.Functions.TriggerCallback('qb-houserobbery:server:GetHouseConfig', function(HouseConfig)
        houses = HouseConfig
        setupEnterTargets()
    end)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData.citizenid then return end
    QBCore.Functions.TriggerCallback('qb-houserobbery:server:GetHouseConfig', function(HouseConfig)
        houses = HouseConfig
        setupEnterTargets()
    end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    teardownTargets(insideTargets)
    teardownTargets(enterTargets)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    teardownTargets(insideTargets)
    teardownTargets(enterTargets)
end)

RegisterNetEvent('qb-houserobbery:client:ResetHouseState', function(house)
    houses[house].opened = false
    for _, v in pairs(houses[house].furniture) do
        v.searched = false
    end
end)

RegisterNetEvent('police:SetCopCount', function(amount)
    currentCops = amount
end)

RegisterNetEvent('qb-houserobbery:client:enterHouse', function(house)
    enterRobberyHouse(house)
end)

RegisterNetEvent('qb-houserobbery:client:setHouseState', function(house, state)
    houses[house].opened = state
end)

RegisterNetEvent('qb-houserobbery:client:setCabinState', function(house, cabin, state)
    houses[house].furniture[cabin].searched = state
end)

RegisterNetEvent('qb-houserobbery:client:SetBusyState', function(cabin, house, bool)
    houses[house].furniture[cabin].isBusy = bool
end)

RegisterNetEvent('lockpicks:UseLockpick', function(isAdvanced)
    TriggerServerEvent('police:server:UpdateCurrentCops')
    Wait(100)

    if Config.UseClockHours then
        if GetClockHours() < Config.MinimumTime or GetClockHours() > Config.MaximumTime then
            QBCore.Functions.Notify(Lang:t('error.not_allowed_time'), 'error', 3500)
            return
        end
    end

    if closestHouse ~= nil then
        if currentCops >= Config.PoliceOnDutyRequired then
            if not houses[closestHouse].opened then
                if not isAdvanced then
                    if Config.RequireScrewdriver and not QBCore.Functions.HasItem('screwdriverset') then
                        QBCore.Functions.Notify(Lang:t('error.missing_something'), 'error', 3500)
                        return
                    end
                end

                loadAnimDict('mp_missheist_countrybank@nervous')
                TaskPlayAnim(PlayerPedId(), 'mp_missheist_countrybank@nervous', 'nervous_idle', 8.0, 8.0, -1, 49, 0.0, false, false, false)
                alertCops()

                TriggerEvent('qb-lockpick:client:openLockpick', function(success)
                    ClearPedTasks(PlayerPedId())
                    if success then
                        TriggerServerEvent('qb-houserobbery:server:enterHouse', closestHouse)
                        QBCore.Functions.Notify(Lang:t('success.worked'), 'success', 2500)
                    else
                        if isAdvanced then
                            if math.random(1, 100) <= Config.ChanceToBreakAdvancedLockPick then
                                TriggerServerEvent('qb-houserobbery:server:removeAdvancedLockpick')
                                TriggerEvent('inventory:client:ItemBox', QBCore.Shared.Items['advancedlockpick'], 'remove')
                            end
                        else
                            if math.random(1, 100) <= Config.ChanceToBreakLockPick then
                                TriggerServerEvent('qb-houserobbery:server:removeLockpick')
                                TriggerEvent('inventory:client:ItemBox', QBCore.Shared.Items['lockpick'], 'remove')
                            end
                        end
                        QBCore.Functions.Notify(Lang:t('error.didnt_work'), 'error', 2500)
                    end
                end)

                if math.random(1, 100) <= 85 and not QBCore.Functions.IsWearingGloves() then
                    local pos = GetEntityCoords(PlayerPedId())
                    TriggerServerEvent('evidence:server:CreateFingerDrop', pos)
                end
            else
                QBCore.Functions.Notify(Lang:t('error.door_open'), 'error', 3500)
            end
        else
            QBCore.Functions.Notify(Lang:t('error.not_enough_police'), 'error', 3500)
        end
    end
end)

-- Util Command (can be commented out - used for setting new spots in the config)
RegisterCommand('gethroffset', function()
    local coords = GetEntityCoords(PlayerPedId())
    local houseCoords = vector3(
        houses[currentHouse]['coords']['x'],
        houses[currentHouse]['coords']['y'],
        houses[currentHouse]['coords']['z'] - Config.MinZOffset
    )
    if inside then
        local xdist = coords.x - houseCoords.x
        local ydist = coords.y - houseCoords.y
        local zdist = coords.z - houseCoords.z
        print('X: ' .. xdist)
        print('Y: ' .. ydist)
        print('Z: ' .. zdist)
    end
end, false)
