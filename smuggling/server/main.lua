-- GTA Online Style Warehouse Smuggling System - Server
local ESX = exports['es_extended']:getSharedObject()

Warehouses = {}
WarehouseStats = {}
ActiveSellLoads = {}
SellLoadBySource = {}
ActiveSourceMissions = {}
DispatchStateBySource = {}

local function notifyPlayer(playerId, message, notifType, duration)
    TriggerClientEvent('warehouse:client:notify', playerId, message, notifType or 'inform', duration)
end

local function notifySource(source, message, notifType, duration)
    if source == 0 then
        print('[LAGERHAUS] ' .. message)
        return
    end

    notifyPlayer(source, message, notifType, duration)
end

local function getFactionDisplayName()
    if Config.FactionCheck and Config.FactionCheck.factionName and Config.FactionCheck.factionName ~= '' then
        return Config.FactionCheck.factionName
    end

    return 'der Fraktion'
end

local function notifyNotFaction(playerId)
    notifyPlayer(playerId, ('Du bist kein Mitglied von %s!'):format(getFactionDisplayName()), 'error')
end

local function distanceBetweenCoords(coordA, coordB)
    if not coordA or not coordB then
        return math.huge
    end

    local ax, ay, az = coordA.x or 0.0, coordA.y or 0.0, coordA.z or 0.0
    local bx, by, bz = coordB.x or 0.0, coordB.y or 0.0, coordB.z or 0.0
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function getDispatchThrottleRule(dispatchType)
    local throttleCfg = Config.DispatchThrottle or {}
    local defaultCfg = throttleCfg.default or {}
    local typeCfg = throttleCfg[dispatchType] or {}

    return {
        cooldownMs = tonumber(typeCfg.cooldownMs) or tonumber(defaultCfg.cooldownMs) or 0,
        minDistance = tonumber(typeCfg.minDistance) or tonumber(defaultCfg.minDistance) or 0.0
    }
end

local function shouldAllowDispatch(src, coords, dispatchType)
    local throttleCfg = Config.DispatchThrottle or {}
    if throttleCfg.enabled == false then
        return true
    end

    local rule = getDispatchThrottleRule(dispatchType)
    if rule.cooldownMs <= 0 and rule.minDistance <= 0.0 then
        return true
    end

    local now = GetGameTimer()
    local dispatchKey = dispatchType or 'default'
    local statesByType = DispatchStateBySource[src]
    if not statesByType then
        statesByType = {}
        DispatchStateBySource[src] = statesByType
    end

    local last = statesByType[dispatchKey]
    if not last then
        statesByType[dispatchKey] = { time = now, coords = coords or nil }
        return true
    end

    local elapsed = now - (last.time or 0)
    if rule.cooldownMs > 0 and elapsed < rule.cooldownMs then
        return false
    end

    if rule.minDistance > 0.0 and coords and last.coords then
        local distance = distanceBetweenCoords(coords, last.coords)
        if distance < rule.minDistance then
            return false
        end
    end

    statesByType[dispatchKey] = { time = now, coords = coords or nil }
    return true
end

local function getFactionOwnerKey()
    if not Config.FactionCheck or Config.FactionCheck.enabled == false then
        return 'global:warehouse'
    end

    local checkType = Config.FactionCheck.checkType or 'job'
    local factionName = (Config.FactionCheck.factionName or 'faction'):lower()
    return ('faction:%s:%s'):format(checkType, factionName)
end

local function getWarehouseOwnerKey(playerData)
    if Config.FactionCheck and Config.FactionCheck.enabled ~= false and not IsIronUnionMember(playerData) then
        return nil
    end

    return getFactionOwnerKey()
end

local function isFactionMemberByData(playerData)
    if Config.FactionCheck and Config.FactionCheck.enabled == false then
        return true
    end
    return IsIronUnionMember(playerData)
end

local function broadcastFactionWarehouse(warehouseId)
    for _, playerId in ipairs(ESX.GetPlayers()) do
        local targetId = tonumber(playerId)
        local targetPlayer = ESX.GetPlayerFromId(targetId)
        if targetPlayer and isFactionMemberByData(targetPlayer) then
            if warehouseId then
                TriggerClientEvent('warehouse:client:hasWarehouse', targetId, warehouseId)
            else
                TriggerClientEvent('warehouse:client:clearWarehouse', targetId)
            end
        end
    end
end

local function getCargoItemName(cargoType)
    local cargoData = Config.CargoTypes[cargoType]
    if not cargoData then
        return cargoType
    end

    return cargoData.item or cargoType
end

local function getInventoryItemCount(inventoryId, itemName)
    local okGet, getResult = pcall(function()
        return exports.ox_inventory:GetItem(inventoryId, itemName, nil, true)
    end)
    if okGet and type(getResult) == 'number' then
        return getResult
    end

    local okSearch, searchResult = pcall(function()
        return exports.ox_inventory:Search(inventoryId, 'count', itemName)
    end)
    if okSearch and type(searchResult) == 'number' then
        return searchResult
    end

    return 0
end

local RegisteredWarehouseStashes = {}

local function getWarehouseStashId(ownerKey)
    return ('warehouse_%s'):format(ownerKey:gsub('[^%w_%-]', '_'))
end

local function ensureWarehouseStash(ownerKey)
    local stashId = getWarehouseStashId(ownerKey)
    if RegisteredWarehouseStashes[stashId] then
        return stashId
    end

    local invCfg = Config.Inventory or {}
    local slots = invCfg.stashSlots or 250
    local maxWeight = invCfg.stashMaxWeight or 2000000
    local labelPrefix = invCfg.stashLabelPrefix or 'Fraktionslager'
    local label = ('%s (%s)'):format(labelPrefix, ownerKey)

    exports.ox_inventory:RegisterStash(stashId, label, slots, maxWeight, false, nil, nil)
    RegisteredWarehouseStashes[stashId] = true
    return stashId
end

local function clearWarehouseStash(ownerKey)
    local stashId = ensureWarehouseStash(ownerKey)
    local ok, stashItems = pcall(function()
        return exports.ox_inventory:GetInventoryItems(stashId)
    end)

    if not ok or type(stashItems) ~= 'table' then
        pcall(function()
            exports.ox_inventory:ClearInventory(stashId)
        end)
        return
    end

    for _, item in pairs(stashItems) do
        if item and item.name and item.count and item.count > 0 then
            pcall(function()
                exports.ox_inventory:RemoveItem(stashId, item.name, item.count, item.metadata, item.slot, true)
            end)
        end
    end
end

