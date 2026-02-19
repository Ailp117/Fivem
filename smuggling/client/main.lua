-- GTA Online Style Warehouse Smuggling System - Client
local ESX = exports['es_extended']:getSharedObject()

WarehouseSmuggling = {
    currentWarehouse = nil,
    isSourcing = false,
    isSelling = false,
    sourceMissionData = nil,
    pendingSourceMission = nil,
    pendingSourceAuth = false,
    pendingCollect = false,
    cargoVehicle = nil,
    sellDeliveryVehicle = nil,
    pendingSellLoad = nil,
    pendingSellComplete = false,
    pendingStore = false,
    isIronUnion = false
}

local warehouseTargetZones = {}
local sourceTargetZone = nil
local returnTargetZone = nil
local sellTargetZone = nil

local function IsPlayerLoaded()
    if ESX.IsPlayerLoaded then
        return ESX.IsPlayerLoaded()
    end

    local playerData = ESX.GetPlayerData()
    return playerData and playerData.identifier ~= nil
end

local function Notify(message, notifType, duration)
    if lib and lib.notify then
        local mappedType = notifType
        if notifType == "info" then
            mappedType = "inform"
        end

        lib.notify({
            description = message,
            type = mappedType or "inform",
            duration = duration or ((Config.Notify and Config.Notify.defaultDuration) or 5000)
        })
        return
    end

    ESX.ShowNotification(message)
end

local function GetPriceScaleCapacity()
    local warehouse = Config.Warehouses[WarehouseSmuggling.currentWarehouse]
    if warehouse and warehouse.capacity and warehouse.capacity > 0 then
        return warehouse.capacity
    end

    return (Config.Mission and Config.Mission.priceScaleCrates) or 42
end

local function formatNumber(number)
    local formatted = tostring(number)
    while true do
        local k
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

local function getDispatchChanceMultiplier(dispatchType)
    local throttleCfg = Config.DispatchThrottle or {}
    local defaultCfg = throttleCfg.default or {}
    local typeCfg = throttleCfg[dispatchType] or {}
    local multiplier = tonumber(typeCfg.chanceMultiplier)
        or tonumber(defaultCfg.chanceMultiplier)
        or 1.0

    if multiplier < 0.0 then
        return 0.0
    end

    return multiplier
end

-- Check if player is Iron Union member
function IsIronUnionMember()
    local Player = ESX.GetPlayerData()
    if not Player then return false end

    if Config.FactionCheck and Config.FactionCheck.enabled == false then
        return true
    end
    
    if Config.FactionCheck.checkType == "gang" then
        return Player.gang and Player.gang.name == Config.FactionCheck.factionName
    elseif Config.FactionCheck.checkType == "job" then
        return Player.job and Player.job.name == Config.FactionCheck.factionName
    end
    
    return false
end

local function RemoveZone(zoneId)
    if zoneId then
        exports.ox_target:removeZone(zoneId)
    end
end

local function DeleteVehicleSafe(vehicle)
    if vehicle and DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
    end
end

local function OpenWarehouseManagement(warehouseId)
    TriggerServerEvent('warehouse:server:getInventory', warehouseId)
end

