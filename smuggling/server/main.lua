-- GTA Online Style Warehouse Smuggling System - Server
local ESX = exports['es_extended']:getSharedObject()

Warehouses = {}
WarehouseInventory = {}
WarehouseStats = {}

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
        local amount = exports.ox_inventory:Search(stashId, 'count', itemName) or 0
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

local function sendRoadPhoneDispatch(src, coords, alertMessage)
    local dispatchCfg = Config.Dispatch or {}
    local roadPhoneCfg = dispatchCfg.roadphone or {}
    local resourceName = roadPhoneCfg.resource or 'roadphone'
    local dispatchJob = roadPhoneCfg.jobName or (Config.Police and Config.Police.jobName) or 'police'
    local mode = roadPhoneCfg.mode or 'auto'
    local thirdArg = nil

    if roadPhoneCfg.useCoordsAsThirdArg and coords then
        thirdArg = { x = coords.x, y = coords.y, z = coords.z }
    end

    if GetResourceState(resourceName) ~= 'started' then
        return false
    end

    if mode ~= 'client' then
        local serverOk = pcall(function()
            exports[resourceName]:sendDispatch(alertMessage, dispatchJob, thirdArg)
        end)
        if serverOk then
            return true
        end
    end

    if mode ~= 'server' and src and src > 0 then
        TriggerClientEvent('warehouse:client:roadphoneDispatch', src, alertMessage, dispatchJob, thirdArg, resourceName)
        return true
    end

    return false
end