local function getCargoInventoryForOwner(ownerKey)
    local inventory = {}
    local totalCrates = 0
    local stashId = ensureWarehouseStash(ownerKey)

    for cargoType, cargoData in pairs(Config.CargoTypes) do
        local itemName = cargoData.item or cargoType
        local amount = getInventoryItemCount(stashId, itemName)
        inventory[cargoType] = amount
        totalCrates = totalCrates + amount
    end

    return inventory, totalCrates
end

local function addCargoToInventory(ownerKey, cargoType, amount)
    local itemName = getCargoItemName(cargoType)
    local stashId = ensureWarehouseStash(ownerKey)
    return exports.ox_inventory:AddItem(stashId, itemName, amount)
end

local function removeCargoFromInventory(ownerKey, cargoType, amount)
    local itemName = getCargoItemName(cargoType)
    local stashId = ensureWarehouseStash(ownerKey)
    return exports.ox_inventory:RemoveItem(stashId, itemName, amount)
end

local function normalizePlate(plate)
    if type(plate) ~= 'string' then
        return ''
    end

    local trimmed = plate:gsub('^%s*(.-)%s*$', '%1')
    return trimmed
end

local function getTrunkInventoryIds(plate)
    local normalized = normalizePlate(plate)
    if normalized == '' then
        return nil
    end

    local compact = normalized:gsub('%s+', '')
    local upper = compact:upper()
    local ids = {}
    local seen = {}

    local function pushPlate(plateValue)
        if not plateValue or plateValue == '' then
            return
        end

        local inventoryId = ('trunk%s'):format(plateValue)
        if not seen[inventoryId] then
            seen[inventoryId] = true
            ids[#ids + 1] = inventoryId
        end
    end

    pushPlate(normalized)
    pushPlate(compact)
    pushPlate(upper)

    return ids, normalized
end

local function addCargoToTrunk(plate, cargoType, amount, forcedTrunkId)
    local itemName = getCargoItemName(cargoType)
    local lastReason = 'invalid_inventory'

    if forcedTrunkId then
        local added, reason = exports.ox_inventory:AddItem(forcedTrunkId, itemName, amount)
        return added, reason, forcedTrunkId
    end

    local trunkIds = getTrunkInventoryIds(plate)
    if not trunkIds then
        return false, lastReason, nil
    end

    for _, trunkId in ipairs(trunkIds) do
        local added, reason = exports.ox_inventory:AddItem(trunkId, itemName, amount)
        if added then
            return true, nil, trunkId
        end

        lastReason = reason or lastReason
    end

    return false, lastReason, nil
end

local function removeCargoFromTrunk(plate, cargoType, amount, forcedTrunkId)
    local itemName = getCargoItemName(cargoType)
    local lastReason = 'invalid_inventory'

    if forcedTrunkId then
        local removed, reason = exports.ox_inventory:RemoveItem(forcedTrunkId, itemName, amount)
        return removed, reason, forcedTrunkId
    end

    local trunkIds = getTrunkInventoryIds(plate)
    if not trunkIds then
        return false, lastReason, nil
    end

    for _, trunkId in ipairs(trunkIds) do
        local removed, reason = exports.ox_inventory:RemoveItem(trunkId, itemName, amount)
        if removed then
            return true, nil, trunkId
        end

        lastReason = reason or lastReason
    end

    return false, lastReason, nil
end

local function getCargoInTrunk(plate, cargoType, forcedTrunkId)
    local itemName = getCargoItemName(cargoType)

    if forcedTrunkId then
        return getInventoryItemCount(forcedTrunkId, itemName), forcedTrunkId
    end

    local trunkIds = getTrunkInventoryIds(plate)
    if not trunkIds then
        return 0, nil
    end

    for _, trunkId in ipairs(trunkIds) do
        local amount = getInventoryItemCount(trunkId, itemName)
        if amount > 0 then
            return amount, trunkId
        end
    end

    return 0, trunkIds[1]
end

local function getSourceMissionMetadata(sourceMission)
    if not sourceMission or not sourceMission.token then
        return nil
    end

    return {
        smuggleMission = sourceMission.token
    }
end

local function tryLoadTrunkInventoryByIds(trunkIds, timeoutMs, intervalMs)
    if not trunkIds then
        return nil
    end

    local timeout = timeoutMs or 3000
    local interval = intervalMs or 100
    local elapsed = 0

    while elapsed <= timeout do
        for _, trunkId in ipairs(trunkIds) do
            local inv = exports.ox_inventory:GetInventory(trunkId)
            if inv then
                return trunkId
            end
        end

        Wait(interval)
        elapsed = elapsed + interval
    end

    return nil
end

local function buildNonEmptyCargoMap(inventory)
    local cargoMap = {}
    local totalCrates = 0

    for cargoType, amount in pairs(inventory or {}) do
        local count = tonumber(amount) or 0
        if count > 0 then
            cargoMap[cargoType] = count
            totalCrates = totalCrates + count
        end
    end

    return cargoMap, totalCrates
end

local function clearSellLoadForOwner(ownerKey)
    local active = ActiveSellLoads[ownerKey]
    if active and active.startedBy then
        SellLoadBySource[active.startedBy] = nil
    end
    ActiveSellLoads[ownerKey] = nil
end

local function returnSellLoadToWarehouse(ownerKey)
    local active = ActiveSellLoads[ownerKey]
    if not active or not active.cargo then
        return false
    end

    local vehiclePlate = active.vehiclePlate
    local trunkInventoryId = active.trunkInventoryId
    local trunkAvailable = false
    if vehiclePlate and vehiclePlate ~= '' then
        if trunkInventoryId then
            trunkAvailable = true
        else
            local trunkIds = getTrunkInventoryIds(vehiclePlate)
            trunkInventoryId = tryLoadTrunkInventoryByIds(trunkIds, 250, 50)
            trunkAvailable = trunkInventoryId ~= nil
        end
    end
    local hadFailure = false
    for cargoType, amount in pairs(active.cargo) do
        if trunkAvailable then
            local availableInTrunk, detectedTrunkId = getCargoInTrunk(vehiclePlate, cargoType, trunkInventoryId)
            trunkInventoryId = detectedTrunkId or trunkInventoryId
            local returnAmount = math.min(availableInTrunk, amount)
            if returnAmount > 0 then
                local removed = removeCargoFromTrunk(vehiclePlate, cargoType, returnAmount, trunkInventoryId)
                if removed then
                    local restored = addCargoToInventory(ownerKey, cargoType, returnAmount)
                    if not restored then
                        hadFailure = true
                    end
                else
                    if Config.Debug then
                        print(('[LAGERHAUS][DEBUG] Rücklagerung fehlgeschlagen (%s x%s)'):format(cargoType, tostring(returnAmount)))
                    end
                    hadFailure = true
                end
            end
        else
            -- Das Fahrzeug ist nicht mehr erreichbar; Ware direkt ins Lager zurücklegen.
            local restored = addCargoToInventory(ownerKey, cargoType, amount)
            if not restored and Config.Debug then
                print(('[LAGERHAUS][DEBUG] Fallback-Rücklagerung fehlgeschlagen (%s x%s)'):format(cargoType, tostring(amount)))
            end
            if not restored then
                hadFailure = true
            end
        end
    end

    if hadFailure then
        return false
    end

    clearSellLoadForOwner(ownerKey)
    return true
end

local function reserveWarehouseCargoForSell(ownerKey, startedBy, vehiclePlate)
    local trunkIds, normalizedPlate = getTrunkInventoryIds(vehiclePlate)
    if not trunkIds then
        return false, 'Ungültiges Lieferfahrzeug (Kennzeichen).', nil, 0
    end

    local deliveryCfg = Config.Delivery or {}
    local loadTimeout = deliveryCfg.trunkLoadTimeoutMs or 3000
    local preferredTrunkId = tryLoadTrunkInventoryByIds(trunkIds, loadTimeout, 100)

    local inventory = getCargoInventoryForOwner(ownerKey)
    local cargoMap, totalCrates = buildNonEmptyCargoMap(inventory)
    if totalCrates <= 0 then
        return false, 'Keine Ware zu verkaufen!', nil, 0
    end

    local loadedCargo = {}
    local usedTrunkId = preferredTrunkId
    for cargoType, amount in pairs(cargoMap) do
        local removed = removeCargoFromInventory(ownerKey, cargoType, amount)
        if not removed then
            for rollbackCargoType, rollbackAmount in pairs(loadedCargo) do
                addCargoToInventory(ownerKey, rollbackCargoType, rollbackAmount)
            end
            return false, 'Konnte Ware nicht in das Lieferfahrzeug laden.', nil, 0
        end

        local added, addReason, loadedTrunkId = addCargoToTrunk(normalizedPlate, cargoType, amount, usedTrunkId)
        if not added then
            addCargoToInventory(ownerKey, cargoType, amount)
            for rollbackCargoType, rollbackAmount in pairs(loadedCargo) do
                removeCargoFromTrunk(normalizedPlate, rollbackCargoType, rollbackAmount, usedTrunkId)
                addCargoToInventory(ownerKey, rollbackCargoType, rollbackAmount)
            end
            if Config.Debug then
                print(('[LAGERHAUS][DEBUG] Trunk AddItem fehlgeschlagen (%s): %s'):format(cargoType, tostring(addReason)))
            end
            return false, 'Kofferraum konnte nicht beladen werden (Kapazität/Trunk nicht verfügbar).', nil, 0
        end

        usedTrunkId = loadedTrunkId or usedTrunkId
        loadedCargo[cargoType] = amount
    end

    ActiveSellLoads[ownerKey] = {
        cargo = loadedCargo,
        totalCrates = totalCrates,
        startedBy = startedBy,
        trunkInventoryId = usedTrunkId,
        vehiclePlate = normalizedPlate,
        startedAt = os.time()
    }
    SellLoadBySource[startedBy] = ownerKey
    return true, nil, loadedCargo, totalCrates
end

local function clearSourceMissionForSource(src, removeItems)
    local sourceMission = ActiveSourceMissions[src]
    if not sourceMission then
        return
    end

    if removeItems and (sourceMission.collected or 0) > 0 then
        local itemName = getCargoItemName(sourceMission.cargoType)
        local metadata = getSourceMissionMetadata(sourceMission)
        pcall(function()
            exports.ox_inventory:RemoveItem(src, itemName, sourceMission.collected, metadata)
        end)
    end

    ActiveSourceMissions[src] = nil
end

local function getWarehousePriceScale(warehouseId)
    local warehouse = Config.Warehouses[warehouseId]
    if warehouse and warehouse.capacity and warehouse.capacity > 0 then
        return warehouse.capacity
    end

    return (Config.Mission and Config.Mission.priceScaleCrates) or 42
end

local function isAdmin(source)
    if source == 0 then
        return true
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return false
    end

    if xPlayer.getGroup then
        local group = xPlayer.getGroup()
        return group == 'admin' or group == 'superadmin'
    end

    return IsPlayerAceAllowed(source, 'command')
end

local function hasValidWarehouse(ownerKey, warehouseId)
    return ownerKey and Warehouses[ownerKey] and Warehouses[ownerKey].id == warehouseId
end

local function syncWarehouseStateForPlayer(src, playerData, waitMs)
    if waitMs and waitMs > 0 then
        Citizen.Wait(waitMs)
    end

    local ownerKey = getWarehouseOwnerKey(playerData)
    if not ownerKey then
        TriggerClientEvent('warehouse:client:clearWarehouse', src)
        return
    end

    if Warehouses[ownerKey] then
        TriggerClientEvent('warehouse:client:hasWarehouse', src, Warehouses[ownerKey].id)
    else
        TriggerClientEvent('warehouse:client:clearWarehouse', src)
    end
end

local function sendLegacyPoliceAlert(coords, alertMessage)
    local policeJobName = (Config.Police and Config.Police.jobName) or 'police'
    local policeNotifyDuration = (Config.Police and Config.Police.notifyDuration) or 10000

    for _, playerId in ipairs(ESX.GetPlayers()) do
        local policeId = tonumber(playerId)
        local Player = ESX.GetPlayerFromId(policeId)
        if Player and Player.job and Player.job.name == policeJobName then
            TriggerClientEvent('warehouse:client:policeAlert', policeId, coords, alertMessage)
            notifyPlayer(policeId, 'ALARM: ' .. alertMessage, 'error', policeNotifyDuration)
        end
    end
end

local function sendRoadPhoneDispatch(coords, alertMessage)
    local dispatchCfg = Config.Dispatch or {}
    local roadPhoneCfg = dispatchCfg.roadphone or {}
    local resourceName = roadPhoneCfg.resource or 'roadphone'

    if GetResourceState(resourceName) ~= 'started' then
        if Config.Debug then
            print(('[LAGERHAUS][DEBUG] RoadPhone resource nicht gestartet: %s'):format(resourceName))
        end
        return false
    end

    if Config.SendPoliceDispatch == false then
        return true
    end

    local dispatchJob = Config.SendPoliceJob or roadPhoneCfg.jobName or (Config.Police and Config.Police.jobName) or 'police'
    local dispatchTitle = Config.SendPoliceTitle or (roadPhoneCfg.title or 'LagerhausAlarm')
    local dispatchText = Config.SendPoliceText or alertMessage or 'Verdächtige Lagerhaus-Aktivität'
    local dispatchCoords = nil
    local dispatchImage = roadPhoneCfg.image or nil

    if coords then
        dispatchCoords = { x = coords.x, y = coords.y, z = coords.z }
    end

    if dispatchTitle:find('%s') then
        dispatchTitle = dispatchTitle:gsub('%s+', '-')
    end

    local anonOk, anonResult = pcall(function()
        return exports[resourceName]:sendDispatchAnonym(dispatchJob, dispatchTitle, dispatchText, dispatchCoords, dispatchImage)
    end)
    if anonOk and anonResult ~= false then
        return true
    end

    if Config.Debug then
        print(('[LAGERHAUS][DEBUG] RoadPhone sendDispatchAnonym fehlgeschlagen (ok=%s, result=%s)'):format(tostring(anonOk), tostring(anonResult)))
    end

    local fallbackOk, fallbackResult = pcall(function()
        return exports[resourceName]:sendDispatch(dispatchText, dispatchJob, dispatchCoords)
    end)
    if fallbackOk and fallbackResult ~= false then
        return true
    end

    if Config.Debug then
        print(('[LAGERHAUS][DEBUG] RoadPhone Fallback sendDispatch fehlgeschlagen (ok=%s, result=%s)'):format(tostring(fallbackOk), tostring(fallbackResult)))
    end

    return false
end

local function dispatchPoliceAlert(coords, alertMessage)
    local dispatchCfg = Config.Dispatch or {}
    local provider = dispatchCfg.provider or 'legacy'

    if provider == 'roadphone' then
        local sent = sendRoadPhoneDispatch(coords, alertMessage)
        if sent then
            return
        end

        if dispatchCfg.fallbackToLegacy ~= false then
            sendLegacyPoliceAlert(coords, alertMessage)
        end
        return
    end

    sendLegacyPoliceAlert(coords, alertMessage)
end

-- Datenbank initialisieren
CreateThread(function()
    if Config.Dispatch and Config.Dispatch.provider == 'roadphone' then
        local roadRes = (Config.Dispatch.roadphone and Config.Dispatch.roadphone.resource) or 'roadphone'
        if GetResourceState(roadRes) ~= 'started' then
            print(('[LAGERHAUS] WARNUNG: Dispatch provider ist RoadPhone, aber Resource nicht gestartet: %s'):format(roadRes))
        end
    end

    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS player_warehouses (
            citizenid VARCHAR(50) PRIMARY KEY,
            warehouse_id INT,
            purchase_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]], {})
    
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS warehouse_stats (
            citizenid VARCHAR(50) PRIMARY KEY,
            total_earned INT DEFAULT 0,
            total_missions INT DEFAULT 0,
            missions_completed INT DEFAULT 0
        )
    ]], {})

    -- Lagerhausdaten laden
    LoadAllWarehouses()
