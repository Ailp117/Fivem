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

local function getPlayerIdentifier(xPlayer)
    return xPlayer.identifier
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
        notifyPlayer(src, 'Du bist kein Mitglied von The Iron Union!', 'error')
        return
    end
    
    local citizenid = getPlayerIdentifier(Player)
    local warehouse = Config.Warehouses[warehouseId]
    
    if not warehouse then
        notifyPlayer(src, 'Ungültiges Lagerhaus!', 'error')
        return
    end
    
    if Warehouses[citizenid] then
        notifyPlayer(src, 'Du besitzt bereits ein Lagerhaus!', 'error')
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

    Warehouses[citizenid] = {
        id = warehouseId,
        purchaseDate = os.date('%Y-%m-%d %H:%M:%S')
    }
    
    WarehouseInventory[citizenid] = WarehouseInventory[citizenid] or {}
    WarehouseStats[citizenid] = WarehouseStats[citizenid] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    
    MySQL.Async.execute('INSERT INTO player_warehouses (citizenid, warehouse_id) VALUES (?, ?)', { citizenid, warehouseId })
    MySQL.Async.execute('INSERT IGNORE INTO warehouse_stats (citizenid) VALUES (?)', { citizenid })
    
    TriggerClientEvent('warehouse:client:purchaseSuccess', src, warehouseId)
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
        notifyPlayer(src, 'Du bist kein Mitglied von The Iron Union!', 'error')
        return
    end
    
    local citizenid = getPlayerIdentifier(Player)
    local inventory = WarehouseInventory[citizenid] or {}
    local stats = WarehouseStats[citizenid] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    
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
        notifyPlayer(src, 'Du bist kein Mitglied von The Iron Union!', 'error')
        return
    end
    
    local citizenid = getPlayerIdentifier(Player)
    
    if not WarehouseInventory[citizenid] then
        WarehouseInventory[citizenid] = {}
    end
    
    local currentAmount = WarehouseInventory[citizenid][cargoType] or 0
    local totalCrates = 0
    
    for _, amt in pairs(WarehouseInventory[citizenid]) do
        totalCrates = totalCrates + amt
    end
    
    local warehouse = Config.Warehouses[warehouseId]
    if totalCrates + amount > warehouse.capacity then
        notifyPlayer(src, 'Lagerhaus ist voll!', 'error')
        return
    end
    
    WarehouseInventory[citizenid][cargoType] = currentAmount + amount
    
    MySQL.Async.execute([[
        INSERT INTO warehouse_inventory (citizenid, cargo_type, amount) 
        VALUES (?, ?, ?) 
        ON DUPLICATE KEY UPDATE amount = VALUES(amount)
    ]], {citizenid, cargoType, WarehouseInventory[citizenid][cargoType]})
    
    -- Statistik aktualisieren
    WarehouseStats[citizenid] = WarehouseStats[citizenid] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    WarehouseStats[citizenid].missionsCompleted = (WarehouseStats[citizenid].missionsCompleted or 0) + 1
    WarehouseStats[citizenid].totalMissions = (WarehouseStats[citizenid].totalMissions or 0) + 1
    
    MySQL.Async.execute('UPDATE warehouse_stats SET missions_completed = missions_completed + 1, total_missions = total_missions + 1 WHERE citizenid = ?', {citizenid})
    
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
        notifyPlayer(src, 'Du bist kein Mitglied von The Iron Union!', 'error')
        return
    end
    
    local citizenid = getPlayerIdentifier(Player)
    
    if not WarehouseInventory[citizenid] then
        notifyPlayer(src, 'Fehler: Keine Ware im Lager!', 'error')
        return
    end
    
    local totalValue = 0
    local soldCargo = {}
    
    for cargoType, amount in pairs(WarehouseInventory[citizenid]) do
        if amount > 0 then
            local cargoData = Config.CargoTypes[cargoType]
            -- Wert basierend auf Menge (mehr Ware = höherer Preis pro Kiste)
            local valuePerCrate = math.floor(cargoData.basePrice + ((cargoData.maxPrice - cargoData.basePrice) * (amount / 42)))
            local cargoValue = valuePerCrate * amount
            
            totalValue = totalValue + cargoValue
            soldCargo[cargoType] = amount
        end
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
    
    -- Inventar leeren
    for cargoType, amount in pairs(soldCargo) do
        WarehouseInventory[citizenid][cargoType] = 0
        MySQL.Async.execute([[
            INSERT INTO warehouse_inventory (citizenid, cargo_type, amount) 
            VALUES (?, ?, 0) 
            ON DUPLICATE KEY UPDATE amount = 0
        ]], {citizenid, cargoType})
    end
    
    -- Statistik aktualisieren
    WarehouseStats[citizenid] = WarehouseStats[citizenid] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    WarehouseStats[citizenid].totalEarned = (WarehouseStats[citizenid].totalEarned or 0) + totalValue
    MySQL.Async.execute('UPDATE warehouse_stats SET total_earned = total_earned + ? WHERE citizenid = ?', {totalValue, citizenid})
    
    notifyPlayer(src, 'Verkauf abgeschlossen! Du erhältst $' .. formatNumber(totalValue), 'success')
    
    TriggerEvent('warehouse:server:log', src, 'Verkauf für $' .. totalValue)