local function RegisterWarehouseTargets()
    local warehouseBlip = Config.Blips and Config.Blips.warehouse or {}
    local targetCfg = Config.Target or {}
    local targetIcons = Config.TargetIcons or {}

    for warehouseId, warehouse in pairs(Config.Warehouses) do
        -- Blip erstellen
        warehouse.blip = AddBlipForCoord(warehouse.coords.x, warehouse.coords.y, warehouse.coords.z)
        SetBlipSprite(warehouse.blip, warehouseBlip.sprite or 473)
        SetBlipDisplay(warehouse.blip, warehouseBlip.display or 4)
        SetBlipScale(warehouse.blip, warehouseBlip.scale or 0.8)
        SetBlipColour(warehouse.blip, warehouseBlip.colour or 2)
        SetBlipAsShortRange(warehouse.blip, warehouseBlip.shortRange ~= false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(warehouse.name)
        EndTextCommandSetBlipName(warehouse.blip)

        warehouseTargetZones[warehouseId] = exports.ox_target:addSphereZone({
            coords = warehouse.coords,
            radius = targetCfg.warehouseRadius or 2.0,
            debug = targetCfg.debug or Config.Debug or false,
            options = {
                {
                    name = ('warehouse_buy_%s'):format(warehouseId),
                    icon = targetIcons.warehouseBuy or 'fa-solid fa-warehouse',
                    label = ('Lagerhaus kaufen ($%s)'):format(formatNumber(warehouse.price)),
                    canInteract = function()
                        WarehouseSmuggling.isIronUnion = IsIronUnionMember()
                        return WarehouseSmuggling.isIronUnion and not WarehouseSmuggling.currentWarehouse
                    end,
                    onSelect = function()
                        OpenWarehousePurchase(warehouseId)
                    end
                },
                {
                    name = ('warehouse_manage_%s'):format(warehouseId),
                    icon = targetIcons.warehouseManage or 'fa-solid fa-box-open',
                    label = 'Lagerhaus verwalten',
                    canInteract = function()
                        WarehouseSmuggling.isIronUnion = IsIronUnionMember()
                        return WarehouseSmuggling.isIronUnion and WarehouseSmuggling.currentWarehouse == warehouseId
                    end,
                    onSelect = function()
                        OpenWarehouseManagement(warehouseId)
                    end
                },
                {
                    name = ('warehouse_sell_%s'):format(warehouseId),
                    icon = targetIcons.warehouseSellStart or 'fa-solid fa-money-bill',
                    label = 'Verkaufsmission starten',
                    canInteract = function()
                        WarehouseSmuggling.isIronUnion = IsIronUnionMember()
                        return WarehouseSmuggling.isIronUnion and WarehouseSmuggling.currentWarehouse == warehouseId and not WarehouseSmuggling.isSelling
                    end,
                    onSelect = function()
                        OpenWarehouseSaleMenu()
                    end
                }
            }
        })
    end
end

-- Warehouse Management Thread
Citizen.CreateThread(function()
    -- Warte bis PlayerData geladen ist
    while not IsPlayerLoaded() do
        Citizen.Wait(1000)
    end

    WarehouseSmuggling.isIronUnion = IsIronUnionMember()
    RegisterWarehouseTargets()
    TriggerServerEvent('warehouse:server:syncWarehouseState')
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function()
    WarehouseSmuggling.isIronUnion = IsIronUnionMember()
    TriggerServerEvent('warehouse:server:syncWarehouseState')
end)

RegisterNetEvent('esx:setGang')
AddEventHandler('esx:setGang', function()
    WarehouseSmuggling.isIronUnion = IsIronUnionMember()
    TriggerServerEvent('warehouse:server:syncWarehouseState')
end)

function OpenWarehousePurchase(warehouseId)
    local warehouse = Config.Warehouses[warehouseId]
    
    local alert = lib.alertDialog({
        header = warehouse.name,
        content = 'Möchtest du dieses Lagerhaus kaufen?\n\nPreis: $' .. formatNumber(warehouse.price) .. '\nKapazität: ' .. warehouse.capacity .. ' Kisten\n\nLagerhäuser können Spezialfracht, Elektronik, Medizinische Ware und mehr lagern.',
        centered = true,
        cancel = true
    })
    
    if alert == 'confirm' then
        TriggerServerEvent('warehouse:server:purchase', warehouseId)
    end
end

RegisterNetEvent('warehouse:client:purchaseSuccess')
AddEventHandler('warehouse:client:purchaseSuccess', function(warehouseId)
    WarehouseSmuggling.currentWarehouse = warehouseId
    Notify('Lagerhaus erfolgreich gekauft!', 'success')
end)

function OpenWarehouseInterior(warehouseId)
    TriggerServerEvent('warehouse:server:getInventory', warehouseId)
end

function OpenWarehouseSaleMenu()
    OpenWarehouseInterior(WarehouseSmuggling.currentWarehouse)
end

RegisterNetEvent('warehouse:client:openMenu')
AddEventHandler('warehouse:client:openMenu', function(inventory, stats)
    local options = {}
    local totalCrates = 0
    local scaleCapacity = GetPriceScaleCapacity()
    
    -- Lagerbestand anzeigen
    for cargoType, amount in pairs(inventory) do
        totalCrates = totalCrates + amount
        if amount > 0 then
            local cargoData = Config.CargoTypes[cargoType]
            local value = math.floor(cargoData.basePrice + ((cargoData.maxPrice - cargoData.basePrice) * (amount / scaleCapacity)))
            
            table.insert(options, {
                title = cargoData.label .. ': ' .. amount .. ' Kisten',
                description = 'Wert pro Kiste: $' .. formatNumber(value),
                icon = 'box',
                disabled = true
            })
        end
    end
    
    if totalCrates == 0 then
        table.insert(options, {
            title = 'Lagerhaus ist leer',
            description = 'Starte eine Beschaffungsmission',
            icon = 'exclamation-triangle',
            disabled = true
        })
    end
    
    -- Source Mission
    table.insert(options, {
        title = 'Beschaffungsmission starten ($' .. formatNumber(((Config.Economy and Config.Economy.sourceMissionBaseCost) or 2000) + (stats.missionsCompleted or 0) * ((Config.Economy and Config.Economy.sourceMissionCostIncrease) or 500)) .. ')',
        description = 'Beschaffe Waren für dein Lagerhaus',
        icon = 'truck',
        onSelect = function()
            OpenSourceMissionMenu()
        end
    })
    
    -- Sell Option (nur wenn Ware vorhanden)
    if totalCrates > 0 then
        table.insert(options, {
            title = 'Waren verkaufen',
            description = 'Aktueller Wert: $' .. formatNumber(CalculateSellValue(inventory)),
            icon = 'money-bill',
            onSelect = function()
                OpenSellMissionMenu()
            end
        })
    end
    
    lib.registerContext({
        id = 'warehouse_menu',
        title = 'Lagerhaus Management',
        options = options
    })
    
    lib.showContext('warehouse_menu')
end)

function CalculateSellValue(inventory)
    local totalValue = 0
    local scaleCapacity = GetPriceScaleCapacity()
    for cargoType, amount in pairs(inventory) do
        if amount > 0 then
            local cargoData = Config.CargoTypes[cargoType]
            local valuePerCrate = math.floor(cargoData.basePrice + ((cargoData.maxPrice - cargoData.basePrice) * (amount / scaleCapacity)))
            totalValue = totalValue + (valuePerCrate * amount)
        end
    end
    return totalValue
end

function OpenSourceMissionMenu()
    local options = {}
    
    for cargoType, data in pairs(Config.CargoTypes) do
        table.insert(options, {
            title = data.label,
            description = 'Wert: $' .. formatNumber(data.basePrice) .. ' - $' .. formatNumber(data.maxPrice) .. ' pro Kiste',
            icon = 'box',
            onSelect = function()
                StartSourceMission(cargoType)
            end
        })
    end
    
    lib.registerContext({
        id = 'source_mission_menu',
        title = 'Warentyp wählen',
        menu = 'warehouse_menu',
        options = options
    })
    
    lib.showContext('source_mission_menu')
end

function StartSourceMission(cargoType)
    if WarehouseSmuggling.isSourcing or WarehouseSmuggling.pendingSourceAuth then
        Notify('Du hast bereits eine aktive Mission!', 'error')
        return
    end

    if not WarehouseSmuggling.currentWarehouse then
        Notify('Du besitzt kein Lagerhaus.', 'error')
        return
    end

    local cargoData = Config.CargoTypes[cargoType]
    if not cargoData then
        Notify('Ungültiger Warentyp.', 'error')
        return
    end

    local sourceVehicles = Config.SourceVehicles and Config.SourceVehicles.land
    if not sourceVehicles or #sourceVehicles == 0 then
        Notify('Keine Quellfahrzeuge in der Config definiert.', 'error')
        return
    end

    WarehouseSmuggling.pendingSourceMission = {
        cargoType = cargoType,
        location = Config.SourceLocations[math.random(1, #Config.SourceLocations)],
        vehicleModel = sourceVehicles[math.random(1, #sourceVehicles)],
        riskLevel = cargoData.riskLevel,
        policeChance = cargoData.policeChance
    }
    WarehouseSmuggling.pendingSourceAuth = true

    Notify('Beschaffungsmission wird vorbereitet...', 'info')
    TriggerServerEvent('warehouse:server:startSourceMission', WarehouseSmuggling.currentWarehouse, cargoType)
end

local function ActivateSourceMission(missionData)
    local sourceCfg = (Config.Mission and Config.Mission.source) or {}
    local cargoData = Config.CargoTypes[missionData.cargoType]

    WarehouseSmuggling.sourceMissionData = missionData
    WarehouseSmuggling.isSourcing = true

    if cargoData and cargoData.riskLevel >= (sourceCfg.highRiskWarningLevel or 3) then
        Notify('WARNUNG: Hochriskante Ware! Polizei könnte alarmiert werden!', 'error', sourceCfg.highRiskWarningDuration or 5000)
    end

    RemoveZone(sourceTargetZone)
    sourceTargetZone = nil
    RemoveZone(returnTargetZone)
    returnTargetZone = nil

    local location = missionData.location
    local sourceBlip = Config.Blips and Config.Blips.source or {}
    WarehouseSmuggling.missionBlip = AddBlipForCoord(location.x, location.y, location.z)
    SetBlipSprite(WarehouseSmuggling.missionBlip, sourceBlip.sprite or 478)
    SetBlipColour(WarehouseSmuggling.missionBlip, sourceBlip.colour or 5)
    SetBlipRoute(WarehouseSmuggling.missionBlip, sourceBlip.route ~= false)
    SetBlipRouteColour(WarehouseSmuggling.missionBlip, sourceBlip.routeColour or (sourceBlip.colour or 5))

    Notify('Beschaffungsmission gestartet! Hole die Ware und bringe sie zurück.', 'info')

    sourceTargetZone = exports.ox_target:addSphereZone({
        coords = targetCoordsFromVec4(location),
        radius = (Config.Target and Config.Target.sourceCollectRadius) or 6.0,
        debug = (Config.Target and Config.Target.debug) or Config.Debug or false,
        options = {
            {
                name = 'warehouse_collect_cargo',
                icon = (Config.TargetIcons and Config.TargetIcons.sourceCollect) or 'fa-solid fa-box',
                label = 'Waren aufladen',
                canInteract = function()
                    local mission = WarehouseSmuggling.sourceMissionData
                    return WarehouseSmuggling.isSourcing
                        and WarehouseSmuggling.cargoVehicle
                        and mission
                        and mission.cratesCollected < mission.totalCrates
                end,
                onSelect = function()
                    CollectCrate()
                end
            }
        }
    })

    CreateSourceMissionThread()
end

RegisterNetEvent('warehouse:client:sourceMissionAuth')
AddEventHandler('warehouse:client:sourceMissionAuth', function(success, approvedCrates)
    local pending = WarehouseSmuggling.pendingSourceMission
    WarehouseSmuggling.pendingSourceAuth = false

    if not pending then
        return
    end

    if not success then
        WarehouseSmuggling.pendingSourceMission = nil
        return
    end

    local totalCrates = tonumber(approvedCrates) or 0
    if totalCrates <= 0 then
        WarehouseSmuggling.pendingSourceMission = nil
        Notify('Ungültige Missionsdaten vom Server.', 'error')
        return
    end

    WarehouseSmuggling.pendingSourceMission = nil
    ActivateSourceMission({
        cargoType = pending.cargoType,
        location = pending.location,
        vehicleModel = pending.vehicleModel,
        cratesCollected = 0,
        totalCrates = totalCrates,
        riskLevel = pending.riskLevel,
        policeChance = pending.policeChance
    })
end)

function targetCoordsFromVec4(coords)
    return vector3(coords.x, coords.y, coords.z)
end

function CreateSourceMissionThread()
    Citizen.CreateThread(function()
        local sourceCfg = (Config.Mission and Config.Mission.source) or {}
        while WarehouseSmuggling.isSourcing do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local mission = WarehouseSmuggling.sourceMissionData
            local targetCoords = vector3(mission.location.x, mission.location.y, mission.location.z)
            local dist = #(playerCoords - targetCoords)
            
            if dist < (sourceCfg.spawnDistance or 100.0) and not WarehouseSmuggling.cargoVehicle then
                -- Fahrzeug spawnen
                SpawnCargoVehicle(mission)
            end

            Citizen.Wait(sourceCfg.monitorTick or 500)
        end
    end)
end

function SpawnCargoVehicle(mission)
    if WarehouseSmuggling.cargoVehicle then return end
    
    local model = GetHashKey(mission.vehicleModel)
    RequestModel(model)
    while not HasModelLoaded(model) do
        Citizen.Wait(0)
    end
    
    WarehouseSmuggling.cargoVehicle = CreateVehicle(model, mission.location.x, mission.location.y, mission.location.z, mission.location.w, true, false)
    SetVehicleOnGroundProperly(WarehouseSmuggling.cargoVehicle)
    SetEntityAsMissionEntity(WarehouseSmuggling.cargoVehicle, true, true)
    SetVehicleEngineOn(WarehouseSmuggling.cargoVehicle, false, true, false)
end

function CollectCrate()
    local mission = WarehouseSmuggling.sourceMissionData
    if not mission then
        return
    end

    if WarehouseSmuggling.pendingCollect then
        Notify('Warte auf Bestätigung der letzten Kiste...', 'info')
        return
    end

    local playerPed = PlayerPedId()
    
    -- Animation
    TaskStartScenarioInPlace(playerPed, "PROP_HUMAN_BUM_BIN", 0, true)
    
    if lib.progressBar({
        duration = (Config.Progress and Config.Progress.sourceCollect) or 10000,
        label = 'Lade Ware...',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true }
    }) then
        ClearPedTasks(playerPed)
        WarehouseSmuggling.pendingCollect = true
        TriggerServerEvent('warehouse:server:collectSourceCargo', WarehouseSmuggling.currentWarehouse, mission.cargoType)
    else
        ClearPedTasks(playerPed)
    end
end

RegisterNetEvent('warehouse:client:collectCargoResult')
AddEventHandler('warehouse:client:collectCargoResult', function(success, collected, total)
    WarehouseSmuggling.pendingCollect = false

    local mission = WarehouseSmuggling.sourceMissionData
    if not mission then
        return
    end

    if not success then
        return
    end

    mission.cratesCollected = tonumber(collected) or mission.cratesCollected
    mission.totalCrates = tonumber(total) or mission.totalCrates

    Notify('Ware geladen! (' .. mission.cratesCollected .. '/' .. mission.totalCrates .. ')', 'success')
    
    -- Bei hohem Risiko (Risikowert >= 3) Polizei benachrichtigen
    local sourceCfg = (Config.Mission and Config.Mission.source) or {}
    if mission.riskLevel >= (sourceCfg.highRiskWarningLevel or 3) then
        local chance = math.min(1.0, mission.policeChance * getDispatchChanceMultiplier('source'))
        if math.random() < chance then
            TriggerServerEvent('warehouse:server:alertPolice', GetEntityCoords(PlayerPedId()), 'Verdächtige Aktivität bei Ladung von ' .. Config.CargoTypes[mission.cargoType].label .. ' festgestellt!', 'source')
            Notify('POLIZEI WURDE ALARMIERT!', 'error', sourceCfg.policeAlertNotifyDuration or 8000)
        end
    end
    
    if mission.cratesCollected >= mission.totalCrates then
        CompleteSourceMission()
    end
end)

function CompleteSourceMission()
    RemoveBlip(WarehouseSmuggling.missionBlip)
    RemoveZone(sourceTargetZone)
    sourceTargetZone = nil
    Notify('Alle Waren geladen! Bringe sie zum Lagerhaus!', 'success')
    
    -- Lagerhaus Blip erstellen
    local warehouse = Config.Warehouses[WarehouseSmuggling.currentWarehouse]
    local returnBlip = Config.Blips and Config.Blips.returnToWarehouse or {}
    WarehouseSmuggling.returnBlip = AddBlipForCoord(warehouse.coords.x, warehouse.coords.y, warehouse.coords.z)
    SetBlipSprite(WarehouseSmuggling.returnBlip, returnBlip.sprite or 501)
    SetBlipColour(WarehouseSmuggling.returnBlip, returnBlip.colour or 2)
    SetBlipRoute(WarehouseSmuggling.returnBlip, returnBlip.route ~= false)

    RemoveZone(returnTargetZone)
    returnTargetZone = exports.ox_target:addSphereZone({
        coords = warehouse.coords,
        radius = (Config.Target and Config.Target.returnStoreRadius) or 4.0,
        debug = (Config.Target and Config.Target.debug) or Config.Debug or false,
        options = {
            {
                name = 'warehouse_store_cargo',
                icon = (Config.TargetIcons and Config.TargetIcons.returnStore) or 'fa-solid fa-warehouse',
                label = 'Ware einlagern',
                canInteract = function()
                    return WarehouseSmuggling.isSourcing and WarehouseSmuggling.sourceMissionData ~= nil
                end,
                onSelect = function()
                    StoreCargo()
                end
            }
        }
    })
end

function StoreCargo()
    local mission = WarehouseSmuggling.sourceMissionData
    if not mission then
        return
    end

    if WarehouseSmuggling.pendingStore then
        Notify('Einlagerung wird bereits verarbeitet...', 'info')
        return
    end
    
    if lib.progressBar({
        duration = (Config.Progress and Config.Progress.storeCargo) or 5000,
        label = 'Lagere Ware ein...',
        useWhileDead = false,
        canCancel = true
    }) then
        WarehouseSmuggling.pendingStore = true
        TriggerServerEvent('warehouse:server:storeCargo', WarehouseSmuggling.currentWarehouse, mission.cargoType, mission.cratesCollected)
    end
end

RegisterNetEvent('warehouse:client:storeCargoResult')
AddEventHandler('warehouse:client:storeCargoResult', function(success)
    WarehouseSmuggling.pendingStore = false
    if not success then
        return
    end

    DeleteVehicleSafe(WarehouseSmuggling.cargoVehicle)
    RemoveBlip(WarehouseSmuggling.returnBlip)
    RemoveZone(returnTargetZone)
    returnTargetZone = nil

    WarehouseSmuggling.isSourcing = false
    WarehouseSmuggling.sourceMissionData = nil
    WarehouseSmuggling.cargoVehicle = nil
end)

function OpenSellMissionMenu()
    lib.registerContext({
        id = 'sell_confirm_menu',
        title = 'Waren verkaufen?',
        options = {
            {
                title = 'Ja, verkaufen',
                description = 'Starte Verkaufsmission',
                icon = 'check',
                onSelect = function()
                    StartSellMission()
                end
            },
            {
                title = 'Nein, abbrechen',
                description = 'Zurück zum Menü',
                icon = 'times',
                onSelect = function()
                    lib.showContext('warehouse_menu')
                end
            }
        }
    })
    
    lib.showContext('sell_confirm_menu')
end

function StartSellMission()
    if WarehouseSmuggling.isSelling or WarehouseSmuggling.pendingSellLoad then
        Notify('Du hast bereits eine Verkaufsmission aktiv!', 'error')
        return
    end
    
    local sellLocation = Config.SellLocations[math.random(1, #Config.SellLocations)]
    local warehouse = Config.Warehouses[WarehouseSmuggling.currentWarehouse]
    if not warehouse then
        Notify('Kein gültiges Lagerhaus gefunden.', 'error')
        return
    end
    
    local deliveryCfg = Config.Delivery or {}
    local deliveryModelName = deliveryCfg.vehicleModel or 'mule'
    local deliveryModel = GetHashKey(deliveryModelName)
    if not IsModelInCdimage(deliveryModel) or not IsModelAVehicle(deliveryModel) then
        Notify('Ungültiges Lieferfahrzeug in der Config: ' .. deliveryModelName, 'error')
        return
    end

    RequestModel(deliveryModel)
    while not HasModelLoaded(deliveryModel) do
        Citizen.Wait(0)
    end
    
    DeleteVehicleSafe(WarehouseSmuggling.sellDeliveryVehicle)
    local spawnOffset = deliveryCfg.spawnOffset or vector3(4.0, 0.0, 0.0)
    WarehouseSmuggling.sellDeliveryVehicle = CreateVehicle(deliveryModel, warehouse.coords.x + spawnOffset.x, warehouse.coords.y + spawnOffset.y, warehouse.coords.z + spawnOffset.z, GetEntityHeading(PlayerPedId()), true, false)
    SetVehicleOnGroundProperly(WarehouseSmuggling.sellDeliveryVehicle)
    SetEntityAsMissionEntity(WarehouseSmuggling.sellDeliveryVehicle, true, true)
    SetVehicleEngineOn(WarehouseSmuggling.sellDeliveryVehicle, true, true, false)
    local platePrefix = deliveryCfg.platePrefix or "SMUG"
    local plateMin = deliveryCfg.plateMin or 100
    local plateMax = deliveryCfg.plateMax or 999
    SetVehicleNumberPlateText(WarehouseSmuggling.sellDeliveryVehicle, platePrefix .. tostring(math.random(plateMin, plateMax)))
    
    WarehouseSmuggling.pendingSellLoad = {
        location = sellLocation,
        vehiclePlate = GetVehicleNumberPlateText(WarehouseSmuggling.sellDeliveryVehicle)
    }

    Notify('Lade Ware in das Lieferfahrzeug...', 'info')
    TriggerServerEvent('warehouse:server:startSellLoad', WarehouseSmuggling.currentWarehouse, WarehouseSmuggling.pendingSellLoad.vehiclePlate)
end

local function ActivateSellMission(loadedCrates)
    local pending = WarehouseSmuggling.pendingSellLoad
    if not pending then
        return
    end

    WarehouseSmuggling.isSelling = true
    WarehouseSmuggling.pendingSellLoad = nil
    RemoveZone(sellTargetZone)
    sellTargetZone = nil

    local sellLocation = pending.location
    local deliveryCfg = Config.Delivery or {}

    -- Verkaufs-Blip
    local sellBlip = Config.Blips and Config.Blips.sell or {}
    WarehouseSmuggling.sellBlip = AddBlipForCoord(sellLocation.x, sellLocation.y, sellLocation.z)
    SetBlipSprite(WarehouseSmuggling.sellBlip, sellBlip.sprite or 500)
    SetBlipColour(WarehouseSmuggling.sellBlip, sellBlip.colour or 1)
    SetBlipRoute(WarehouseSmuggling.sellBlip, sellBlip.route ~= false)

    Notify(('Verkaufsmission gestartet! %s Kisten wurden geladen.'):format(loadedCrates or 0), 'info')

    sellTargetZone = exports.ox_target:addSphereZone({
        coords = sellLocation,
        radius = (Config.Target and Config.Target.sellRadius) or 4.0,
        debug = (Config.Target and Config.Target.debug) or Config.Debug or false,
        options = {
            {
                name = 'warehouse_sell_cargo',
                icon = (Config.TargetIcons and Config.TargetIcons.sellComplete) or 'fa-solid fa-handshake',
                label = 'Waren verkaufen',
                canInteract = function()
                    if not WarehouseSmuggling.isSelling or WarehouseSmuggling.pendingSellComplete then
                        return false
                    end

                    local ped = PlayerPedId()
                    local missionVehicle = WarehouseSmuggling.sellDeliveryVehicle
                    if not missionVehicle or not DoesEntityExist(missionVehicle) then
                        return false
                    end

                    local requireDriver = (deliveryCfg.requireDriver ~= false)
                    if not requireDriver then
                        return GetVehiclePedIsIn(ped, false) == missionVehicle
                    end

                    return GetVehiclePedIsIn(ped, false) == missionVehicle and GetPedInVehicleSeat(missionVehicle, -1) == ped
                end,
                onSelect = function()
                    CompleteSellMission()
                end
            }
        }
    })

    CreateSellMissionThread()
end

RegisterNetEvent('warehouse:client:sellLoadResult')
AddEventHandler('warehouse:client:sellLoadResult', function(success, loadedCrates)
    local pending = WarehouseSmuggling.pendingSellLoad
    if not pending then
        return
    end

    if not success then
        WarehouseSmuggling.pendingSellLoad = nil
        DeleteVehicleSafe(WarehouseSmuggling.sellDeliveryVehicle)
        WarehouseSmuggling.sellDeliveryVehicle = nil
        return
    end

    ActivateSellMission(loadedCrates)
end)

function CreateSellMissionThread()
    Citizen.CreateThread(function()
        local sellCfg = (Config.Mission and Config.Mission.sell) or {}
        local missionStartTime = GetGameTimer()
        
        -- Prüfen ob hochriskante Ware dabei ist
        TriggerServerEvent('warehouse:server:checkRiskLevel', WarehouseSmuggling.currentWarehouse)
        
        while WarehouseSmuggling.isSelling do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            
            -- Bei hohem Risiko kontinuierliche Polizei-Checks
            if WarehouseSmuggling.hasHighRiskCargo then
                local highRiskChance = (WarehouseSmuggling.policeChance or sellCfg.highRiskDefaultChance or 0.001) * getDispatchChanceMultiplier('sell')
                if math.random() < math.min(1.0, highRiskChance) then
                    TriggerServerEvent('warehouse:server:alertPolice', playerCoords, 'Verdächtiger Frachttransport unterwegs!', 'sell')
                    Notify('POLIZEI VERFOLGT DICH!', 'error', sellCfg.policeChaseNotifyDuration or 5000)
                end
            else
                -- Normale Checks
                if GetGameTimer() - missionStartTime > (sellCfg.lowRiskStartDelayMs or 30000) then
                    local lowRiskChance = (sellCfg.lowRiskPoliceChance or 0.0005) * getDispatchChanceMultiplier('sell')
                    if math.random() < math.min(1.0, lowRiskChance) then
                        TriggerServerEvent('warehouse:server:alertPolice', playerCoords, 'Verdächtige Lagerhaus-Aktivität', 'sell')
                    end
                end
            end

            Citizen.Wait(sellCfg.monitorTick or 1000)
        end
    end)
end

function CompleteSellMission()
    local missionVehicle = WarehouseSmuggling.sellDeliveryVehicle
    if not missionVehicle or not DoesEntityExist(missionVehicle) then
        Notify('Lieferfahrzeug nicht gefunden.', 'error')
        return
    end

    local ped = PlayerPedId()
    local requireDriver = not Config.Delivery or Config.Delivery.requireDriver ~= false
    if requireDriver and (GetVehiclePedIsIn(ped, false) ~= missionVehicle or GetPedInVehicleSeat(missionVehicle, -1) ~= ped) then
        Notify('Du musst mit dem Lieferfahrzeug ausliefern.', 'error')
        return
    end
    if not requireDriver and GetVehiclePedIsIn(ped, false) ~= missionVehicle then
        Notify('Du musst mit dem Lieferfahrzeug ausliefern.', 'error')
        return
    end

    if lib.progressBar({
        duration = (Config.Progress and Config.Progress.completeSell) or 10000,
        label = 'Verkaufe Waren...',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = { dict = 'mp_common', clip = 'givetake1_a' }
    }) then
        WarehouseSmuggling.pendingSellComplete = true
        TriggerServerEvent('warehouse:server:completeSell', WarehouseSmuggling.currentWarehouse)
        Notify('Verkaufsabschluss wird verarbeitet...', 'info')
    end
end

RegisterNetEvent('warehouse:client:completeSellResult')
AddEventHandler('warehouse:client:completeSellResult', function(success)
    WarehouseSmuggling.pendingSellComplete = false
    if not success then
        return
    end

    RemoveBlip(WarehouseSmuggling.sellBlip)
    RemoveZone(sellTargetZone)
    sellTargetZone = nil
    WarehouseSmuggling.isSelling = false
    WarehouseSmuggling.pendingSellLoad = nil
    DeleteVehicleSafe(WarehouseSmuggling.sellDeliveryVehicle)
    WarehouseSmuggling.sellDeliveryVehicle = nil
end)

RegisterNetEvent('warehouse:client:hasWarehouse')
AddEventHandler('warehouse:client:hasWarehouse', function(warehouseId)
    WarehouseSmuggling.currentWarehouse = warehouseId
end)

RegisterNetEvent('warehouse:client:clearWarehouse')
AddEventHandler('warehouse:client:clearWarehouse', function()
    WarehouseSmuggling.currentWarehouse = nil
end)

RegisterNetEvent('warehouse:client:notify')
AddEventHandler('warehouse:client:notify', function(message, notifType, duration)
    Notify(message, notifType, duration)
end)

RegisterNetEvent('warehouse:client:policeAlert')
AddEventHandler('warehouse:client:policeAlert', function(coords, message)
    local policeBlip = Config.Blips and Config.Blips.policeAlert or {}
    local alertBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(alertBlip, policeBlip.sprite or 161)
    SetBlipColour(alertBlip, policeBlip.colour or 1)
    SetBlipScale(alertBlip, policeBlip.scale or 1.2)
    SetBlipAsShortRange(alertBlip, policeBlip.shortRange or false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(policeBlip.name or "Polizei Alarm")
    EndTextCommandSetBlipName(alertBlip)

    Notify(message or 'Verdächtige Lagerhaus-Aktivität', 'error', (Config.Police and Config.Police.notifyDuration) or 10000)

    SetTimeout(policeBlip.duration or 60000, function()
        if DoesBlipExist(alertBlip) then
            RemoveBlip(alertBlip)
        end
    end)
end)

-- Risiko-Info vom Server erhalten
RegisterNetEvent('warehouse:client:riskLevelInfo')
AddEventHandler('warehouse:client:riskLevelInfo', function(hasHighRisk, maxRiskLevel, policeChance)
    WarehouseSmuggling.hasHighRiskCargo = hasHighRisk
    WarehouseSmuggling.maxRiskLevel = maxRiskLevel
    WarehouseSmuggling.policeChance = policeChance
    
    if hasHighRisk then
        local riskText = "MITTEL"
        if maxRiskLevel == 4 then
            riskText = "EXTREM HOCH"
        elseif maxRiskLevel == 3 then
            riskText = "HOCH"
        end
        Notify('WARNUNG: ' .. riskText .. 'ES RISIKO! Polizei-Aufmerksamkeit erhöht!', 'error', (Config.Police and Config.Police.notifyDuration) or 8000)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    if WarehouseSmuggling.isSourcing or WarehouseSmuggling.pendingSourceAuth then
        TriggerServerEvent('warehouse:server:cancelSourceMission')
    end

    if WarehouseSmuggling.isSelling or WarehouseSmuggling.pendingSellLoad then
        TriggerServerEvent('warehouse:server:cancelSellLoad')
    end

    for warehouseId, zoneId in pairs(warehouseTargetZones) do
        RemoveZone(zoneId)
        warehouseTargetZones[warehouseId] = nil
    end

    RemoveZone(sourceTargetZone)
    RemoveZone(returnTargetZone)
    RemoveZone(sellTargetZone)
    DeleteVehicleSafe(WarehouseSmuggling.cargoVehicle)
    DeleteVehicleSafe(WarehouseSmuggling.sellDeliveryVehicle)
    WarehouseSmuggling.cargoVehicle = nil
    WarehouseSmuggling.sellDeliveryVehicle = nil
    WarehouseSmuggling.pendingSourceMission = nil
    WarehouseSmuggling.pendingSourceAuth = false
    WarehouseSmuggling.pendingCollect = false
    WarehouseSmuggling.pendingSellLoad = nil
    WarehouseSmuggling.pendingSellComplete = false
end)