end)

function LoadAllWarehouses()
    MySQL.Async.fetchAll('SELECT * FROM player_warehouses', {}, function(result)
        for _, row in ipairs(result) do
            Warehouses[row.citizenid] = {
                id = row.warehouse_id,
                purchaseDate = row.purchase_date
            }
        end
    end)
    
    MySQL.Async.fetchAll('SELECT * FROM warehouse_stats', {}, function(result)
        for _, row in ipairs(result) do
            WarehouseStats[row.citizenid] = {
                totalEarned = row.total_earned,
                totalMissions = row.total_missions,
                missionsCompleted = row.missions_completed
            }
        end
    end)
end

-- Check if player is Iron Union member
function IsIronUnionMember(playerData)
    if not Config.FactionCheck.enabled then return true end
    
    if Config.FactionCheck.checkType == "gang" then
        return playerData.gang and playerData.gang.name == Config.FactionCheck.factionName
    elseif Config.FactionCheck.checkType == "job" then
        return playerData.job and playerData.job.name == Config.FactionCheck.factionName
    end
    
    return false
end

-- Lagerhaus kaufen
RegisterNetEvent('warehouse:server:purchase')
AddEventHandler('warehouse:server:purchase', function(warehouseId)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    
    if not Player then return end
    
    -- Prüfe Fraktionsmitgliedschaft
    if not IsIronUnionMember(Player) then
        notifyNotFaction(src)
        return
    end
    
    local ownerKey = getWarehouseOwnerKey(Player)
    local warehouse = Config.Warehouses[warehouseId]
    
    if not warehouse then
        notifyPlayer(src, 'Ungültiges Lagerhaus!', 'error')
        return
    end
    
    if not ownerKey then
        notifyNotFaction(src)
        return
    end

    if Warehouses[ownerKey] then
        notifyPlayer(src, 'Deine Fraktion besitzt bereits ein Lagerhaus!', 'error')
        return
    end

    local bankMoney = 0
    if Player.getAccount then
        local bankAccount = Player.getAccount('bank')
        if bankAccount then
            bankMoney = bankAccount.money or 0
        end
    end

    if bankMoney < warehouse.price then
        notifyPlayer(src, 'Nicht genug Geld auf dem Bankkonto!', 'error')
        return
    end

    if not Player.removeAccountMoney then
        notifyPlayer(src, 'ESX Konto-Funktion fehlt (removeAccountMoney).', 'error')
        return
    end

    Player.removeAccountMoney('bank', warehouse.price, 'warehouse-purchase')

    Warehouses[ownerKey] = {
        id = warehouseId,
        purchaseDate = os.date('%Y-%m-%d %H:%M:%S')
    }
    
    WarehouseStats[ownerKey] = WarehouseStats[ownerKey] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    
    MySQL.Async.execute('INSERT INTO player_warehouses (citizenid, warehouse_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE warehouse_id = VALUES(warehouse_id)', { ownerKey, warehouseId })
    MySQL.Async.execute('INSERT IGNORE INTO warehouse_stats (citizenid) VALUES (?)', { ownerKey })
    
    TriggerClientEvent('warehouse:client:purchaseSuccess', src, warehouseId)
    broadcastFactionWarehouse(warehouseId)
    TriggerEvent('warehouse:server:log', src, 'Lagerhaus gekauft: ' .. warehouse.name .. ' für $' .. warehouse.price)
end)

