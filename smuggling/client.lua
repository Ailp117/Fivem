-- GTA Online Style Warehouse Smuggling System - Client
local QBCore = exports['qb-core']:GetCoreObject()

WarehouseSmuggling = {
    isInWarehouse = false,
    currentWarehouse = nil,
    isSourcing = false,
    isSelling = false,
    sourceMissionData = nil,
    sellMissionData = nil,
    cargoVehicle = nil,
    currentCrates = 0,
    isIronUnion = false
}

Config.FactionCheck = {
    enabled = true,
    factionName = "the iron union",
    checkType = "gang"
}

Config = {
    Warehouses = {
        [1] = { name = "Rancho Warehouse", coords = vector3(826.7, -3199.5, 5.9), price = 250000, capacity = 42 },
        [2] = { name = "La Mesa Warehouse", coords = vector3(919.4, -1517.0, 30.4), price = 400000, capacity = 42 },
        [3] = { name = "Cypress Flats Warehouse", coords = vector3(804.4, -2224.5, 29.5), price = 350000, capacity = 42 },
        [4] = { name = "LSIA Warehouse", coords = vector3(-1133.2, -3454.8, 13.9), price = 450000, capacity = 42 },
        [5] = { name = "Elysian Island Warehouse", coords = vector3(251.3, -3078.6, 5.8), price = 375000, capacity = 42 },
        [6] = { name = "Davis Quartz Warehouse", coords = vector3(2692.0, 3453.8, 55.7), price = 200000, capacity = 42 },
        [7] = { name = "Paleto Bay Warehouse", coords = vector3(-108.3, 6167.2, 31.2), price = 175000, capacity = 42 },
        [8] = { name = "Sandy Shores Warehouse", coords = vector3(1624.3, 3568.2, 35.2), price = 225000, capacity = 42 }
    },
    
    CargoTypes = {
        ["specialcargo"] = { label = "Spezialfracht", basePrice = 10000, maxPrice = 20000, riskLevel = 3, policeChance = 0.02 },
        ["electronics"] = { label = "Elektronik", basePrice = 8000, maxPrice = 16000, riskLevel = 2, policeChance = 0.01 },
        ["medical"] = { label = "Medizinische Ware", basePrice = 12000, maxPrice = 24000, riskLevel = 1, policeChance = 0.005 },
        ["tobacco"] = { label = "Tabak & Alkohol", basePrice = 6000, maxPrice = 12000, riskLevel = 1, policeChance = 0.005 },
        ["counterfeit"] = { label = "Fälschungen", basePrice = 7000, maxPrice = 14000, riskLevel = 3, policeChance = 0.02 },
        ["gems"] = { label = "Edelsteine", basePrice = 15000, maxPrice = 30000, riskLevel = 2, policeChance = 0.01 },
        ["weapons"] = { label = "Waffen & Munition", basePrice = 20000, maxPrice = 40000, riskLevel = 4, policeChance = 0.05 },
        ["drugs"] = { label = "Drogen", basePrice = 18000, maxPrice = 35000, riskLevel = 4, policeChance = 0.05 }
    },
    
    SourceLocations = {
        -- Ausschließlich Land Missionen
        vector4(294.5, -3260.8, 5.8, 0.0),
        vector4(-320.5, -2695.2, 6.0, 0.0),
        vector4(1234.6, -2959.8, 9.3, 0.0),
        vector4(274.8, 301.7, 105.5, 0.0),
        vector4(-1042.3, -2023.1, 13.2, 0.0),
        vector4(1165.2, -1339.6, 34.9, 0.0),
        vector4(-534.2, -1715.6, 19.3, 0.0),
        vector4(896.1, -895.4, 26.1, 0.0),
        vector4(-1048.4, -2673.8, 13.8, 0.0),
        vector4(266.5, -1262.2, 29.3, 0.0),
        vector4(-428.0, -1728.3, 19.8, 0.0),
        vector4(1204.8, -3118.1, 5.5, 0.0),
        vector4(-1161.5, -2166.9, 13.2, 0.0),
        vector4(814.3, -2224.5, 29.5, 0.0),
        vector4(152.4, -3211.5, 5.8, 0.0)
    },
    
    SellLocations = {
        vector3(-1392.3, 21.4, 53.5),
        vector3(-631.9, -229.1, 38.1),
        vector3(818.9, -2159.2, 29.6),
        vector3(-1486.8, -909.0, 10.0),
        vector3(365.6, 340.5, 104.4),
        vector3(-596.4, -1601.2, 26.7)
    },
    
    SourceVehicles = {
        -- Ausschließlich Landfahrzeuge
        land = { "benson", "pounder", "mule", "biff", "pounder2", "phantom", "hauler", "barracks", "riot" }
    },
    
    EnemyModels = { "g_m_y_mexgoon_03", "g_m_m_chigoon_02", "g_m_y_salvagoon_03", "g_m_y_azteca_01" },
    EnemyVehicles = { "buccaneer", "ruiner", "dominator", "gauntlet", "vigero", "gresley" }
}