end)

-- Polizei-Alarm mit Risikowert
RegisterNetEvent('warehouse:server:alertPolice')
AddEventHandler('warehouse:server:alertPolice', function(coords, message)
    local src = source
    local alertMessage = message or 'Verdächtige Lagerhaus-Aktivität'
    
    for _, playerId in ipairs(ESX.GetPlayers()) do
        local policeId = tonumber(playerId)
        local Player = ESX.GetPlayerFromId(policeId)
        if Player and Player.job and Player.job.name == 'police' then
            TriggerClientEvent('warehouse:client:policeAlert', playerId, coords, alertMessage)
            notifyPlayer(policeId, 'ALARM: ' .. alertMessage, 'error', 10000)
        end
    end
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
    
    local citizenid = getPlayerIdentifier(Player)
    local inventory = WarehouseInventory[citizenid] or {}
    
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
                if cargoData.riskLevel >= 3 then
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
    
    local citizenid = getPlayerIdentifier(Player)
    
    Citizen.Wait(1000)
    
    if Warehouses[citizenid] then
        TriggerClientEvent('warehouse:client:hasWarehouse', src, Warehouses[citizenid].id)
    end
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
    
    local citizenid = getPlayerIdentifier(targetPlayer)
    
    Warehouses[citizenid] = {
        id = warehouseId,
        purchaseDate = os.date('%Y-%m-%d %H:%M:%S')
    }

    WarehouseInventory[citizenid] = WarehouseInventory[citizenid] or {}
    WarehouseStats[citizenid] = WarehouseStats[citizenid] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    
    MySQL.Async.execute('INSERT INTO player_warehouses (citizenid, warehouse_id) VALUES (?, ?) ON DUPLICATE KEY UPDATE warehouse_id = ?', { citizenid, warehouseId, warehouseId })
    MySQL.Async.execute('INSERT IGNORE INTO warehouse_stats (citizenid) VALUES (?)', { citizenid })
    
    TriggerClientEvent('warehouse:client:hasWarehouse', targetId, warehouseId)
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
    
    local citizenid = getPlayerIdentifier(targetPlayer)
    
    Warehouses[citizenid] = nil
    WarehouseInventory[citizenid] = nil
    WarehouseStats[citizenid] = nil
    
    MySQL.Async.execute('DELETE FROM player_warehouses WHERE citizenid = ?', {citizenid})
    MySQL.Async.execute('DELETE FROM warehouse_inventory WHERE citizenid = ?', {citizenid})
    MySQL.Async.execute('DELETE FROM warehouse_stats WHERE citizenid = ?', {citizenid})
    
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

    local citizenid = getPlayerIdentifier(Player)
    
    if not Warehouses[citizenid] then
        notifySource(source, 'Du besitzt kein Lagerhaus!', 'error')
        return
    end
    
    local warehouse = Config.Warehouses[Warehouses[citizenid].id]
    local inventory = WarehouseInventory[citizenid] or {}
    local stats = WarehouseStats[citizenid] or { totalEarned = 0, totalMissions = 0, missionsCompleted = 0 }
    
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
    
    local citizenid = getPlayerIdentifier(targetPlayer)
    
    if not WarehouseInventory[citizenid] then
        WarehouseInventory[citizenid] = {}
    end
    
    local currentAmount = WarehouseInventory[citizenid][cargoType] or 0
    WarehouseInventory[citizenid][cargoType] = currentAmount + amount
    
    MySQL.Async.execute([[
        INSERT INTO warehouse_inventory (citizenid, cargo_type, amount) 
        VALUES (?, ?, ?) 
        ON DUPLICATE KEY UPDATE amount = VALUES(amount)
    ]], {citizenid, cargoType, WarehouseInventory[citizenid][cargoType]})
    
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
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end