-- Lagerhaus-Inventar abrufen
RegisterNetEvent('warehouse:server:getInventory')
AddEventHandler('warehouse:server:getInventory', function(warehouseId)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    
    if not Player then return end
    
    -- Prüfe Fraktionsmitgliedschaft
    if not IsIronUnionMember(Player) then
        notifyNotFaction(src)
        return
    end
    
    local ownerKey = getWarehouseOwnerKey(Player)
    if not ownerKey then
        notifyNotFaction(src)
        return
    end

    if not hasValidWarehouse(ownerKey, warehouseId) then
        notifyPlayer(src, 'Du besitzt dieses Lagerhaus nicht.', 'error')
        return
    end

    local inventory = getCargoInventoryForOwner(ownerKey)
    local stats = WarehouseStats[ownerKey] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    
    TriggerClientEvent('warehouse:client:openMenu', src, inventory, stats)
end)

RegisterNetEvent('warehouse:server:startSourceMission')
AddEventHandler('warehouse:server:startSourceMission', function(warehouseId, cargoType)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    if not Player then
        TriggerClientEvent('warehouse:client:sourceMissionAuth', src, false)
        return
    end

    local function fail(message)
        if message then
            notifyPlayer(src, message, 'error')
        end
        TriggerClientEvent('warehouse:client:sourceMissionAuth', src, false)
    end

    if ActiveSourceMissions[src] then
        fail('Du hast bereits eine aktive Beschaffungsmission.')
        return
    end

    if not IsIronUnionMember(Player) then
        notifyNotFaction(src)
        TriggerClientEvent('warehouse:client:sourceMissionAuth', src, false)
        return
    end

    if not Config.CargoTypes[cargoType] then
        fail('Ungültiger Warentyp!')
        return
    end

    local ownerKey = getWarehouseOwnerKey(Player)
    if not ownerKey then
        notifyNotFaction(src)
        TriggerClientEvent('warehouse:client:sourceMissionAuth', src, false)
        return
    end

    if not hasValidWarehouse(ownerKey, warehouseId) then
        fail('Du besitzt dieses Lagerhaus nicht.')
        return
    end

    local sourceCfg = (Config.Mission and Config.Mission.source) or {}
    local minCrates = tonumber(sourceCfg.minCrates) or 1
    local maxCrates = tonumber(sourceCfg.maxCrates) or 3
    if maxCrates < minCrates then
        maxCrates = minCrates
    end

    local approvedAmount = math.random(minCrates, maxCrates)
    ActiveSourceMissions[src] = {
        ownerKey = ownerKey,
        warehouseId = warehouseId,
        cargoType = cargoType,
        amount = approvedAmount,
        collected = 0,
        token = ('smug:%s:%s:%s'):format(src, os.time(), math.random(1000, 9999)),
        startedAt = os.time()
    }

    TriggerClientEvent('warehouse:client:sourceMissionAuth', src, true, approvedAmount)
end)