local function dispatchPoliceAlert(src, coords, alertMessage)
    local dispatchCfg = Config.Dispatch or {}
    local provider = dispatchCfg.provider or 'legacy'

    if provider == 'roadphone' then
        local sent = sendRoadPhoneDispatch(src, coords, alertMessage)
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
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS player_warehouses (
            citizenid VARCHAR(50) PRIMARY KEY,
            warehouse_id INT,
            purchase_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]], {})
    
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS warehouse_inventory (
            citizenid VARCHAR(50),
            cargo_type VARCHAR(50),
            amount INT DEFAULT 0,
            PRIMARY KEY (citizenid, cargo_type)
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
    
    MySQL.Async.fetchAll('SELECT * FROM warehouse_inventory', {}, function(result)
        for _, row in ipairs(result) do
            if not WarehouseInventory[row.citizenid] then
                WarehouseInventory[row.citizenid] = {}
            end
            WarehouseInventory[row.citizenid][row.cargo_type] = row.amount
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
    
    WarehouseInventory[ownerKey] = WarehouseInventory[ownerKey] or {}
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

-- Waren einlagern
RegisterNetEvent('warehouse:server:storeCargo')
AddEventHandler('warehouse:server:storeCargo', function(warehouseId, cargoType, amount)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    
    if not Player then return end
    
    -- Prüfe Fraktionsmitgliedschaft
    if not IsIronUnionMember(Player) then
        notifyNotFaction(src)
        return
    end

    if not Config.CargoTypes[cargoType] then
        notifyPlayer(src, 'Ungültiger Warentyp!', 'error')
        return
    end

    amount = tonumber(amount) or 0
    if amount <= 0 then
        notifyPlayer(src, 'Ungültige Warenmenge!', 'error')
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
    
    if not WarehouseInventory[ownerKey] then
        WarehouseInventory[ownerKey] = {}
    end

    local inventory, totalCrates = getCargoInventoryForOwner(ownerKey)
    local currentAmount = inventory[cargoType] or 0
    
    local warehouse = Config.Warehouses[warehouseId]
    if totalCrates + amount > warehouse.capacity then
        notifyPlayer(src, 'Lagerhaus ist voll!', 'error')
        return
    end

    local success = addCargoToInventory(ownerKey, cargoType, amount)
    if not success then
        notifyPlayer(src, 'Nicht genug Platz im Inventar für diese Ware!', 'error')
        return
    end

    WarehouseInventory[ownerKey][cargoType] = currentAmount + amount
    
    -- Statistik aktualisieren
    WarehouseStats[ownerKey] = WarehouseStats[ownerKey] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    WarehouseStats[ownerKey].missionsCompleted = (WarehouseStats[ownerKey].missionsCompleted or 0) + 1
    WarehouseStats[ownerKey].totalMissions = (WarehouseStats[ownerKey].totalMissions or 0) + 1
    
    MySQL.Async.execute('UPDATE warehouse_stats SET missions_completed = missions_completed + 1, total_missions = total_missions + 1 WHERE citizenid = ?', {ownerKey})
    
    notifyPlayer(src, amount .. ' Kisten ' .. Config.CargoTypes[cargoType].label .. ' eingelagert!', 'success')
end)

-- Verkauf abschließen
RegisterNetEvent('warehouse:server:completeSell')
AddEventHandler('warehouse:server:completeSell', function(warehouseId)
    local src = source
    local Player = ESX.GetPlayerFromId(src)
    
    if not Player then return end
    
    -- Prüfe Fraktionsmitgliedschaft
    if not IsIronUnionMember(Player) then
        notifyNotFaction(src)
        return
    end

    local deliveryCfg = Config.Delivery or {}
    local requiredModel = GetHashKey(deliveryCfg.vehicleModel or Config.DeliveryVehicle or 'mule')
    local requireDriver = deliveryCfg.requireDriver ~= false
    local ped = GetPlayerPed(src)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        notifyPlayer(src, 'Du musst mit dem Lieferfahrzeug ausliefern.', 'error')
        return
    end

    if GetEntityModel(vehicle) ~= requiredModel then
        notifyPlayer(src, 'Falsches Lieferfahrzeug. Nutze das Missionsfahrzeug.', 'error')
        return
    end
    if requireDriver and GetPedInVehicleSeat(vehicle, -1) ~= ped then
        notifyPlayer(src, 'Du musst Fahrer des Lieferfahrzeugs sein.', 'error')
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
    local totalValue = 0
    local priceScale = getWarehousePriceScale(warehouseId)
    
    for cargoType, amount in pairs(inventory) do
        if amount > 0 then
            local removed = removeCargoFromInventory(ownerKey, cargoType, amount)
            if not removed then
                notifyPlayer(src, 'Fehler beim Entfernen von ' .. cargoType .. ' aus dem Inventar.', 'error')
                goto continue
            end

            local cargoData = Config.CargoTypes[cargoType]
            -- Wert basierend auf Menge (mehr Ware = höherer Preis pro Kiste)
            local valuePerCrate = math.floor(cargoData.basePrice + ((cargoData.maxPrice - cargoData.basePrice) * (amount / priceScale)))
            local cargoValue = valuePerCrate * amount
            
            totalValue = totalValue + cargoValue
        end
        ::continue::
    end
    
    if totalValue == 0 then
        notifyPlayer(src, 'Keine Ware zu verkaufen!', 'error')
        return
    end
    
    -- Bezahlung
    if Player.addMoney then
        Player.addMoney(totalValue, 'warehouse-sell')
    elseif Player.addAccountMoney then
        Player.addAccountMoney('money', totalValue, 'warehouse-sell')
    else
        notifyPlayer(src, 'ESX Geld-Funktion fehlt (addMoney/addAccountMoney).', 'error')
        return
    end
    
    -- In-Memory Cache nach Verkauf aktualisieren
    WarehouseInventory[ownerKey] = {}
    for cargoType in pairs(Config.CargoTypes) do
        WarehouseInventory[ownerKey][cargoType] = 0
    end
    
    -- Statistik aktualisieren
    WarehouseStats[ownerKey] = WarehouseStats[ownerKey] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    WarehouseStats[ownerKey].totalEarned = (WarehouseStats[ownerKey].totalEarned or 0) + totalValue
    MySQL.Async.execute('UPDATE warehouse_stats SET total_earned = total_earned + ? WHERE citizenid = ?', {totalValue, ownerKey})
    
    notifyPlayer(src, 'Verkauf abgeschlossen! Du erhältst $' .. formatNumber(totalValue), 'success')
    
    TriggerEvent('warehouse:server:log', src, 'Verkauf für $' .. totalValue)
end)

-- Polizei-Alarm mit Risikowert
RegisterNetEvent('warehouse:server:alertPolice')
AddEventHandler('warehouse:server:alertPolice', function(coords, message)
    if Config.Police and Config.Police.enabled == false then
        return
    end

    local src = source
    local alertMessage = message or 'Verdächtige Lagerhaus-Aktivität'
    dispatchPoliceAlert(src, coords, alertMessage)
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

    local inventory = getCargoInventoryForOwner(ownerKey)
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

    WarehouseInventory[ownerKey] = WarehouseInventory[ownerKey] or {}
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
    WarehouseInventory[ownerKey] = nil
    WarehouseStats[ownerKey] = nil
    clearWarehouseStash(ownerKey)
    
    MySQL.Async.execute('DELETE FROM player_warehouses WHERE citizenid = ?', {ownerKey})
    MySQL.Async.execute('DELETE FROM warehouse_inventory WHERE citizenid = ?', {ownerKey})
    MySQL.Async.execute('DELETE FROM warehouse_stats WHERE citizenid = ?', {ownerKey})
    
    broadcastFactionWarehouse(nil)
    notifySource(source, 'Lagerhaus zurückgesetzt!', 'success')
end, false)

RegisterCommand('warehouseinfo', function(source, args)
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

    WarehouseInventory[ownerKey] = WarehouseInventory[ownerKey] or {}
    WarehouseInventory[ownerKey][cargoType] = (WarehouseInventory[ownerKey][cargoType] or 0) + amount

    notifySource(source, amount .. 'x ' .. cargoType .. ' hinzugefügt!', 'success')
end, false)

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
