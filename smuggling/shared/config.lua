Config = {}

Config.FactionCheck = {
    enabled = true,
    factionName = "the iron union",
    checkType = "job" -- "gang" oder "job"
}

Config.Debug = false

Config.Notify = {
    defaultDuration = 5000
}

Config.Warehouses = {
    [1] = { name = "Rancho Warehouse", coords = vector3(826.7, -3199.5, 5.9), price = 250000, capacity = 42 },
    [2] = { name = "La Mesa Warehouse", coords = vector3(919.4, -1517.0, 30.4), price = 400000, capacity = 42 },
    [3] = { name = "Cypress Flats Warehouse", coords = vector3(804.4, -2224.5, 29.5), price = 350000, capacity = 42 },
    [4] = { name = "LSIA Warehouse", coords = vector3(-1133.2, -3454.8, 13.9), price = 450000, capacity = 42 },
    [5] = { name = "Elysian Island Warehouse", coords = vector3(251.3, -3078.6, 5.8), price = 375000, capacity = 42 },
    [6] = { name = "Davis Quartz Warehouse", coords = vector3(2692.0, 3453.8, 55.7), price = 200000, capacity = 42 },
    [7] = { name = "Paleto Bay Warehouse", coords = vector3(-108.3, 6167.2, 31.2), price = 175000, capacity = 42 },
    [8] = { name = "Sandy Shores Warehouse", coords = vector3(1624.3, 3568.2, 35.2), price = 225000, capacity = 42 }
}

Config.CargoTypes = {
    ["specialcargo"] = { item = "specialcargo", label = "Spezialfracht", basePrice = 10000, maxPrice = 20000, riskLevel = 3, policeChance = 0.02 },
    ["electronics"] = { item = "electronics", label = "Elektronik", basePrice = 8000, maxPrice = 16000, riskLevel = 2, policeChance = 0.01 },
    ["medical"] = { item = "medical", label = "Medizinische Ware", basePrice = 12000, maxPrice = 24000, riskLevel = 1, policeChance = 0.005 },
    ["tobacco"] = { item = "tobacco", label = "Tabak & Alkohol", basePrice = 6000, maxPrice = 12000, riskLevel = 1, policeChance = 0.005 },
    ["counterfeit"] = { item = "counterfeit", label = "Fälschungen", basePrice = 7000, maxPrice = 14000, riskLevel = 3, policeChance = 0.02 },
    ["gems"] = { item = "gems", label = "Edelsteine", basePrice = 15000, maxPrice = 30000, riskLevel = 2, policeChance = 0.01 },
    ["weapons"] = { item = "weapons", label = "Waffen & Munition", basePrice = 20000, maxPrice = 40000, riskLevel = 4, policeChance = 0.05 },
    ["drugs"] = { item = "drugs", label = "Drogen", basePrice = 18000, maxPrice = 35000, riskLevel = 4, policeChance = 0.05 }
}

Config.SourceLocations = {
    -- Ausschliesslich Land Missionen
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
}

Config.SellLocations = {
    vector3(-1392.3, 21.4, 53.5),
    vector3(-631.9, -229.1, 38.1),
    vector3(818.9, -2159.2, 29.6),
    vector3(-1486.8, -909.0, 10.0),
    vector3(365.6, 340.5, 104.4),
    vector3(-596.4, -1601.2, 26.7)
}

Config.SourceVehicles = {
    -- Ausschliesslich Landfahrzeuge
    land = { "benson", "pounder", "mule", "biff", "pounder2", "phantom", "hauler", "barracks", "riot" }
}

Config.Economy = {
    -- Nur Anzeige im Menü (wird aktuell nicht abgebucht)
    sourceMissionBaseCost = 2000,
    sourceMissionCostIncrease = 500
}

Config.Inventory = {
    stashSlots = 250,
    stashMaxWeight = 2000000,
    stashLabelPrefix = "Fraktionslager"
}

Config.Target = {
    debug = false,
    warehouseRadius = 2.0,
    sourceCollectRadius = 6.0,
    returnStoreRadius = 4.0,
    sellRadius = 4.0
}

Config.TargetIcons = {
    warehouseBuy = 'fa-solid fa-warehouse',
    warehouseManage = 'fa-solid fa-box-open',
    warehouseSellStart = 'fa-solid fa-money-bill',
    sourceCollect = 'fa-solid fa-box',
    returnStore = 'fa-solid fa-warehouse',
    sellComplete = 'fa-solid fa-handshake'
}

Config.Blips = {
    warehouse = {
        sprite = 473,
        display = 4,
        scale = 0.8,
        colour = 2,
        shortRange = true
    },
    source = {
        sprite = 478,
        colour = 5,
        route = true,
        routeColour = 5
    },
    returnToWarehouse = {
        sprite = 501,
        colour = 2,
        route = true
    },
    sell = {
        sprite = 500,
        colour = 1,
        route = true
    },
    policeAlert = {
        sprite = 161,
        colour = 1,
        scale = 1.2,
        shortRange = false,
        duration = 60000,
        name = "Polizei Alarm"
    }
}

Config.Progress = {
    sourceCollect = 10000,
    storeCargo = 5000,
    completeSell = 10000
}

Config.Mission = {
    priceScaleCrates = 42,
    source = {
        monitorTick = 500,
        spawnDistance = 100.0,
        minCrates = 1,
        maxCrates = 3,
        highRiskWarningLevel = 3,
        highRiskWarningDuration = 5000,
        policeAlertNotifyDuration = 8000
    },
    sell = {
        monitorTick = 1000,
        highRiskDefaultChance = 0.001,
        lowRiskStartDelayMs = 30000,
        lowRiskPoliceChance = 0.0005,
        policeChaseNotifyDuration = 5000
    }
}

Config.Police = {
    enabled = true,
    jobName = "police",
    notifyDuration = 10000
}

Config.Dispatch = {
    provider = "roadphone", -- "roadphone" oder "legacy"
    fallbackToLegacy = true,
    roadphone = {
        resource = "roadphone",
        mode = "auto", -- "auto", "server", "client"
        jobName = "police",
        useCoordsAsThirdArg = false
    }
}

Config.Delivery = {
    vehicleModel = "mule",
    requireDriver = true,
    spawnOffset = vector3(4.0, 0.0, 0.0),
    platePrefix = "SMUG",
    plateMin = 100,
    plateMax = 999
}

-- Backward compatibility
Config.DeliveryVehicle = Config.Delivery.vehicleModel