RegisterNetEvent('warehouse:server:collectSourceCargo')
AddEventHandler('warehouse:server:collectSourceCargo', function(warehouseId, cargoType)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    if not Player then
        TriggerClientEvent('warehouse:client:collectCargoResult', src, false)
        return
    end

    local function fail(message)
        if message then
            notifyPlayer(src, message, 'error')
        end
        TriggerClientEvent('warehouse:client:collectCargoResult', src, false)
    end

    if not Config.CargoTypes[cargoType] then
        fail('Ungültiger Warentyp!')
        return
    end

    local ownerKey = getWarehouseOwnerKey(Player)
    if not ownerKey then
        notifyNotFaction(src)
        TriggerClientEvent('warehouse:client:collectCargoResult', src, false)
        return
    end

    local sourceMission = ActiveSourceMissions[src]
    if not sourceMission then
        fail('Keine aktive Beschaffungsmission gefunden.')
        return
    end

    if sourceMission.ownerKey ~= ownerKey
        or sourceMission.warehouseId ~= warehouseId
        or sourceMission.cargoType ~= cargoType
    then
        fail('Ungültige Missionsdaten.')
        return
    end

    local collected = tonumber(sourceMission.collected) or 0
    local amount = tonumber(sourceMission.amount) or 0
    if collected >= amount then
        fail('Alle Kisten wurden bereits eingesammelt.')
        return
    end

    local itemName = getCargoItemName(cargoType)
    local metadata = getSourceMissionMetadata(sourceMission)
    local added, addReason = exports.ox_inventory:AddItem(src, itemName, 1, metadata)
    if not added then
        if Config.Debug and addReason then
            print(('[LAGERHAUS][DEBUG] Collect AddItem fehlgeschlagen (%s): %s'):format(cargoType, tostring(addReason)))
        end
        fail('Kein Platz im Inventar für die Ware.')
        return
    end

    sourceMission.collected = collected + 1
    TriggerClientEvent('warehouse:client:collectCargoResult', src, true, sourceMission.collected, sourceMission.amount)
end)