-- Check if player is Iron Union member
function IsIronUnionMember()
    local Player = QBCore.Functions.GetPlayerData()
    if not Player then return false end
    
    if Config.FactionCheck.checkType == "gang" then
        return Player.gang and Player.gang.name == Config.FactionCheck.factionName
    elseif Config.FactionCheck.checkType == "job" then
        return Player.job and Player.job.name == Config.FactionCheck.factionName
    end
    
    return false
end

-- Warehouse Management Thread
Citizen.CreateThread(function()
    -- Warte bis PlayerData geladen ist
    while LocalPlayer.state.isLoggedIn ~= true do
        Citizen.Wait(1000)
    end
    
    -- Prüfe Fraktionsmitgliedschaft
    WarehouseSmuggling.isIronUnion = IsIronUnionMember()
    
    if not WarehouseSmuggling.isIronUnion then
        return -- Beende Thread wenn kein Iron Union Mitglied
    end
    
    for warehouseId, warehouse in pairs(Config.Warehouses) do
        -- Blip erstellen
        warehouse.blip = AddBlipForCoord(warehouse.coords.x, warehouse.coords.y, warehouse.coords.z)
        SetBlipSprite(warehouse.blip, 473)
        SetBlipDisplay(warehouse.blip, 4)
        SetBlipScale(warehouse.blip, 0.8)
        SetBlipColour(warehouse.blip, 2)
        SetBlipAsShortRange(warehouse.blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(warehouse.name)
        EndTextCommandSetBlipName(warehouse.blip)
    end
    
    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        for warehouseId, warehouse in pairs(Config.Warehouses) do
            local dist = #(playerCoords - warehouse.coords)
            
            if dist < 50.0 then
                sleep = 0
                
                -- Marker zeichnen
                DrawMarker(1, warehouse.coords.x, warehouse.coords.y, warehouse.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 1.0, 0, 255, 0, 100, false, false, 2, false, nil, nil, false)
                
                if dist < 2.0 then
                    if not WarehouseSmuggling.currentWarehouse then
                        DrawText3D(warehouse.coords.x, warehouse.coords.y, warehouse.coords.z + 1.0, "[E] Lagerhaus kaufen - $" .. formatNumber(warehouse.price))
                        if IsControlJustReleased(0, 38) then
                            OpenWarehousePurchase(warehouseId)
                        end
                    else
                        DrawText3D(warehouse.coords.x, warehouse.coords.y, warehouse.coords.z + 1.0, "[E] Lagerhaus betreten | [G] Verkaufen")
                        if IsControlJustReleased(0, 38) then
                            EnterWarehouse(warehouseId)
                        elseif IsControlJustReleased(0, 113) then -- G Taste
                            if WarehouseSmuggling.currentWarehouse == warehouseId then
                                OpenWarehouseSaleMenu()
                            end
                        end
                    end
                end
            end
        end
        
        Citizen.Wait(sleep)
    end
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
    QBCore.Functions.Notify('Lagerhaus erfolgreich gekauft!', 'success')
end)

function EnterWarehouse(warehouseId)
    WarehouseSmuggling.isInWarehouse = true
    
    -- Teleport in das Lagerhaus Interior
    DoScreenFadeOut(500)
    Citizen.Wait(500)
    SetEntityCoords(PlayerPedId(), 992.2, -3097.9, -39.0)
    SetEntityHeading(PlayerPedId(), 275.0)
    DoScreenFadeIn(500)
    
    -- Lagerhaus Interior UI öffnen
    OpenWarehouseInterior(warehouseId)
end

function OpenWarehouseInterior(warehouseId)
    TriggerServerEvent('warehouse:server:getInventory', warehouseId)
end

RegisterNetEvent('warehouse:client:openMenu')
AddEventHandler('warehouse:client:openMenu', function(inventory, stats)
    local options = {}
    local totalCrates = 0
    
    -- Lagerbestand anzeigen
    for cargoType, amount in pairs(inventory) do
        totalCrates = totalCrates + amount
        if amount > 0 then
            local cargoData = Config.CargoTypes[cargoType]
            local value = math.floor(cargoData.basePrice + ((cargoData.maxPrice - cargoData.basePrice) * (amount / 42)))
            
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
        title = 'Beschaffungsmission starten ($' .. formatNumber(2000 + (stats.missionsCompleted or 0) * 500) .. ')',
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
    
    -- Lagerhaus verlassen
    table.insert(options, {
        title = 'Lagerhaus verlassen',
        description = 'Zurück nach draußen',
        icon = 'door-open',
        onSelect = function()
            ExitWarehouse()
        end
    })
    
    lib.registerContext({
        id = 'warehouse_menu',
        title = 'Lagerhaus Management',
        options = options
    })
    
    lib.showContext('warehouse_menu')
end)

function CalculateSellValue(inventory)
    local totalValue = 0
    for cargoType, amount in pairs(inventory) do
        if amount > 0 then
            local cargoData = Config.CargoTypes[cargoType]
            local valuePerCrate = math.floor(cargoData.basePrice + ((cargoData.maxPrice - cargoData.basePrice) * (amount / 42)))
            totalValue = totalValue + (valuePerCrate * amount)
        end
    end
    return totalValue
end

function ExitWarehouse()
    DoScreenFadeOut(500)
    Citizen.Wait(500)
    
    local warehouse = Config.Warehouses[WarehouseSmuggling.currentWarehouse]
    SetEntityCoords(PlayerPedId(), warehouse.coords.x, warehouse.coords.y, warehouse.coords.z)
    
    DoScreenFadeIn(500)
    WarehouseSmuggling.isInWarehouse = false
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
    if WarehouseSmuggling.isSourcing then
        QBCore.Functions.Notify('Du hast bereits eine aktive Mission!', 'error')
        return
    end
    
    -- Ausschließlich Land-Transport
    local missionType = "land"
    local location = Config.SourceLocations[math.random(1, #Config.SourceLocations)]
    local vehicleModel = Config.SourceVehicles[missionType][math.random(1, #Config.SourceVehicles[missionType])]
    local cargoData = Config.CargoTypes[cargoType]
    
    WarehouseSmuggling.sourceMissionData = {
        cargoType = cargoType,
        missionType = missionType,
        location = location,
        vehicleModel = vehicleModel,
        cratesCollected = 0,
        totalCrates = math.random(1, 3), -- 1-3 Kisten pro Mission
        riskLevel = cargoData.riskLevel,
        policeChance = cargoData.policeChance
    }
    
    -- Bei hohem Risiko Warnung anzeigen
    if cargoData.riskLevel >= 3 then
        QBCore.Functions.Notify('WARNUNG: Hochriskante Ware! Polizei könnte alarmiert werden!', 'error', 5000)
    end
    
    WarehouseSmuggling.isSourcing = true
    
    -- Blip erstellen
    WarehouseSmuggling.missionBlip = AddBlipForCoord(location.x, location.y, location.z)
    SetBlipSprite(WarehouseSmuggling.missionBlip, 478)
    SetBlipColour(WarehouseSmuggling.missionBlip, 5)
    SetBlipRoute(WarehouseSmuggling.missionBlip, true)
    SetBlipRouteColour(WarehouseSmuggling.missionBlip, 5)
    
    QBCore.Functions.Notify('Beschaffungsmission gestartet! Hole die Ware und bringe sie zurück.', 'info')
    
    -- Mission Monitor
    CreateSourceMissionThread()
end

function CreateSourceMissionThread()
    Citizen.CreateThread(function()
        while WarehouseSmuggling.isSourcing do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local mission = WarehouseSmuggling.sourceMissionData
            local targetCoords = vector3(mission.location.x, mission.location.y, mission.location.z)
            local dist = #(playerCoords - targetCoords)
            
            if dist < 100.0 and not WarehouseSmuggling.cargoVehicle then
                -- Fahrzeug spawnen
                SpawnCargoVehicle(mission)
            end
            
            if dist < 15.0 and WarehouseSmuggling.cargoVehicle then
                DrawText3D(targetCoords.x, targetCoords.y, targetCoords.z + 1.0, "[E] Waren aufladen (" .. mission.cratesCollected .. "/" .. mission.totalCrates .. ")")
                if IsControlJustReleased(0, 38) then
                    CollectCrate()
                end
            end
            
            Citizen.Wait(0)
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
    
    -- Gegner spawnen
    SpawnEnemies(mission.location)
end

function SpawnEnemies(coords)
    local numEnemies = math.random(3, 5)
    
    for i = 1, numEnemies do
        local model = GetHashKey(Config.EnemyModels[math.random(1, #Config.EnemyModels)])
        RequestModel(model)
        while not HasModelLoaded(model) do
            Citizen.Wait(0)
        end
        
        local enemyPed = CreatePed(26, model, coords.x + math.random(-15, 15), coords.y + math.random(-15, 15), coords.z, math.random(0, 360), true, true)
        GiveWeaponToPed(enemyPed, GetHashKey("weapon_pistol"), 250, false, true)
        TaskCombatPed(enemyPed, PlayerPedId(), 0, 16)
        SetPedAsEnemy(enemyPed, true)
        SetPedAccuracy(enemyPed, math.random(20, 50))
    end
    
    -- Gegner-Fahrzeug mit Verstärkung
    if math.random() > 0.5 then
        local vehicleModel = GetHashKey(Config.EnemyVehicles[math.random(1, #Config.EnemyVehicles)])
        RequestModel(vehicleModel)
        while not HasModelLoaded(vehicleModel) do
            Citizen.Wait(0)
        end
        
        local enemyVehicle = CreateVehicle(vehicleModel, coords.x + 20, coords.y, coords.z, coords.w, true, false)
        SetVehicleOnGroundProperly(enemyVehicle)
        
        for i = -1, 1 do
            local enemyPed = CreatePedInsideVehicle(enemyVehicle, 26, GetHashKey(Config.EnemyModels[math.random(1, #Config.EnemyModels)]), i, true, true)
            GiveWeaponToPed(enemyPed, GetHashKey("weapon_smg"), 250, false, true)
            TaskVehicleDriveToCoordLongrange(enemyPed, enemyVehicle, GetEntityCoords(PlayerPedId()).x, GetEntityCoords(PlayerPedId()).y, GetEntityCoords(PlayerPedId()).z, 20.0, 447, 10.0)
        end
    end
end

function CollectCrate()
    local mission = WarehouseSmuggling.sourceMissionData
    local playerPed = PlayerPedId()
    
    -- Animation
    TaskStartScenarioInPlace(playerPed, "PROP_HUMAN_BUM_BIN", 0, true)
    
    if lib.progressBar({
        duration = 10000,
        label = 'Lade Ware...',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true }
    }) then
        ClearPedTasks(playerPed)
        mission.cratesCollected = mission.cratesCollected + 1
        QBCore.Functions.Notify('Ware geladen! (' .. mission.cratesCollected .. '/' .. mission.totalCrates .. ')', 'success')
        
        -- Chance auf zusätzliche Gegner
        if math.random() < 0.4 then
            QBCore.Functions.Notify('Verstärkung ist eingetroffen!', 'error')
            SpawnEnemies(GetEntityCoords(PlayerPedId()))
        end
        
        -- Bei hohem Risiko (Risikowert >= 3) Polizei benachrichtigen
        if mission.riskLevel >= 3 then
            if math.random() < mission.policeChance then
                TriggerServerEvent('warehouse:server:alertPolice', GetEntityCoords(playerPed), 'Verdächtige Aktivität bei Ladung von ' .. Config.CargoTypes[mission.cargoType].label .. ' festgestellt!')
                QBCore.Functions.Notify('POLIZEI WURDE ALARMIERT!', 'error', 8000)
            end
        end
        
        if mission.cratesCollected >= mission.totalCrates then
            CompleteSourceMission()
        end
    else
        ClearPedTasks(playerPed)
    end
end

function CompleteSourceMission()
    RemoveBlip(WarehouseSmuggling.missionBlip)
    QBCore.Functions.Notify('Alle Waren geladen! Bringe sie zum Lagerhaus!', 'success')
    
    -- Lagerhaus Blip erstellen
    local warehouse = Config.Warehouses[WarehouseSmuggling.currentWarehouse]
    WarehouseSmuggling.returnBlip = AddBlipForCoord(warehouse.coords.x, warehouse.coords.y, warehouse.coords.z)
    SetBlipSprite(WarehouseSmuggling.returnBlip, 501)
    SetBlipColour(WarehouseSmuggling.returnBlip, 2)
    SetBlipRoute(WarehouseSmuggling.returnBlip, true)
    
    -- Return Monitor
    CreateReturnThread()
end

function CreateReturnThread()
    Citizen.CreateThread(function()
        while WarehouseSmuggling.isSourcing do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local warehouse = Config.Warehouses[WarehouseSmuggling.currentWarehouse]
            local dist = #(playerCoords - warehouse.coords)
            
            if dist < 10.0 then
                DrawText3D(warehouse.coords.x, warehouse.coords.y, warehouse.coords.z + 1.0, "[E] Ware einlagern")
                if IsControlJustReleased(0, 38) then
                    StoreCargo()
                end
            end
            
            Citizen.Wait(0)
        end
    end)
end

function StoreCargo()
    local mission = WarehouseSmuggling.sourceMissionData
    
    if lib.progressBar({
        duration = 5000,
        label = 'Lagere Ware ein...',
        useWhileDead = false,
        canCancel = true
    }) then
        -- Fahrzeug löschen
        if DoesEntityExist(WarehouseSmuggling.cargoVehicle) then
            DeleteEntity(WarehouseSmuggling.cargoVehicle)
        end
        
        RemoveBlip(WarehouseSmuggling.returnBlip)
        
        TriggerServerEvent('warehouse:server:storeCargo', WarehouseSmuggling.currentWarehouse, mission.cargoType, mission.cratesCollected)
        
        WarehouseSmuggling.isSourcing = false
        WarehouseSmuggling.sourceMissionData = nil
        WarehouseSmuggling.cargoVehicle = nil
        
        QBCore.Functions.Notify('Ware erfolgreich eingelagert!', 'success')
    end
end

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
    if WarehouseSmuggling.isSelling then
        QBCore.Functions.Notify('Du hast bereits eine Verkaufsmission aktiv!', 'error')
        return
    end
    
    local sellLocation = Config.SellLocations[math.random(1, #Config.SellLocations)]
    
    WarehouseSmuggling.isSelling = true
    
    -- Verkaufs-Blip
    WarehouseSmuggling.sellBlip = AddBlipForCoord(sellLocation.x, sellLocation.y, sellLocation.z)
    SetBlipSprite(WarehouseSmuggling.sellBlip, 500)
    SetBlipColour(WarehouseSmuggling.sellBlip, 1)
    SetBlipRoute(WarehouseSmuggling.sellBlip, true)
    
    QBCore.Functions.Notify('Verkaufsmission gestartet! Fahre zum Käufer.', 'info')
    
    -- Verkaufs Monitor
    CreateSellMissionThread()
end

function CreateSellMissionThread()
    Citizen.CreateThread(function()
        local missionStartTime = GetGameTimer()
        local inventory = {} -- Hier müssten wir das aktuelle Inventar haben
        local hasHighRiskCargo = false
        local maxPoliceChance = 0
        
        -- Prüfen ob hochriskante Ware dabei ist
        TriggerServerEvent('warehouse:server:checkRiskLevel', WarehouseSmuggling.currentWarehouse)
        
        while WarehouseSmuggling.isSelling do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            
            -- Bei hohem Risiko kontinuierliche Polizei-Checks
            if WarehouseSmuggling.hasHighRiskCargo then
                if math.random() < (WarehouseSmuggling.policeChance or 0.001) then
                    TriggerServerEvent('warehouse:server:alertPolice', playerCoords, 'Verdächtiger Frachttransport unterwegs!')
                    QBCore.Functions.Notify('POLIZEI VERFOLGT DICH!', 'error', 5000)
                end
            else
                -- Normale Checks
                if GetGameTimer() - missionStartTime > 30000 then
                    if math.random() < 0.0005 then
                        TriggerServerEvent('warehouse:server:alertPolice', playerCoords, 'Verdächtige Lagerhaus-Aktivität')
                    end
                end
            end
            
            -- Verkaufs-Orte dynamisch finden
            for _, location in ipairs(Config.SellLocations) do
                local locationDist = #(playerCoords - location)
                if locationDist < 10.0 then
                    DrawText3D(location.x, location.y, location.z + 1.0, "[E] Waren verkaufen")
                    if IsControlJustReleased(0, 38) then
                        CompleteSellMission(location)
                    end
                end
            end
            
            Citizen.Wait(0)
        end
    end)
end

function CompleteSellMission(location)
    if lib.progressBar({
        duration = 10000,
        label = 'Verkaufe Waren...',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = { dict = 'mp_common', clip = 'givetake1_a' }
    }) then
        RemoveBlip(WarehouseSmuggling.sellBlip)
        
        TriggerServerEvent('warehouse:server:completeSell', WarehouseSmuggling.currentWarehouse)
        
        WarehouseSmuggling.isSelling = false
        WarehouseSmuggling.sellMissionData = nil
        
        QBCore.Functions.Notify('Verkauf abgeschlossen!', 'success')
    end
end

-- Helper Functions
function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    local px, py, pz = table.unpack(GetGameplayCamCoords())
    
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(1)
    AddTextComponentString(text)
    DrawText(_x, _y)
    local factor = (string.len(text)) / 370
    DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 41, 11, 41, 68)
end

function formatNumber(number)
    local formatted = tostring(number)
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

RegisterNetEvent('warehouse:client:hasWarehouse')
AddEventHandler('warehouse:client:hasWarehouse', function(warehouseId)
    WarehouseSmuggling.currentWarehouse = warehouseId
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
        QBCore.Functions.Notify('WARNUNG: ' .. riskText .. 'ES RISIKO! Polizei-Aufmerksamkeit erhöht!', 'error', 8000)
    end
end)