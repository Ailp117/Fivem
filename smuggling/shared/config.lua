Config = {}

Config.FactionCheck = {
    enabled = true,
    factionName = "the iron union",
    checkType = "job" -- "gang" oder "job"
}

Config.Debug = true

Config.Notify = {
    defaultDuration = 5000
}

Config.Warehouses = {
    [1] = { name = "Rancho Warehouse", coords = vector3(826.694520, -3203.762696, 5.926026), price = 250000, capacity = 42 },
    [2] = { name = "La Mesa Warehouse", coords = vector3(906.210998, -1513.635132, 30.375122), price = 400000, capacity = 42 },
    [3] = { name = "Cypress Flats Warehouse", coords = vector3(804.672546, -2219.472412, 29.414672), price = 350000, capacity = 42 },
    [4] = { name = "LSIA Warehouse", coords = vector3(-1131.257202, -3423.850586, 13.929688), price = 450000, capacity = 42 },
    [5] = { name = "Elysian Island Warehouse", coords = vector3(251.195602, -3075.613282, 5.774414), price = 375000, capacity = 42 },
    [6] = { name = "Davis Quartz Warehouse", coords = vector3(2703.534180, 3457.701172, 55.531860), price = 200000, capacity = 42 },
    [7] = { name = "Paleto Bay Warehouse", coords = vector3(-161.920884, 6189.296875, 31.419800), price = 175000, capacity = 42 },
    [8] = { name = "Sandy Shores Warehouse", coords = vector3(1730.729614, 3707.169190, 34.098876), price = 225000, capacity = 42 }
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
    vector4(-322.892304, -2694.290040, 6.145020, 0.0),
    vector4(1234.6, -2959.8, 9.3, 0.0),
    vector4(287.301086, 310.391204, 105.525268, 0.0),
    vector4(-1042.3, -2023.1, 13.2, 0.0),
    vector4(1158.817626, -1310.386840, 34.907714, 0.0),
    vector4(-539.103272, -1720.153808, 19.389038, 0.0),
    vector4(895.753846, -891.876954, 27.224122, 0.0),
    vector4(-1084.641724, -2477.274658, 14.064454, 0.0),
    vector4(294.791198, -1251.771484, 29.397828, 0.0),
    vector4(-428.650544, -1728.487916, 19.776612, 0.0),
    vector4(1204.8, -3118.1, 5.5, 0.0),
    vector4(-1152.171386, -2170.101074, 13.255738, 0.0),
    vector4(844.404418, -2365.120850, 30.341430, 0.0),
    vector4(152.4, -3211.5, 5.8, 0.0)
}

Config.SellLocations = {
    vector3(-1392.3, 21.4, 53.5),
    vector3(-635.301086, -243.903290, 38.227050),
    vector3(822.145080, -2145.705566, 28.706910),
    vector3(-1484.808838, -901.635192, 10.020508),
    vector3(367.648346, 339.942872, 103.250610),
    vector3(-612.672546, -1600.800048, 26.735474)
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

Config.WarehouseSale = {
    enabled = true,
    refundPercent = 0.5,      -- 0.5 = 50% Rueckerstattung vom Kaufpreis
    payoutAccount = "bank",   -- "bank", "money" oder false fuer Bargeld-Fallback
    requireEmpty = true,      -- Verkauf nur wenn keine Ware eingelagert ist
    blockDuringMissions = true -- Verkauf blockieren, solange Fraktions-Missionen laufen
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
    timeout = {
        enabled = true,
        checkIntervalMs = 5000,
        sourceMinutes = 10,
        sellMinutes = 10
    },
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

Config.SendPoliceDispatch = true
Config.SendPoliceJob = 'police'
Config.SendPoliceTitle = 'Lagerhaus-Alarm'
Config.SendPoliceText = 'Es wird verdächtige Aktivität an einem Lagerhaus gemeldet!'

Config.Dispatch = {
    provider = "roadphone", -- "roadphone" oder "legacy"
    fallbackToLegacy = true,
    roadphone = {
        resource = "roadphone",
        jobName = "police"
    }
}

-- Dispatch-Haeufigkeit und Abstand zwischen Dispatches
Config.DispatchThrottle = {
    enabled = true,
    default = {
        cooldownMs = 0,       -- 0 = kein globales Zeitlimit
        minDistance = 0.0,    -- 0 = kein globaler Mindestabstand
        chanceMultiplier = 1.0
    },
    source = {
        cooldownMs = 30000,   -- mindestens 30s zwischen Source-Dispatches
        minDistance = 60.0,   -- mindestens 60m Abstand
        chanceMultiplier = 1.0
    },
    sell = {
        cooldownMs = 45000,   -- mindestens 45s zwischen Sell-Dispatches
        minDistance = 150.0,  -- mindestens 150m Abstand
        chanceMultiplier = 1.0
    }
}

Config.Delivery = {
    vehicleModel = "mule",
    requireDriver = true,
    trunkLoadTimeoutMs = 3000,
    spawnOffset = vector3(4.0, 0.0, 0.0),
    platePrefix = "S",
    plateMin = 100,
    plateMax = 999
}