-- Waren einlagern
RegisterNetEvent('warehouse:server:storeCargo')
AddEventHandler('warehouse:server:storeCargo', function(warehouseId, cargoType)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    
    if not Player then
        TriggerClientEvent('warehouse:client:storeCargoResult', src, false)
        return
    end

    local function fail(message)
        if message then
            notifyPlayer(src, message, 'error')
        end
        TriggerClientEvent('warehouse:client:storeCargoResult', src, false)
    end
    
    -- Prüfe Fraktionsmitgliedschaft
    if not IsIronUnionMember(Player) then
        notifyNotFaction(src)
        TriggerClientEvent('warehouse:client:storeCargoResult', src, false)
        return
    end

    if not Config.CargoTypes[cargoType] then
        fail('Ungültiger Warentyp!')
        return
    end

    local ownerKey = getWarehouseOwnerKey(Player)
    if not ownerKey then
        notifyNotFaction(src)
        TriggerClientEvent('warehouse:client:storeCargoResult', src, false)
        return
    end

    if not hasValidWarehouse(ownerKey, warehouseId) then
        fail('Du besitzt dieses Lagerhaus nicht.')
        return
    end

    local sourceMission = ActiveSourceMissions[src]
    if not sourceMission then
        fail('Keine aktive Beschaffungsmission gefunden.')
        return
    end

    if sourceMission.ownerKey ~= ownerKey
        or sourceMission.warehouseId ~= warehouseId
        or sourceMission.cargoType ~= cargoType
    then
        fail('Ungültige Missionsdaten.')
        return
    end

    local amount = tonumber(sourceMission.amount) or 0
    if amount <= 0 then
        fail('Ungültige Warenmenge!')
        return
    end

    local collected = tonumber(sourceMission.collected) or 0
    if collected < amount then
        fail(('Du musst zuerst alle Kisten einsammeln (%s/%s).'):format(collected, amount))
        return
    end
    
    local inventory, totalCrates = getCargoInventoryForOwner(ownerKey)
    
    local warehouse = Config.Warehouses[warehouseId]
    if totalCrates + amount > warehouse.capacity then
        fail('Lagerhaus ist voll!')
        return
    end

    local itemName = getCargoItemName(cargoType)
    local sourceMetadata = getSourceMissionMetadata(sourceMission)
    local removedFromPlayer = exports.ox_inventory:RemoveItem(src, itemName, amount, sourceMetadata)
    if not removedFromPlayer then
        fail('Dir fehlt die eingesammelte Ware im Inventar.')
        return
    end

    local success, reason = addCargoToInventory(ownerKey, cargoType, amount)
    if not success then
        exports.ox_inventory:AddItem(src, itemName, amount, sourceMetadata)
        if Config.Debug and reason then
            print(('[LAGERHAUS][DEBUG] AddItem fehlgeschlagen (%s): %s'):format(cargoType, tostring(reason)))
        end
        fail('Konnte Ware nicht einlagern. Prüfe Item-Definition in ox_inventory.')
        return
    end

    -- Statistik aktualisieren
    WarehouseStats[ownerKey] = WarehouseStats[ownerKey] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    WarehouseStats[ownerKey].missionsCompleted = (WarehouseStats[ownerKey].missionsCompleted or 0) + 1
    WarehouseStats[ownerKey].totalMissions = (WarehouseStats[ownerKey].totalMissions or 0) + 1
    
    MySQL.Async.execute('UPDATE warehouse_stats SET missions_completed = missions_completed + 1, total_missions = total_missions + 1 WHERE citizenid = ?', {ownerKey})
    
    clearSourceMissionForSource(src)
    notifyPlayer(src, amount .. ' Kisten ' .. Config.CargoTypes[cargoType].label .. ' eingelagert!', 'success')
    TriggerClientEvent('warehouse:client:storeCargoResult', src, true, cargoType, amount)
end)

RegisterNetEvent('warehouse:server:startSellLoad')
AddEventHandler('warehouse:server:startSellLoad', function(warehouseId, vehiclePlate)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    if not Player then
        TriggerClientEvent('warehouse:client:sellLoadResult', src, false)
        return
    end

    local function fail(message)
        if message then
            notifyPlayer(src, message, 'error')
        end
        TriggerClientEvent('warehouse:client:sellLoadResult', src, false)
    end

    if not IsIronUnionMember(Player) then
        notifyNotFaction(src)
        TriggerClientEvent('warehouse:client:sellLoadResult', src, false)
        return
    end

    local ownerKey = getWarehouseOwnerKey(Player)
    if not ownerKey then
        notifyNotFaction(src)
        TriggerClientEvent('warehouse:client:sellLoadResult', src, false)
        return
    end

    if not hasValidWarehouse(ownerKey, warehouseId) then
        fail('Du besitzt dieses Lagerhaus nicht.')
        return
    end

    if ActiveSellLoads[ownerKey] then
        fail('Für dieses Lagerhaus läuft bereits eine Verkaufsmission.')
        return
    end

    local success, errorMessage, _, totalCrates = reserveWarehouseCargoForSell(ownerKey, src, vehiclePlate)
    if not success then
        fail(errorMessage)
        return
    end

    notifyPlayer(src, ('%s Kisten in das Lieferfahrzeug geladen.'):format(totalCrates), 'success')
    TriggerClientEvent('warehouse:client:sellLoadResult', src, true, totalCrates)
end)

RegisterNetEvent('warehouse:server:cancelSellLoad')
AddEventHandler('warehouse:server:cancelSellLoad', function()
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    if not Player then
        return
    end

    local ownerKey = getWarehouseOwnerKey(Player)
    if not ownerKey then
        return
    end

    local active = ActiveSellLoads[ownerKey]
    if not active then
        return
    end

    if active.startedBy ~= src then
        return
    end

    returnSellLoadToWarehouse(ownerKey)
    notifyPlayer(src, 'Verkaufsmission abgebrochen. Ware wurde ins Lagerhaus zurückgelegt.', 'inform')
end)

RegisterNetEvent('warehouse:server:cancelSourceMission')
AddEventHandler('warehouse:server:cancelSourceMission', function()
    local src = source
    if not ActiveSourceMissions[src] then
        return
    end

    clearSourceMissionForSource(src, true)
end)

-- Verkauf abschließen
RegisterNetEvent('warehouse:server:completeSell')
AddEventHandler('warehouse:server:completeSell', function(warehouseId)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    
    if not Player then
        TriggerClientEvent('warehouse:client:completeSellResult', src, false)
        return
    end

    local function fail(message)
        if message then
            notifyPlayer(src, message, 'error')
        end
        TriggerClientEvent('warehouse:client:completeSellResult', src, false)
    end
    
    -- Prüfe Fraktionsmitgliedschaft
    if not IsIronUnionMember(Player) then
        notifyNotFaction(src)
        TriggerClientEvent('warehouse:client:completeSellResult', src, false)
        return
    end

    local deliveryCfg = Config.Delivery or {}
    local requiredModel = GetHashKey(deliveryCfg.vehicleModel or 'mule')
    local requireDriver = deliveryCfg.requireDriver ~= false
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        fail('Du musst mit dem Lieferfahrzeug ausliefern.')
        return
    end

    if GetEntityModel(vehicle) ~= requiredModel then
        fail('Falsches Lieferfahrzeug. Nutze das Missionsfahrzeug.')
        return
    end
    if requireDriver and GetPedInVehicleSeat(vehicle, -1) ~= ped then
        fail('Du musst Fahrer des Lieferfahrzeugs sein.')
        return
    end
    
    local ownerKey = getWarehouseOwnerKey(Player)
    if not ownerKey then
        notifyNotFaction(src)
        TriggerClientEvent('warehouse:client:completeSellResult', src, false)
        return
    end

    if not hasValidWarehouse(ownerKey, warehouseId) then
        fail('Du besitzt dieses Lagerhaus nicht.')
        return
    end

    local activeLoad = ActiveSellLoads[ownerKey]
    if not activeLoad or not activeLoad.cargo then
        fail('Keine Ware im Lieferfahrzeug geladen.')
        return
    end

    if activeLoad.startedBy ~= src then
        fail('Diese Verkaufsmission gehört einem anderen Fraktionsmitglied.')
        return
    end

    local currentPlate = normalizePlate(GetVehicleNumberPlateText(vehicle) or '')
    if activeLoad.vehiclePlate and currentPlate ~= activeLoad.vehiclePlate then
        fail('Das falsche Lieferfahrzeug wurde verwendet.')
        return
    end

    local inventory = activeLoad.cargo
    local trunkInventoryId = activeLoad.trunkInventoryId
    local totalValue = 0
    local priceScale = getWarehousePriceScale(warehouseId)
    
    for cargoType, amount in pairs(inventory) do
        if amount > 0 then
            local availableInTrunk, detectedTrunkId = getCargoInTrunk(activeLoad.vehiclePlate, cargoType, trunkInventoryId)
            trunkInventoryId = detectedTrunkId or trunkInventoryId
            local sellAmount = math.min(availableInTrunk, amount)
            if sellAmount <= 0 then
                goto continue
            end

            local removed, removeReason = removeCargoFromTrunk(activeLoad.vehiclePlate, cargoType, sellAmount, trunkInventoryId)
            if not removed then
                if Config.Debug then
                    print(('[LAGERHAUS][DEBUG] removeCargoFromTrunk fehlgeschlagen (%s): %s'):format(cargoType, tostring(removeReason)))
                end
                fail('Fehler beim Entladen des Lieferfahrzeugs.')
                return
            end

            local cargoData = Config.CargoTypes[cargoType]
            if not cargoData then
                goto continue
            end
            -- Wert basierend auf Menge (mehr Ware = höherer Preis pro Kiste)
            local valuePerCrate = math.floor(cargoData.basePrice + ((cargoData.maxPrice - cargoData.basePrice) * (sellAmount / priceScale)))
            local cargoValue = valuePerCrate * sellAmount
            
            totalValue = totalValue + cargoValue
        end
        ::continue::
    end
    
    if totalValue == 0 then
        fail('Keine Ware zu verkaufen!')
        return
    end
    
    -- Bezahlung
    if Player.addMoney then
        Player.addMoney(totalValue, 'warehouse-sell')
    elseif Player.addAccountMoney then
        Player.addAccountMoney('money', totalValue, 'warehouse-sell')
    else
        fail('ESX Geld-Funktion fehlt (addMoney/addAccountMoney).')
        return
    end
    
    clearSellLoadForOwner(ownerKey)
    -- Statistik aktualisieren
    WarehouseStats[ownerKey] = WarehouseStats[ownerKey] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    WarehouseStats[ownerKey].totalEarned = (WarehouseStats[ownerKey].totalEarned or 0) + totalValue
    MySQL.Async.execute('UPDATE warehouse_stats SET total_earned = total_earned + ? WHERE citizenid = ?', {totalValue, ownerKey})
    
    notifyPlayer(src, 'Verkauf abgeschlossen! Du erhältst $' .. formatNumber(totalValue), 'success')
    TriggerClientEvent('warehouse:client:completeSellResult', src, true, totalValue)
    
    TriggerEvent('warehouse:server:log', src, 'Verkauf für $' .. totalValue)
end)

-- Polizei-Alarm mit Risikowert
RegisterNetEvent('warehouse:server:alertPolice')
AddEventHandler('warehouse:server:alertPolice', function(coords, message, dispatchType)
    if Config.Police and Config.Police.enabled == false then
        return
    end

    local src = source
    local dispatchKind = dispatchType or 'default'
    if not shouldAllowDispatch(src, coords, dispatchKind) then
        return
    end

    local alertMessage = message or 'Verdächtige Lagerhaus-Aktivität'
    dispatchPoliceAlert(coords, alertMessage)
end)

-- Risikolevel prüfen für Verkaufsmission
RegisterNetEvent('warehouse:server:checkRiskLevel')
AddEventHandler('warehouse:server:checkRiskLevel', function(warehouseId)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    
    if not Player then return end
    
    -- Prüfe Fraktionsmitgliedschaft
    if not IsIronUnionMember(Player) then
        return
    end
    
    local ownerKey = getWarehouseOwnerKey(Player)
    if not ownerKey then
        return
    end

    if not hasValidWarehouse(ownerKey, warehouseId) then
        return
    end

    local activeLoad = ActiveSellLoads[ownerKey]
    local inventory = activeLoad and activeLoad.cargo or getCargoInventoryForOwner(ownerKey)
    local highRiskThreshold = ((Config.Mission and Config.Mission.source) and Config.Mission.source.highRiskWarningLevel) or 3
    
    local hasHighRisk = false
    local maxRiskLevel = 0
    local totalPoliceChance = 0
    
    for cargoType, amount in pairs(inventory) do
        if amount > 0 then
            local cargoData = Config.CargoTypes[cargoType]
            if cargoData then
                if cargoData.riskLevel > maxRiskLevel then
                    maxRiskLevel = cargoData.riskLevel
                end
                if cargoData.riskLevel >= highRiskThreshold then
                    hasHighRisk = true
                    totalPoliceChance = totalPoliceChance + cargoData.policeChance
                end
            end
        end
    end
    
    -- An Client senden
    TriggerClientEvent('warehouse:client:riskLevelInfo', src, hasHighRisk, maxRiskLevel, totalPoliceChance)
end)

-- Spieler laden
RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local src = playerId or source
    local Player = xPlayer or ESX.GetPlayerFromId(src)
    
    if not Player then return end

    syncWarehouseStateForPlayer(src, Player, 1000)
end)

RegisterNetEvent('warehouse:server:syncWarehouseState')
AddEventHandler('warehouse:server:syncWarehouseState', function()
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    if not Player then
        return
    end

    syncWarehouseStateForPlayer(src, Player, 0)
end)

-- Admin Befehle
RegisterCommand('givewarehouse', function(source, args)
    if not isAdmin(source) then
        notifySource(source, 'Keine Berechtigung für diesen Befehl.', 'error')
        return
    end

    local targetId = tonumber(args[1])
    local warehouseId = tonumber(args[2])

    if not targetId or not warehouseId then
        notifySource(source, 'Nutzung: /givewarehouse [id] [warehouseid]', 'error')
        return
    end

    if not Config.Warehouses[warehouseId] then
        notifySource(source, 'Ungültige Warehouse ID.', 'error')
        return
    end

    local targetPlayer = ESX.GetPlayerFromId(targetId)
    
    if not targetPlayer then
        notifySource(source, 'Spieler nicht gefunden!', 'error')
        return
    end
    
    local ownerKey = getWarehouseOwnerKey(targetPlayer)
    if not ownerKey then
        notifySource(source, 'Zielspieler ist nicht in der Fraktion.', 'error')
        return
    end
    
    Warehouses[ownerKey] = {
        id = warehouseId,
        purchaseDate = os.date('%Y-%m-%d %H:%M:%S')
    }

    WarehouseStats[ownerKey] = WarehouseStats[ownerKey] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    
    MySQL.Async.execute('INSERT INTO player_warehouses (citizenid, warehouse_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE warehouse_id = ?', { ownerKey, warehouseId, warehouseId })
    MySQL.Async.execute('INSERT IGNORE INTO warehouse_stats (citizenid) VALUES (?)', { ownerKey })
    
    broadcastFactionWarehouse(warehouseId)
    notifySource(source, 'Lagerhaus gegeben!', 'success')
end, false)

RegisterCommand('resetwarehouse', function(source, args)
    if not isAdmin(source) then
        notifySource(source, 'Keine Berechtigung für diesen Befehl.', 'error')
        return
    end

    local targetId = tonumber(args[1])

    if not targetId then
        notifySource(source, 'Nutzung: /resetwarehouse [id]', 'error')
        return
    end

    local targetPlayer = ESX.GetPlayerFromId(targetId)
    
    if not targetPlayer then
        notifySource(source, 'Spieler nicht gefunden!', 'error')
        return
    end
    
    local ownerKey = getWarehouseOwnerKey(targetPlayer)
    if not ownerKey then
        notifySource(source, 'Zielspieler ist nicht in der Fraktion.', 'error')
        return
    end
    
    Warehouses[ownerKey] = nil
    WarehouseStats[ownerKey] = nil
    clearSellLoadForOwner(ownerKey)
    clearWarehouseStash(ownerKey)
    
    MySQL.Async.execute('DELETE FROM player_warehouses WHERE citizenid = ?', {ownerKey})
    MySQL.Async.execute('DELETE FROM warehouse_stats WHERE citizenid = ?', {ownerKey})
    
    broadcastFactionWarehouse(nil)
    notifySource(source, 'Lagerhaus zurückgesetzt!', 'success')
end, false)

RegisterCommand('warehouseinfo', function(source)
    if source == 0 then
        print('[LAGERHAUS] Dieser Befehl ist nur ingame nutzbar.')
        return
    end

    local Player = ESX.GetPlayerFromId(source)
    if not Player then
        return
    end

    local ownerKey = getWarehouseOwnerKey(Player)
    if not ownerKey then
        notifySource(source, 'Du bist kein Mitglied der Fraktion.', 'error')
        return
    end
    
    if not Warehouses[ownerKey] then
        notifySource(source, 'Deine Fraktion besitzt kein Lagerhaus!', 'error')
        return
    end
    
    local warehouse = Config.Warehouses[Warehouses[ownerKey].id]
    local inventory = getCargoInventoryForOwner(ownerKey)
    local stats = WarehouseStats[ownerKey] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    
    local totalCrates = 0
    for _, amount in pairs(inventory) do
        totalCrates = totalCrates + amount
    end
    
    TriggerClientEvent('chat:addMessage', source, {
        color = {46, 125, 50},
        multiline = true,
        args = {'[LAGERHAUS]', '=== ' .. warehouse.name .. ' ==='}
    })
    
    TriggerClientEvent('chat:addMessage', source, {
        color = {46, 125, 50},
        multiline = true,
        args = {'[LAGERHAUS]', 'Lager: ' .. totalCrates .. '/' .. warehouse.capacity .. ' Kisten'}
    })
    
    TriggerClientEvent('chat:addMessage', source, {
        color = {46, 125, 50},
        multiline = true,
        args = {'[LAGERHAUS]', 'Gesamtverdienst: $' .. formatNumber(stats.totalEarned)}
    })
    
    TriggerClientEvent('chat:addMessage', source, {
        color = {46, 125, 50},
        multiline = true,
        args = {'[LAGERHAUS]', 'Abgeschlossene Missionen: ' .. stats.missionsCompleted}
    })
end, false)

RegisterCommand('addcargo', function(source, args)
    if not isAdmin(source) then
        notifySource(source, 'Keine Berechtigung für diesen Befehl.', 'error')
        return
    end

    local targetId = tonumber(args[1])
    local cargoType = args[2]
    local amount = tonumber(args[3])

    if not targetId or not cargoType or not amount then
        notifySource(source, 'Nutzung: /addcargo [id] [type] [amount]', 'error')
        return
    end

    local targetPlayer = ESX.GetPlayerFromId(targetId)
    
    if not targetPlayer then
        notifySource(source, 'Spieler nicht gefunden!', 'error')
        return
    end
    
    if not Config.CargoTypes[cargoType] then
        notifySource(source, 'Ungültiger Warentyp!', 'error')
        return
    end
    
    local ownerKey = getWarehouseOwnerKey(targetPlayer)
    if not ownerKey then
        notifySource(source, 'Zielspieler ist nicht in der Fraktion.', 'error')
        return
    end

    if not Warehouses[ownerKey] then
        notifySource(source, 'Für diese Fraktion existiert kein Lagerhaus.', 'error')
        return
    end

    local success = addCargoToInventory(ownerKey, cargoType, amount)
    if not success then
        notifySource(source, 'Konnte Item nicht hinzufügen (Inventar voll oder Item fehlt).', 'error')
        return
    end

    notifySource(source, amount .. 'x ' .. cargoType .. ' hinzugefügt!', 'success')
end, false)

AddEventHandler('playerDropped', function()
    local src = source
    DispatchStateBySource[src] = nil
    clearSourceMissionForSource(src, true)

    local ownerKey = SellLoadBySource[src]
    if not ownerKey then
        return
    end

    local returned = returnSellLoadToWarehouse(ownerKey)
    if returned and Config.Debug then
        print(('[LAGERHAUS][DEBUG] Verkaufsfracht nach Disconnect zurück ins Lager gelegt (owner=%s, src=%s)'):format(tostring(ownerKey), tostring(src)))
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    for ownerKey in pairs(ActiveSellLoads) do
        returnSellLoadToWarehouse(ownerKey)
    end
end)

-- Logging
RegisterNetEvent('warehouse:server:log')
AddEventHandler('warehouse:server:log', function(playerId, message)
    print('[LAGERHAUS] Spieler ' .. playerId .. ': ' .. message)
end)

function formatNumber(number)
    local formatted = tostring(number)
    while true do
        local k
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end
